import AppKit
import SwiftUI
import ServiceManagement

final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 620),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered, defer: false)
        w.title = "PeakGlow Settings"
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: SettingsView())
        w.center()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = w
    }
}

struct SettingsView: View {
    @ObservedObject private var s = AppSettings.shared
    @State private var showAdvanced = false
    @State private var loginEnabled = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @State private var confirmReset = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
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
                    Button("Use Soft Appearance") {
                        s.resetAppearance()
                    }
                }

                Section("Load") {
                    slider("Full glow threshold", Binding(get: { s.mediumWatts },
                        set: { s.mediumWatts = min($0, s.highWatts - 1) }),
                        in: 8...60, value: "\(Int(s.mediumWatts)) W")
                    slider("Boost threshold", Binding(get: { s.highWatts },
                        set: { s.highWatts = max($0, s.mediumWatts + 1) }),
                        in: 9...90, value: "\(Int(s.highWatts)) W")
                    Button("Use Recommended Thresholds") {
                        s.mediumWatts = MachineProfile.current.suggestedMediumWatts
                        s.highWatts = MachineProfile.current.suggestedHighWatts
                    }
                }

                Section("Behavior") {
                    Toggle("Launch at login", isOn: $loginEnabled)
                        .onChange(of: loginEnabled) { _, enabled in
                            updateLogin(enabled)
                        }
                    Toggle("Temperature alerts", isOn: binding(\.overheatAlertEnabled))
                    slider("Hover delay", binding(\.hoverDwell), in: 0.2...1.5,
                           value: String(format: "%.1f s", s.hoverDwell))
                    if let loginError {
                        Text(loginError).font(.caption).foregroundStyle(.red)
                    }
                }

                Section {
                    DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
                        slider("Soft glow opacity", binding(\.mediumAlpha), in: 0.2...0.8,
                               value: "\(Int(s.mediumAlpha * 100))%")
                        slider("Breathing rate", binding(\.pulseHz), in: 0.1...2,
                               value: String(format: "%.1f Hz", s.pulseHz))
                        slider("HDR gain", binding(\.hdrFactor), in: 1...8,
                               value: String(format: "%.1f×", s.hdrFactor))
                        slider("Alert brightness", binding(\.overheatGain), in: 0.5...8,
                               value: String(format: "%.1f×", s.overheatGain))
                        slider("Alert size", binding(\.overheatScale), in: 0.6...1.8,
                               value: "\(Int(s.overheatScale * 100))%")
                        slider("Frame rate", binding(\.frameRate), in: 15...60,
                               value: "\(Int(s.frameRate)) fps")
                        slider("Hysteresis", binding(\.hysteresisWatts), in: 1...10,
                               value: String(format: "%.1f W", s.hysteresisWatts))
                        slider("Transition delay", binding(\.holdOnSeconds), in: 0.5...10,
                               value: String(format: "%.1f s", s.holdOnSeconds))
                        slider("Sampling interval", binding(\.sampleInterval), in: 0.2...3,
                               value: String(format: "%.1f s", s.sampleInterval))
                    }
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Text("PeakGlow")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Reset Settings…") { confirmReset = true }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
        .frame(width: 520, height: 620)
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

    private func binding<T>(_ keyPath: ReferenceWritableKeyPath<AppSettings, T>) -> Binding<T> {
        Binding(get: { s[keyPath: keyPath] }, set: { s[keyPath: keyPath] = $0 })
    }

    private func slider(_ title: String, _ value: Binding<Double>,
                        in range: ClosedRange<Double>, value text: String) -> some View {
        LabeledContent {
            HStack(spacing: 12) {
                Slider(value: value, in: range).frame(minWidth: 120)
                    .accessibilityLabel(title)
                Text(text).monospacedDigit().foregroundStyle(.secondary)
                    .frame(width: 64, alignment: .trailing)
            }
        } label: {
            Text(title)
        }
    }

    private func updateLogin(_ enabled: Bool) {
        guard enabled != (SMAppService.mainApp.status == .enabled) else { return }
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            loginError = SMAppService.mainApp.status == .requiresApproval
                ? "Allow PeakGlow in System Settings → Login Items." : nil
        } catch {
            loginError = "Could not update login item: \(error.localizedDescription)"
        }
        loginEnabled = SMAppService.mainApp.status == .enabled
    }
}

