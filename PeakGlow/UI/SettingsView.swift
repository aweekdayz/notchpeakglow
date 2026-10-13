import AppKit
import SwiftUI
import ServiceManagement

@MainActor final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show() {
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
                switch selection ?? .appearance {
                case .appearance:
                Section {
                    LabeledContent("Model") {
                        Text(MachineProfile.current.summary)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    LabeledContent("Display", value: notchDisplayAvailable
                                   ? "Built-in notch display available" : "Notch display unavailable")
                } header: {
                    Text("Device")
                } footer: {
                    SettingsNote(notchDisplayAvailable
                        ? "Power presets depend on the MacBook family. Adjust thresholds for your chip and workload."
                        : "Glow and hover controls require a built-in notch display. External displays and closed-display mode are not supported.")
                }
                Section {
                    Toggle("Show glow at low load", isOn: binding(\.ambientGlow))
                    slider("Glow size", binding(\.glowScale), in: 0.4...1.6,
                           value: "\(Int(s.glowScale * 100))%")
                    slider("Brightness", binding(\.glowIntensity), in: 0.2...2,
                           value: "\(Int(s.glowIntensity * 100))%")
                    Button { s.resetAppearance() } label: {
                        Text("Use Soft Appearance").foregroundStyle(.primary)
                    }
                    .nativeGlassAction()
                } header: {
                    Text("Glow")
                } footer: {
                    SettingsNote("Auto follows system power. High load adds an ice-blue glow.")
                }
                case .power:
                Section {
                    slider("Full glow threshold", Binding(get: { s.mediumWatts },
                        set: { s.mediumWatts = min($0, s.highWatts - 1) }),
                        in: 8...60, value: "\(Int(s.mediumWatts)) W", step: 1, unit: "W")
                    slider("Boost threshold", Binding(get: { s.highWatts },
                        set: { s.highWatts = max($0, s.mediumWatts + 1) }),
                        in: 9...90, value: "\(Int(s.highWatts)) W", step: 1, unit: "W")
                    Button {
                        s.mediumWatts = MachineProfile.current.suggestedMediumWatts
                        s.highWatts = MachineProfile.current.suggestedHighWatts
                    } label: {
                        Text("Use Recommended Thresholds").foregroundStyle(.primary)
                    }
                    .nativeGlassAction()
                } header: {
                    Text("Power thresholds")
                } footer: {
                    SettingsNote("In Auto, full glow begins at the lower threshold. Boost begins at the higher threshold.")
                }
                case .behavior:
                Section("Startup") {
                    Toggle("Launch at login", isOn: $loginEnabled)
                        .onChange(of: loginEnabled) { _, enabled in
                            updateLogin(enabled)
                        }
                    if loginNeedsApproval {
                        SettingsNote("Allow PeakGlow in System Settings to launch at login.")
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
                }
                Section {
                    Toggle("Temperature alerts", isOn: binding(\.overheatAlertEnabled))
                } header: {
                    Text("Alerts")
                } footer: {
                    SettingsNote("A warm glow highlights elevated temperatures.")
                }
                Section {
                    slider("Hover delay", binding(\.hoverDwell), in: 0...0.8,
                           value: String(format: "%.0f ms", s.hoverDwell * 1000), step: 0.01, unit: "ms", scale: 1000,
                           explanation: "Time over the notch before controls appear.")
                } header: {
                    Text("Interaction")
                } footer: {
                    SettingsNote("Move away or press Esc to close the controls. In Auto, a game controller pauses the glow; previews remain available.")
                }
                case .advanced:
                Section("Rendering") {
                        slider("Soft glow opacity", binding(\.mediumAlpha), in: 0.2...0.8,
                               value: "\(Int(s.mediumAlpha * 100))%")
                        slider("Breathing rate", binding(\.pulseHz), in: 0.1...2,
                               value: String(format: "%.1f Hz", s.pulseHz), step: 0.1, unit: "Hz")
                        slider("HDR gain", binding(\.hdrFactor), in: 1...8,
                               value: String(format: "%.1f×", s.hdrFactor), step: 0.1, unit: "×", explanation: "Brightness above standard white. HDR headroom depends on your display and its brightness.")
                        slider("Frame rate", binding(\.frameRate), in: 15...60,
                               value: "\(Int(s.frameRate)) fps", step: 1, unit: "fps")
                }
                Section("Temperature alerts") {
                    slider("Alert brightness", binding(\.overheatGain), in: 0.5...2,
                           value: String(format: "%.1f×", s.overheatGain), step: 0.1, unit: "×")
                    slider("Alert size", binding(\.overheatScale), in: 0.6...1.8,
                           value: "\(Int(s.overheatScale * 100))%")
                }
                Section("Load response") {
                        slider("Dimming margin", binding(\.hysteresisWatts), in: 1...10,
                               value: String(format: "%.1f W", s.hysteresisWatts), step: 0.1, unit: "W", explanation: "Power must drop this far below a threshold before the glow dims.")
                        slider("Transition delay", binding(\.holdOnSeconds), in: 0.5...10,
                               value: String(format: "%.1f s", s.holdOnSeconds), step: 0.1, unit: "s", explanation: "Time above a threshold before brightening. Dimming waits 2 seconds longer.")
                        slider("Sampling interval", binding(\.sampleInterval), in: 0.2...3,
                               value: String(format: "%.1f s", s.sampleInterval), step: 0.1, unit: "s", explanation: "Time between power readings. Shorter intervals update more often and use more resources.")
                }
                }
            }
            .formStyle(.grouped)
            .toolbar(removing: .sidebarToggle)
            .navigationTitle((selection ?? .appearance).title)
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
            selection = .appearance
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
    case appearance, power, behavior, advanced
    var id: Self { self }
    var symbol: String {
        switch self {
        case .appearance: "sparkles"
        case .power: "bolt"
        case .behavior: "cursorarrow.motionlines"
        case .advanced: "slider.horizontal.3"
        }
    }
    var title: String {
        switch self {
        case .appearance: "Appearance"
        case .power: "Power"
        case .behavior: "Behavior"
        case .advanced: "Advanced"
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
