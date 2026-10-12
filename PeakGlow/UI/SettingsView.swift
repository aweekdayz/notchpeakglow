import AppKit
import SwiftUI
import ServiceManagement

final class SettingsWindowController {
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
                    LabeledContent("Device", value: MachineProfile.current.summary)
                    Text("A subtle glow at low load, brighter as power rises.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Section("Appearance") {
                    Toggle("Show glow at low load", isOn: binding(\.ambientGlow))
                    slider("Glow size", binding(\.glowScale), in: 0.4...1.6,
                           value: "\(Int(s.glowScale * 100))%")
                    slider("Brightness", binding(\.glowIntensity), in: 0.2...2,
                           value: "\(Int(s.glowIntensity * 100))%")
                    Text("Soft light follows the notch. High load shifts to ice blue.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button { s.resetAppearance() } label: {
                        Text("Use Soft Appearance").foregroundStyle(.primary)
                    }
                    .nativeGlassAction()
                }
                case .power:
                Section("Load") {
                    slider("Full glow threshold", Binding(get: { s.mediumWatts },
                        set: { s.mediumWatts = min($0, s.highWatts - 1) }),
                        in: 8...60, value: "\(Int(s.mediumWatts)) W", step: 1, unit: "W")
                    slider("Boost threshold", Binding(get: { s.highWatts },
                        set: { s.highWatts = max($0, s.mediumWatts + 1) }),
                        in: 9...90, value: "\(Int(s.highWatts)) W", step: 1, unit: "W")
                    Text("Auto uses a subtle glow below the full glow threshold. Boost begins at the higher threshold.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button {
                        s.mediumWatts = MachineProfile.current.suggestedMediumWatts
                        s.highWatts = MachineProfile.current.suggestedHighWatts
                    } label: {
                        Text("Use Recommended Thresholds").foregroundStyle(.primary)
                    }
                    .nativeGlassAction()
                }
                case .behavior:
                Section("Behavior") {
                    Toggle("Launch at login", isOn: $loginEnabled)
                        .onChange(of: loginEnabled) { _, enabled in
                            updateLogin(enabled)
                        }
                    if loginNeedsApproval {
                        Text("Launch at login needs your approval in System Settings.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Open Login Items…") {
                            SMAppService.openSystemSettingsLoginItems()
                        }
                        .nativeGlassAction()
                    }
                    Toggle("Temperature alerts", isOn: binding(\.overheatAlertEnabled))
                    slider("Hover delay", binding(\.hoverDwell), in: 0...0.8,
                           value: String(format: "%.0f ms", s.hoverDwell * 1000), step: 0.01, unit: "ms", scale: 1000,
                           explanation: "Hover to preview controls. Click to keep them open for keyboard use; press Esc to close.")
                    Text("Auto pauses the glow while a game controller is connected. Preview modes remain available.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let loginError {
                        Text(loginError).font(.caption).foregroundStyle(.red)
                    }
                }
                case .advanced:
                Section("Rendering") {
                        slider("Soft glow opacity", binding(\.mediumAlpha), in: 0.2...0.8,
                               value: "\(Int(s.mediumAlpha * 100))%")
                        slider("Breathing rate", binding(\.pulseHz), in: 0.1...2,
                               value: String(format: "%.1f Hz", s.pulseHz), step: 0.1, unit: "Hz")
                        slider("HDR gain", binding(\.hdrFactor), in: 1...8,
                               value: String(format: "%.1f×", s.hdrFactor), step: 0.1, unit: "×", explanation: "Brightness above standard white on HDR displays. Available headroom depends on your display and brightness.")
                        slider("Frame rate", binding(\.frameRate), in: 15...60,
                               value: "\(Int(s.frameRate)) fps", step: 1, unit: "fps")
                }
                Section("Temperature alerts") {
                    slider("Alert brightness", binding(\.overheatGain), in: 0.5...8,
                           value: String(format: "%.1f×", s.overheatGain), step: 0.1, unit: "×")
                    slider("Alert size", binding(\.overheatScale), in: 0.6...1.8,
                           value: "\(Int(s.overheatScale * 100))%")
                }
                Section("Load response") {
                        slider("Hysteresis", binding(\.hysteresisWatts), in: 1...10,
                               value: String(format: "%.1f W", s.hysteresisWatts), step: 0.1, unit: "W", explanation: "Power must fall this far below a threshold before the glow returns to a lower level.")
                        slider("Transition delay", binding(\.holdOnSeconds), in: 0.5...10,
                               value: String(format: "%.1f s", s.holdOnSeconds), step: 0.1, unit: "s", explanation: "Power must stay above a threshold for this long before the glow increases. Decreases wait at least 1 second and 2 seconds longer than this setting.")
                        slider("Sampling interval", binding(\.sampleInterval), in: 0.2...3,
                               value: String(format: "%.1f s", s.sampleInterval), step: 0.1, unit: "s", explanation: "Time between power readings. Shorter intervals refresh more often and use more resources.")
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
            loginError = "Could not update login item: \(error.localizedDescription)"
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
            HStack {
                Text(title)
                Spacer()
                if step != nil {
                    TextField(title, value: numericValue,
                              format: .number.precision(.fractionLength(0...1)))
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                        .frame(width: 64)
                        .help("Allowed range: \(range.lowerBound * scale)–\(range.upperBound * scale) \(unit)")
                        .accessibilityLabel("\(title), numeric value")
                        .accessibilityValue(formattedValue)
                    Text(unit).foregroundStyle(.secondary)
                } else {
                    Text(formattedValue)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
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
                Text(explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }
}
