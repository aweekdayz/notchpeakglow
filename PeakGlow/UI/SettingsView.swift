import AppKit
import SwiftUI
import ServiceManagement

@MainActor final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?
    /// True while the window is being built out of sight, shortly after launch.
    private var warming = false
    private var showWhenReady = false

    /// Build the window a moment after launch, while nobody is waiting for it. The first build
    /// (toolbar, split view and first layout of SwiftUI) takes one to several seconds on the main
    /// thread, which showed as a freeze when it happened on the first click. It is invisible
    /// (zero alpha, no mouse events, no activation) and is taken off screen when it has settled.
    func prewarm() {
        guard window == nil, !warming else { return }
        warming = true
        let w = makeWindow()
        window = w
        w.ignoresMouseEvents = true
        w.orderFrontRegardless()
        // If the window never reports ready, do not leave Settings unable to open.
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self, weak w] in
            MainActor.assumeIsolated {
                guard let self, self.warming, let w else { return }
                self.warming = false
                w.orderOut(nil)
                w.ignoresMouseEvents = false
                if self.showWhenReady { self.showWhenReady = false; self.show() }
            }
        }
    }

    func show() {
        // Asked for while it is still being built: open it as soon as it has settled.
        if warming { showWhenReady = true; return }
        // An accessory app has no menu bar. Present as a regular app while Settings is open,
        // so the menu bar and its commands are visible; revert when the window closes.
        NSApp.setActivationPolicy(.regular)
        AppState.shared.settingsVisible = true
        AppState.shared.refreshPower()
        // Establish active-app appearance before the initially selected row is rendered.
        NSApp.activate(ignoringOtherApps: true)
        if let window {
            window.alphaValue = 1
            bringToFront(window)
            return
        }
        let w = makeWindow()
        w.center()
        window = w
        bringToFront(w)
    }

    /// Make Settings the front window of an active app. Right after the activation policy changes
    /// from background to regular the system may not honour the first request, which left the
    /// window behind other apps' windows and drawn as inactive (gray window buttons). So ask,
    /// check, and ask again a few times over the next second, stopping as soon as it has worked.
    private func bringToFront(_ w: NSWindow, attempt: Int = 0) {
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        w.orderFrontRegardless()
        let delays: [TimeInterval] = [0.05, 0.12, 0.25, 0.5, 0.9]
        guard attempt < delays.count else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delays[attempt]) { [weak self, weak w] in
            MainActor.assumeIsolated {
                guard let self, let w, w.isVisible, AppState.shared.settingsVisible else { return }
                if NSApp.isActive && w.isKeyWindow { return }
                self.bringToFront(w, attempt: attempt + 1)
            }
        }
    }

    private func makeWindow() -> NSWindow {
        let w = SettingsWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false)
        w.title = "PeakGlow Settings"
        w.isReleasedWhenClosed = false
        w.minSize = NSSize(width: 700, height: 540)
        w.toolbarStyle = .unified
        w.setFrameAutosaveName("PeakGlowSettings")
        w.alphaValue = 0
        let hosting = NSHostingView(rootView: SettingsView(onReady: { [weak self, weak w] in
            // Publish initial selection after mounting, then reveal its settled layout.
            DispatchQueue.main.async { [weak self, weak w] in
                guard let self, let w else { return }
                w.contentView?.needsLayout = true
                w.contentView?.layoutSubtreeIfNeeded()
                w.contentView?.displayIfNeeded()
                w.alignResetToolbar()
                if self.warming {
                    // Built out of sight: put it away until it is asked for.
                    self.warming = false
                    w.orderOut(nil)
                    w.ignoresMouseEvents = false
                    if self.showWhenReady {
                        self.showWhenReady = false
                        self.show()
                    }
                } else {
                    w.alphaValue = 1
                }
            }
        }))
        // The window owns its bounds. Avoid repeated min/ideal/max content measurements.
        hosting.sizingOptions = []
        w.contentView = hosting
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: w, queue: .main) { _ in
            MainActor.assumeIsolated {
                AppState.shared.settingsVisible = false
                _ = NSApp.setActivationPolicy(.accessory)
            }
        }
        w.center()
        return w
    }
}

/// The AppKit window owns native toolbar spacing; SwiftUI owns the controls.
private final class SettingsWindow: NSWindow {
    override func update() {
        super.update()
        alignResetToolbar()
    }

