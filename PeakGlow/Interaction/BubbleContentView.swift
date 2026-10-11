import SwiftUI

/// A compact system-style control surface. Material lives on the AppKit panel.
struct BubbleContentView: View {
    var onClose: () -> Void
    @EnvironmentObject var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var status: String {
        switch app.preview {
        case .low: return "Glow off"
        case .medium: return "Soft preview"
        case .high: return "Boost preview"
        case .overheat: return "Warm preview"
        case .auto: break
        }
        if app.gamepadConnected { return "Glow paused" }
        if app.overheatAlarm { return "Temperature elevated" }
        if app.powerAvailability != .current { return "Load unavailable" }
        switch app.effectiveLevel {
        case .low: return "Low load"
        case .medium: return "Moderate load"
        case .high: return "High load"
        }
    }

    private var powerText: String {
        app.powerAvailability == .current ? String(format: "%.1f", app.watts) : "—"
    }

    private var powerDescription: String {
        switch app.powerAvailability {
        case .waiting: return "Waiting for power data"
        case .current: return "System power"
        case .unavailable: return "Power data unavailable"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("PeakGlow", systemImage: "waveform.path")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Menu {
                    Button("Settings…") {
                        SettingsWindowController.shared.show()
                        onClose()
                    }
                    Divider()
                    Button("Quit PeakGlow") { NSApp.terminate(nil) }
                } label: {
                    Image(systemName: "ellipsis").frame(width: 28, height: 28)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityLabel("More actions")
            }

            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 5) {
                    Label(status, systemImage: app.overheatAlarm ? "thermometer.high" : "circle.fill")
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(app.overheatAlarm ? Color.orange : Color.secondary)
                    Text(powerDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(powerText)
                        .font(.system(size: 30, weight: .medium))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: app.watts)
                    Text("W")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("System power")
                .accessibilityValue(app.powerAvailability == .current ? "\(powerText) watts" : powerDescription)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Glow")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("Glow mode", selection: $app.preview) {
                    Text("Auto").tag(PreviewLevel.auto)
                    Text("Off").tag(PreviewLevel.low)
                    Text("Soft").tag(PreviewLevel.medium)
                    Text("Boost").tag(PreviewLevel.high)
                    Text("Warm").tag(PreviewLevel.overheat)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            HStack {
                Text(app.preview == .auto ? (app.gamepadConnected ? "Game controller connected" : "Adapts to system load") : "Choose Auto to resume")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    SettingsWindowController.shared.show()
                    onClose()
                } label: {
                    Image(systemName: "gearshape").frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .help("Settings…")
                .accessibilityLabel("Open Settings")
            }
        }
        .padding(20)
        .frame(width: 328, height: 258)
    }
}

