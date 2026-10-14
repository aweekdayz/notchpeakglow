import AppKit
import SwiftUI
import ServiceManagement

@MainActor final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show() {
        // An accessory app has no menu bar. Present as a regular app while Settings is open,
        // so the menu bar and its commands are visible; revert when the window closes.
        NSApp.setActivationPolicy(.regular)
        AppState.shared.settingsVisible = true
        AppState.shared.refreshPower()
        // Establish active-app appearance before the initially selected row is rendered.
        NSApp.activate(ignoringOtherApps: true)
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let w = SettingsWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        w.title = "PeakGlow Settings"
        w.isReleasedWhenClosed = false
        w.minSize = NSSize(width: 700, height: 540)
        w.toolbarStyle = .unified
        w.setFrameAutosaveName("PeakGlowSettings")
        w.alphaValue = 0
        let hosting = NSHostingView(rootView: SettingsView(onReady: { [weak w] in
            // Publish initial selection after mounting, then reveal its settled layout.
            DispatchQueue.main.async { [weak w] in
                guard let w else { return }
                w.contentView?.needsLayout = true
                w.contentView?.layoutSubtreeIfNeeded()
                w.contentView?.displayIfNeeded()
                w.alignResetToolbar()
                w.alphaValue = 1
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
        w.makeKeyAndOrderFront(nil)
        window = w
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
        } footer: {
            SettingsNote("The menu bar icon shows system power and lets you choose a Glow mode, open Settings or quit, without the pointer.")
        }
        Section {
            slider("Hover delay", binding(\.hoverDwell), in: 0...0.8,
                   value: String(format: "%.0f ms", s.hoverDwell * 1000), step: 0.01, unit: "ms", scale: 1000,
                   explanation: "How long to hover over the notch before the controls open.")
        } header: {
            Text("Notch controls")
        } footer: {
            SettingsNote("Move away or press Esc to close the controls. In Auto, a connected game controller pauses the glow.")
        }
        Section {
            Toggle("Warn when the Mac runs hot", isOn: binding(\.overheatAlertEnabled))
        } header: {
            Text("Temperature")
        } footer: {
            SettingsNote("The glow turns orange when the temperature stays high. It is a hint, not a hardware safety feature.")
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
        } footer: {
            SettingsNote("Auto follows your Mac's power. Off turns the glow off. Mid, High and Hot are previews: they show the glow as it looks at medium power, at high power and with the temperature warning, so you can tune its colors and brightness. Choose Auto when you are done.")
        }
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(powerNowText)
                        .font(.title2.weight(.semibold))
                        .monospacedDigit()
                    Spacer()
                    Text(power.reading.availability == .current ? "System power" : "Power data unavailable")
                        .foregroundStyle(.secondary)
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
        } footer: {
            SettingsNote("The colors are the glow's own, from low power on the left to high power on the right. The lit part shows where your Mac is now.")
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
        } footer: {
            SettingsNote("Different Macs draw different power, so these start at values suited to your MacBook. Adjust them until the glow matches how busy your Mac feels.")
        }
        Section {
            Toggle("Keep a faint glow when idle", isOn: binding(\.ambientGlow))
            slider("Glow size", binding(\.glowScale), in: 0.4...1.6,
                   value: "\(Int(s.glowScale * 100))%",
                   explanation: "How far the light spreads from the notch.")
            slider("Brightness", binding(\.glowIntensity), in: 0.2...2,
                   value: "\(Int(s.glowIntensity * 100))%")
            Picker("Wallpaper", selection: binding(\.glowWallpaper)) {
                Text("Automatic").tag(0)
                Text("Light").tag(1)
                Text("Dark").tag(2)
            }
            SettingsNote("Automatic follows the system appearance. Choose Light if the glow is hard to see on a bright wallpaper, or Dark for a dark one.")
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
                       value: "\(Int(s.mediumAlpha * 100))%",
                       explanation: "Opacity of the glow at moderate power.")
                slider("Breathing rate", binding(\.pulseHz), in: 0.1...2,
                       value: String(format: "%.1f Hz", s.pulseHz), step: 0.1, unit: "Hz",
                       explanation: "Speed of the slow pulse at high power.")
                slider("HDR gain", binding(\.hdrFactor), in: 1...8,
                       value: String(format: "%.1f×", s.hdrFactor), step: 0.1, unit: "×",
                       explanation: "Brightness above standard white. HDR headroom depends on your display and its brightness.")
                slider("Maximum frame rate", binding(\.frameRate), in: 15...60,
                       value: "\(Int(s.frameRate)) fps", step: 1, unit: "fps",
                       explanation: "Used while the glow changes. It slows to 30 fps when nothing is moving. Higher is smoother and uses more energy.")
                slider("Warning brightness", binding(\.overheatGain), in: 0.5...2,
                       value: String(format: "%.1f×", s.overheatGain), step: 0.1, unit: "×",
                       explanation: "Brightness of the orange temperature warning.")
                slider("Warning size", binding(\.overheatScale), in: 0.6...1.8,
                       value: "\(Int(s.overheatScale * 100))%",
                       explanation: "How far the warning glow spreads.")
                slider("Dimming margin", binding(\.hysteresisWatts), in: 1...10,
                       value: String(format: "%.1f W", s.hysteresisWatts), step: 0.1, unit: "W",
                       explanation: "Power must drop this far below a threshold before the glow dims.")
                slider("Transition delay", binding(\.holdOnSeconds), in: 0.5...10,
                       value: String(format: "%.1f s", s.holdOnSeconds), step: 0.1, unit: "s",
                       explanation: "Time above a threshold before brightening. Dimming waits 2 seconds longer.")
                slider("Sampling interval", binding(\.sampleInterval), in: 0.2...3,
                       value: String(format: "%.1f s", s.sampleInterval), step: 0.1, unit: "s",
                       explanation: "Time between power readings. Shorter intervals update more often and use more resources.")
            }
        } header: {
            Text("Advanced")
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
                ? "Copy Diagnostics puts the Mac model, macOS version and sensor status on the clipboard for a bug report. It contains no serial number or personal data."
                : "Glow and notch controls require a built-in notch display. External displays and closed-display mode are not supported.")
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
    case general, glow, about
    var id: Self { self }
    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .glow: "sparkles"
        case .about: "info.circle"
        }
    }
    var title: String {
        switch self {
        case .general: "General"
        case .glow: "Glow"
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