    func alignResetToolbar() {
        guard let toolbar, toolbar.items.count >= 2 else { return }
        if !toolbar.centeredItemIdentifiers.isEmpty { toolbar.centeredItemIdentifiers = [] }
        let actionIndex = toolbar.items.count - 1
        // Reset is the final action. Use NSToolbar's real flexible-space item,
        // rather than a hosted SwiftUI spacer with an intrinsic view width.
        if toolbar.items[actionIndex - 1].itemIdentifier != .flexibleSpace {
            toolbar.insertItem(withItemIdentifier: .flexibleSpace, at: actionIndex)
        }
    }
}

struct SettingsView: View {
    var onReady: () -> Void = {}
    @ObservedObject private var s = AppSettings.shared
    @State private var selection: SettingsPage?
    @State private var initializedSelection = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @FocusState private var sidebarFocused: Bool
    @State private var loginEnabled = Self.loginRequested
    @State private var loginNeedsApproval = SMAppService.mainApp.status == .requiresApproval
    @State private var loginError: String?
    @State private var confirmReset = false
    @State private var diagnosticsCopied = false
    @State private var advancedExpanded = false
    @ObservedObject private var power = AppState.shared.power
    @ObservedObject private var app = AppState.shared
    @ObservedObject private var updates = UpdateController.shared
    @ObservedObject private var battery = AppState.shared.battery
    @State private var notchDisplayAvailable = NotchedScreenFinder.find() != nil

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $selection) {
                ForEach(SettingsPage.allCases) { page in
                    NavigationLink(value: page) {
                        Label(page.title, systemImage: page.symbol)
                    }
                    .tag(page)
                }
            }
            .listStyle(.sidebar)
            .toolbar(removing: .sidebarToggle)
            .focused($sidebarFocused)
            .navigationSplitViewColumnWidth(180)
        } detail: {
            Form {
                switch selection ?? .general {
                case .general:
                    generalPage
                case .glow:
                    glowPage
                case .battery:
                    batteryPage
                case .about:
                    aboutPage
                }
            }
            .formStyle(.grouped)
            .toolbar(removing: .sidebarToggle)
            .navigationTitle((selection ?? .general).title)
        }
        .toolbar(removing: .sidebarToggle)
        .toolbar {
            // Both toolbar items keep the same identity through sidebar transitions.
            ToolbarItem(id: "PeakGlowSidebarToggle", placement: .navigation) { sidebarToggle }
            ToolbarItem(id: "PeakGlowReset", placement: .automatic) {
                resetButton
            }
        }
        .task {
            guard !initializedSelection else { return }
            initializedSelection = true
            selection = .general
            sidebarFocused = true
            onReady()
        }
        // Selection does not imply keyboard focus. Initialize the native sidebar
        // as the focus target without overriding later user-directed navigation.
        .defaultFocus($sidebarFocused, true)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshLoginStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            notchDisplayAvailable = NotchedScreenFinder.find() != nil
        }
        .navigationSplitViewStyle(.prominentDetail)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .alert("Reset settings?", isPresented: $confirmReset) {
            Button("Cancel", role: .cancel) {}
            Button("Reset") {
                s.resetAll()
                AppState.shared.preview = .auto
            }
        } message: {
            Text("Restore the default appearance and recommended load thresholds.")
        }
    }

    // MARK: - Pages

    @ViewBuilder private var generalPage: some View {
        Section {
            Toggle("Open PeakGlow at login", isOn: $loginEnabled)
                .onChange(of: loginEnabled) { _, enabled in
                    updateLogin(enabled)
                }
            if loginNeedsApproval {
                SettingsNote("Allow PeakGlow in System Settings to open at login.")
                Button("Open Login Items…") {
                    SMAppService.openSystemSettingsLoginItems()
                }
                .nativeGlassAction()
            }
            if let loginError {
                Text(loginError)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text("Startup")
        }
        Section {
            Toggle("Show menu bar icon", isOn: binding(\.menuBarIcon))
        } header: {
            Text("Menu bar")
        }
        Section {
            slider("Hover delay", binding(\.hoverDwell), in: 0...0.8,
                   value: String(format: "%.0f ms", s.hoverDwell * 1000), step: 0.01, unit: "ms", scale: 1000)
            Toggle("Haptic feedback", isOn: binding(\.hapticsEnabled))
        } header: {
            Text("Notch controls")
        } footer: {
            SettingsNote("In Auto, a connected game controller pauses the glow.")
        }
        Section {
            Toggle("Warn when the Mac runs hot", isOn: binding(\.overheatAlertEnabled))
        } header: {
            Text("Temperature")
        } footer: {
            SettingsNote("The glow turns orange when the temperature stays high. This is a hint, not a safety feature.")
        }
    }

    @ViewBuilder private var glowPage: some View {
        Section {
            Picker("Glow mode", selection: $app.preview) {
                ForEach(PreviewLevel.displayOrder, id: \.self) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel("Glow mode")
            Text(app.preview.explanation)
                .foregroundStyle(.secondary)
        } header: {
            Text("Glow mode")
        }
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(powerNowText)
                        .font(.title2.weight(.semibold))
                        .monospacedDigit()
                    Spacer()
                    if power.reading.availability != .current {
                        Text("Power data unavailable")
                            .foregroundStyle(.secondary)
                    }
                }
                PowerMeter(watts: gaugeWatts, medium: s.mediumWatts, high: s.highWatts,
                           maximum: gaugeMaximum, gradient: gaugeGradient)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("System power")
                    .accessibilityValue(power.reading.availability == .current
                        ? "\(powerNowText). Brighter glow from \(Int(s.mediumWatts)) watts, strongest glow from \(Int(s.highWatts)) watts."
                        : "Unavailable")
            }
            .padding(.vertical, 4)
        } header: {
            Text("Power now")
        }
        Section {
            slider("Brighter glow from", Binding(get: { s.mediumWatts },
                set: { s.mediumWatts = min($0, s.highWatts - 1) }),
                in: 8...60, value: "\(Int(s.mediumWatts)) W", step: 1, unit: "W",
                explanation: "Above this power the glow gets brighter and turns green.")
            slider("Strongest glow from", Binding(get: { s.highWatts },
                set: { s.highWatts = max($0, s.mediumWatts + 1) }),
                in: 9...90, value: "\(Int(s.highWatts)) W", step: 1, unit: "W",
                explanation: "Above this power the glow is at its strongest and turns yellow.")
            Button {
                s.mediumWatts = MachineProfile.current.suggestedMediumWatts
                s.highWatts = MachineProfile.current.suggestedHighWatts
            } label: {
                Text("Use Recommended for This Mac").foregroundStyle(.primary)
            }
            .nativeGlassAction()
        } header: {
            Text("When the glow changes")
        }
        Section {
            Toggle("Keep a faint glow when idle", isOn: binding(\.ambientGlow))
            Toggle("Show charging in the glow", isOn: binding(\.chargingGlow))
            slider("Glow size", binding(\.glowScale), in: 0.4...1.6,
                   value: "\(Int(s.glowScale * 100))%")
            slider("Brightness", binding(\.glowIntensity), in: 0.2...2,
                   value: "\(Int(s.glowIntensity * 100))%")
            Picker("Wallpaper", selection: binding(\.glowWallpaper)) {
                Text("Automatic").tag(0)
                Text("Light").tag(1)
                Text("Dark").tag(2)
            }
            SettingsNote("Choose Light if the glow is hard to see on a bright wallpaper.")
            Button { s.resetAppearance() } label: {
                Text("Use Default Look").foregroundStyle(.primary)
            }
            .nativeGlassAction()
        } header: {
            Text("Look")
        }
        Section {
            DisclosureGroup("Fine-tuning", isExpanded: $advancedExpanded) {
                slider("Base opacity", binding(\.mediumAlpha), in: 0.2...0.8,
                       value: "\(Int(s.mediumAlpha * 100))%")
                slider("Breathing rate", binding(\.pulseHz), in: 0.1...2,
                       value: String(format: "%.1f Hz", s.pulseHz), step: 0.1, unit: "Hz")
                slider("HDR gain", binding(\.hdrFactor), in: 1...8,
                       value: String(format: "%.1f×", s.hdrFactor), step: 0.1, unit: "×",
                       explanation: "Brightness above standard white. It depends on your display.")
                slider("Maximum frame rate", binding(\.frameRate), in: 15...60,
                       value: "\(Int(s.frameRate)) fps", step: 1, unit: "fps",
                       explanation: "Higher is smoother and uses more energy. It slows to 30 fps when nothing moves.")
                slider("Warning brightness", binding(\.overheatGain), in: 0.5...2,
                       value: String(format: "%.1f×", s.overheatGain), step: 0.1, unit: "×")
                slider("Warning size", binding(\.overheatScale), in: 0.6...1.8,
                       value: "\(Int(s.overheatScale * 100))%")
                slider("Dimming margin", binding(\.hysteresisWatts), in: 1...10,
                       value: String(format: "%.1f W", s.hysteresisWatts), step: 0.1, unit: "W",
                       explanation: "Power must drop this far below a threshold before the glow dims.")
                slider("Transition delay", binding(\.holdOnSeconds), in: 0.5...10,
                       value: String(format: "%.1f s", s.holdOnSeconds), step: 0.1, unit: "s",
                       explanation: "Time above a threshold before brightening. Dimming waits 2 seconds longer.")
                slider("Sampling interval", binding(\.sampleInterval), in: 0.2...3,
                       value: String(format: "%.1f s", s.sampleInterval), step: 0.1, unit: "s",
                       explanation: "Shorter uses more energy.")
            }
        } header: {
            Text("Advanced")
        }
    }

    @ViewBuilder private var batteryPage: some View {
        if let b = battery.snapshot {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(b.percent)%")
                            .font(.title2.weight(.semibold))
                            .monospacedDigit()
                        Spacer()
                        Text(b.statusText)
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: Double(b.percent), total: 100)
                        .tint(b.isChargingNow ? .green : .accentColor)
                        .accessibilityLabel("Charge")
                        .accessibilityValue("\(b.percent) percent")
                    if let time = b.timeText {
                        Text(time)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Charge")
            }
            Section {
                if let health = b.healthPercent {
                    LabeledContent("Maximum capacity", value: "\(health)%")
                }
                if let design = b.designCapacity, let maximum = b.maximumCapacity {
                    LabeledContent("Capacity", value: "\(maximum) of \(design) mAh")
                }
                if let cycles = b.cycleCount {
                    LabeledContent("Cycle count", value: b.designCycleCount.map { "\(cycles) of \($0)" } ?? "\(cycles)")
                }
                if let temperature = b.temperature {
                    LabeledContent("Temperature", value: String(format: "%.1f °C", temperature))
                }
            } header: {
                Text("Health")
            }
            Section {
                LabeledContent("Power adapter", value: b.externalConnected ? (b.adapterWatts.map { "\($0) W" } ?? "Connected") : "Not connected")
                if let watts = b.batteryWatts, abs(watts) >= 0.1 {
                    LabeledContent(watts > 0 ? "Charging power" : "Battery power", value: String(format: "%.1f W", abs(watts)))
                }
            } header: {
                Text("Power")
            }
        } else {
            Section {
                Text("This Mac has no battery.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var aboutPage: some View {
        Section {
            LabeledContent("Model") {
                Text(MachineProfile.current.summary)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
            LabeledContent("Display", value: notchDisplayAvailable
                           ? "Built-in notch display available" : "Notch display unavailable")
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(Diagnostics.report(), forType: .string)
                diagnosticsCopied = true
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    diagnosticsCopied = false
                }
            } label: {
                Text(diagnosticsCopied ? "Copied" : "Copy Diagnostics").foregroundStyle(.primary)
            }
            .nativeGlassAction()
            .accessibilityHint("Copies the Mac model, macOS version and sensor status to the clipboard for a bug report")
        } header: {
            Text("This Mac")
        } footer: {
            SettingsNote(notchDisplayAvailable
                ? "Copy Diagnostics copies the Mac model, macOS version and sensor status for a bug report, with no serial number or personal data."
                : "The glow and the controls need a built-in notch display.")
        }
        Section {
            Toggle("Check for updates automatically", isOn: $updates.automaticChecks)
            Button("Check for Updates…") {
                updates.checkForUpdates(nil)
            }
            .nativeGlassAction()
            .disabled(!updates.canCheckForUpdates)
        } header: {
            Text("Updates")
        }
        Section {
            LabeledContent("Version", value: Self.versionText)
            LabeledContent("Maintained by", value: "aweekdayz")
            Button("Credits and Licensing…") {
                (NSApp.delegate as? AppDelegate)?.showAbout()
            }
            .nativeGlassAction()
            Link("Source code and releases", destination: URL(string: "https://github.com/aweekdayz/notchpeakglow")!)
        } header: {
            Text("PeakGlow")
        }
    }

    // MARK: - Power gauge

    private static var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    private var gaugeWatts: Double { power.reading.availability == .current ? power.reading.watts : 0 }
    /// The bar ends where the glow reaches the top of its color ramp.
    private var gaugeMaximum: Double { max(s.highWatts * 1.4, 1) }
    private var powerNowText: String {
        power.reading.availability == .current ? String(format: "%.1f W", power.reading.watts) : "— W"
    }
    /// The glow's own ramp (blue, cyan, green, yellow) laid out by power, so the bar matches the glow.
    private var gaugeGradient: Gradient {
        PowerRamp.gradient(medium: s.mediumWatts, high: s.highWatts)
    }

    private var sidebarToggle: some View {
        Button {
            withAnimation {
                columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
            }
        } label: {
            Label("Toggle Sidebar", systemImage: "sidebar.left")
        }
        .labelStyle(.iconOnly)
        .help(columnVisibility == .detailOnly ? "Show sidebar" : "Hide sidebar")
        .accessibilityLabel(columnVisibility == .detailOnly ? "Show sidebar" : "Hide sidebar")
    }

    private var resetButton: some View {
        Button { confirmReset = true } label: {
            Label("Reset…", systemImage: "arrow.counterclockwise")
                .foregroundStyle(.primary)
        }
        .nativeGlassAction()
        .help("Reset all settings")
    }

    private func binding<T>(_ keyPath: ReferenceWritableKeyPath<AppSettings, T>) -> Binding<T> {
        Binding(get: { s[keyPath: keyPath] }, set: { s[keyPath: keyPath] = $0 })
    }

    private func slider(_ title: String, _ value: Binding<Double>,
                        in range: ClosedRange<Double>, value text: String,
                        step: Double? = nil, unit: String = "", scale: Double = 1,
                        explanation: String? = nil) -> some View {
        NativeSettingsSlider(title: title, value: value, range: range, formattedValue: text,
                             step: step, unit: unit, scale: scale, explanation: explanation)
    }

    private static var loginRequested: Bool {
        let status = SMAppService.mainApp.status
        return status == .enabled || status == .requiresApproval
    }

    private func refreshLoginStatus() {
        loginNeedsApproval = SMAppService.mainApp.status == .requiresApproval
        loginEnabled = Self.loginRequested
    }

    private func updateLogin(_ enabled: Bool) {
        guard enabled != Self.loginRequested else { return }
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            let detail = error as NSError
            loginError = "Could not update launch at login. Try again or check Login Items in System Settings. (\(detail.domain), code \(detail.code))"
        }
        refreshLoginStatus()
    }

}


