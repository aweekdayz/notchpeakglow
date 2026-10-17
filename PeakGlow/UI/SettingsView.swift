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
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false)
        w.title = "PeakGlow Settings"
        w.isReleasedWhenClosed = false
        w.minSize = NSSize(width: 700, height: 540)
        w.setFrameAutosaveName("PeakGlowSettings")
        w.alphaValue = 0
        let hosting = NSHostingView(rootView: SettingsView(onReady: { [weak self, weak w] in
            // Publish initial selection after mounting, then reveal its settled layout.
            DispatchQueue.main.async { [weak self, weak w] in
                guard let self, let w else { return }
                w.contentView?.needsLayout = true
                w.contentView?.layoutSubtreeIfNeeded()
                w.contentView?.displayIfNeeded()
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

struct SettingsView: View {
    var onReady: () -> Void = {}
    @ObservedObject private var s = AppSettings.shared
    @State private var selection: SettingsPage?
    @State private var initializedSelection = false
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
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(SettingsPage.allCases) { page in
                    NavigationLink(value: page) {
                        sidebarLabel(page)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .alert("Reset settings?", isPresented: $confirmReset) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                s.resetAll()
                AppState.shared.preview = .auto
            }
        } message: {
            Text("Restore the default appearance and recommended load thresholds.")
        }
    }

    /// Each page has a white symbol on a colored rounded square, as in System Settings. The Battery
    /// entry shows the charge, with a bolt while charging.
    @ViewBuilder private func sidebarLabel(_ page: SettingsPage) -> some View {
        let symbol = page == .battery ? (battery.snapshot.map { BatterySymbol.name($0) } ?? page.symbol) : page.symbol
        Label {
            Text(page.title)
        } icon: {
            Image(systemName: symbol)
                .font(.system(size: page == .battery ? 11 : 13, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(page.badgeColor.gradient, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
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
                LabeledContent("Allow PeakGlow in System Settings to open at login.") {
                    Button("Open Login Items…") {
                        SMAppService.openSystemSettingsLoginItems()
                    }
                }
            }
            if let loginError {
                Text(loginError)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Toggle("Show menu bar icon", isOn: binding(\.menuBarIcon))
        }
        Section {
            slider("Hover delay", binding(\.hoverDwell), in: 0...0.8,
                   value: String(format: "%.0f ms", s.hoverDwell * 1000), step: 0.01)
            Toggle("Haptic feedback", isOn: binding(\.hapticsEnabled))
        } header: {
            Text("Notch controls")
        } footer: {
            Text("In Auto, a connected game controller pauses the glow.")
        }
        Section {
            Toggle("Warn when the Mac runs hot", isOn: binding(\.overheatAlertEnabled))
        } header: {
            Text("Temperature")
        } footer: {
            Text("The glow turns orange when the temperature stays high. This is a hint, not a safety feature.")
        }
        Section {
            Toggle("Check for updates automatically", isOn: $updates.automaticChecks)
            LabeledContent("Check now") {
                Button("Check for Updates…") {
                    updates.checkForUpdates(nil)
                }
                .disabled(!updates.canCheckForUpdates)
            }
        } header: {
            Text("Updates")
        }
        Section {
            LabeledContent("Restore the default settings") {
                Button("Reset…", role: .destructive) { confirmReset = true }
            }
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
            LabeledContent("Suited to this MacBook") {
                Button("Use Recommended") {
                    s.mediumWatts = MachineProfile.current.suggestedMediumWatts
                    s.highWatts = MachineProfile.current.suggestedHighWatts
                }
            }
        } header: {
            Text("When the glow changes")
        }
        Section {
            Toggle("Keep a faint glow when idle", isOn: binding(\.ambientGlow))
            slider("Glow size", binding(\.glowScale), in: 0.4...1.6,
                   value: "\(Int(s.glowScale * 100))%")
            slider("Brightness", binding(\.glowIntensity), in: 0.2...2,
                   value: "\(Int(s.glowIntensity * 100))%")
            Picker("Wallpaper", selection: binding(\.glowWallpaper)) {
                Text("Automatic").tag(0)
                Text("Light").tag(1)
                Text("Dark").tag(2)
            }
            LabeledContent("Restore the default look") {
                Button("Use Default Look") { s.resetAppearance() }
            }
        } header: {
            Text("Look")
        } footer: {
            Text("Choose Light if the glow is hard to see on a bright wallpaper.")
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
        BatterySettingsContent(snapshot: battery.snapshot, chargingGlow: binding(\.chargingGlow),
                               chargeIsland: binding(\.chargeIsland))
    }

    @ViewBuilder private var aboutPage: some View {
        Section {
            VStack(spacing: 6) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .frame(width: 80, height: 80)
                    .accessibilityHidden(true)
                Text("PeakGlow")
                    .font(.title2.weight(.semibold))
                Text("Version \(Self.versionText)")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .accessibilityElement(children: .combine)
        }
        Section {
            LabeledContent("Model") {
                Text(MachineProfile.current.summary)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
            LabeledContent("Display", value: notchDisplayAvailable
                           ? "Built-in notch display available" : "Notch display unavailable")
            LabeledContent("Report a problem") {
                Button(diagnosticsCopied ? "Copied" : "Copy Diagnostics") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(Diagnostics.report(), forType: .string)
                    diagnosticsCopied = true
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        diagnosticsCopied = false
                    }
                }
                .accessibilityHint("Copies the Mac model, macOS version and sensor status to the clipboard for a bug report")
            }
        } header: {
            Text("This Mac")
        } footer: {
            Text(notchDisplayAvailable
                ? "Copy Diagnostics copies the Mac model, macOS version and sensor status for a bug report, with no serial number or personal data."
                : "The glow and the controls need a built-in notch display.")
        }
        Section {
            LabeledContent("Maintained by", value: "aweekdayz")
            LabeledContent("Credits and licensing") {
                Button("Show…") {
                    (NSApp.delegate as? AppDelegate)?.showAbout()
                }
            }
            LabeledContent("Source code") {
                Link("GitHub", destination: URL(string: "https://github.com/aweekdayz/notchpeakglow")!)
            }
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

    private func binding<T>(_ keyPath: ReferenceWritableKeyPath<AppSettings, T>) -> Binding<T> {
        Binding(get: { s[keyPath: keyPath] }, set: { s[keyPath: keyPath] = $0 })
    }

    private func slider(_ title: String, _ value: Binding<Double>,
                        in range: ClosedRange<Double>, value text: String,
                        step: Double? = nil, unit: String = "", scale: Double = 1,
                        explanation: String? = nil) -> some View {
        SettingSliderRow(title: title, value: value, range: range, step: step, valueText: text, note: explanation)
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
    var badgeColor: Color {
        switch self {
        case .general: .gray
        case .glow: .indigo
        case .battery: .green
        case .about: .blue
        }
    }
}

/// A setting with a slider: the label on the left, the system slider and its value on the right, and a
/// short note underneath when one is needed.
private struct SettingSliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double?
    let valueText: String
    let note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent(title) {
                HStack(spacing: 10) {
                    // The slider is continuous (a stepped one draws a row of tick dots); the value is
                    // rounded to its step as it is set.
                    Slider(value: Binding(
                        get: { value },
                        set: { input in
                            guard input.isFinite else { return }
                            let rounded = step.map { range.lowerBound + ((input - range.lowerBound) / $0).rounded() * $0 } ?? input
                            value = min(range.upperBound, max(range.lowerBound, rounded))
                        }), in: range)
                    .labelsHidden()
                    .frame(minWidth: 140, idealWidth: 220, maxWidth: 260)
                    Text(valueText)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 62, alignment: .trailing)
                }
            }
            if let note {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(valueText)
    }
}
