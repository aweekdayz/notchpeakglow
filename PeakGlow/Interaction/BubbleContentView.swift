import SwiftUI

/// A compact system-style control surface. Material lives on the AppKit panel.
struct BubbleContentView: View {
    var onClose: () -> Void
    @EnvironmentObject var app: AppState

    private var status: String {
        if app.preview == .low { return "Glow off" }
        if app.preview == .overheat { return "Warm preview" }
        if app.overheatAlarm { return "Temperature elevated" }
        switch app.effectiveLevel {
        case .low: return "Low load"
        case .medium: return "Moderate load"
        case .high: return "High load"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("PeakGlow", systemImage: "waveform.path")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Menu {
                    Button("Quit PeakGlow") { NSApp.terminate(nil) }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityLabel("More actions")
            }

            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 5) {
                    Label(status, systemImage: app.overheatAlarm ? "thermometer.high" : "circle.fill")
                        .font(.callout)
                        .foregroundStyle(app.overheatAlarm ? Color.orange : Color.secondary)
                    Text(app.preview == .auto ? "System power" : "Glow preview")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(app.watts > 0.5 ? String(format: "%.1f", app.watts) : "—")
                        .font(.system(size: 30, weight: .medium))
                        .monospacedDigit()
                    Text("W")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
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
                Text(app.preview == .auto ? "Adapts to system load" : "Choose Auto to resume")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    SettingsWindowController.shared.show()
                    onClose()
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
                .help("Settings…")
                .accessibilityLabel("Open Settings")
            }
        }
        .padding(20)
        .frame(width: 328, height: 234)
    }
}