private enum SettingsPage: String, CaseIterable, Identifiable {
    case general, glow, battery, about
    var id: Self { self }
    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .glow: "sparkles"
        case .battery: "battery.100percent"
        case .about: "info.circle"
        }
    }
    var title: String {
        switch self {
        case .general: "General"
        case .glow: "Glow"
        case .battery: "Battery"
        case .about: "About"
        }
    }
}

private extension View {
    func nativeGlassAction() -> some View {
        self.buttonStyle(.glass)
    }
}

/// One readable secondary text style for inline help and native section footers.
private struct SettingsNote: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Keeps the system slider intact, including its thumb, tracking, and keyboard behavior.
private struct NativeSettingsSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let formattedValue: String
    let step: Double?
    let unit: String
    let scale: Double
    let explanation: String?

    private var sliderValue: Binding<Double> {
        Binding(get: { value }, set: { input in
            guard input.isFinite else { return }
            let adjusted = unit == "fps" ? input.rounded() : input
            value = min(range.upperBound, max(range.lowerBound, adjusted))
        })
    }

    private var numericValue: Binding<Double> {
        Binding(get: { value * scale }, set: { input in
            guard input.isFinite else { return }
            let clamped = min(range.upperBound, max(range.lowerBound, input / scale))
            let rounded = step.map { range.lowerBound + ((clamped - range.lowerBound) / $0).rounded() * $0 } ?? clamped
            value = min(range.upperBound, max(range.lowerBound, rounded))
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
                Spacer(minLength: 12)
                if step != nil {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        TextField("", value: numericValue,
                                  format: .number.precision(.fractionLength(0...1)))
                            // The row already has a title; don't let Form render
                            // a second label inside this compact numeric field.
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                            .frame(width: 64)
                            .help("Allowed range: \(range.lowerBound * scale)–\(range.upperBound * scale) \(unit)")
                            .accessibilityLabel("\(title), numeric value")
                            .accessibilityValue(formattedValue)
                        Text(unit)
                            .foregroundStyle(.secondary)
                            .frame(width: 24, alignment: .leading)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                } else {
                    Text(formattedValue)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 94, alignment: .trailing)
                }
            }
            // Entry precision is not a set of meaningful visual stops.
            // Keep the system's unmarked track; numeric entry supplies precision.
            Slider(value: sliderValue, in: range) { Text(title) }
                .labelsHidden()
                .controlSize(.regular)
                .tint(.accentColor)
                .help(formattedValue)
                .accessibilityLabel(title)
                .accessibilityValue(formattedValue)
            if let explanation {
                SettingsNote(explanation)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }
}
