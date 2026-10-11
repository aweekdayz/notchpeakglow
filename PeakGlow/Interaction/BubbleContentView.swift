import SwiftUI

/// A compact system-style control surface. Material lives on the AppKit panel.
struct BubbleContentView: View {
    var onClose: () -> Void
    @EnvironmentObject var app: AppState

    private var status: String {
        if app.overheatAlarm { return "温度偏高" }
        switch app.effectiveLevel {
        case .low: return "运行平稳"
        case .medium: return "负载上升"
        case .high: return "高负载"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("PeakGlow", systemImage: "waveform.path")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Menu {
                    Button("退出 PeakGlow") { NSApp.terminate(nil) }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityLabel("更多操作")
            }

            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 5) {
                    Label(status, systemImage: app.overheatAlarm ? "thermometer.high" : "circle.fill")
                        .font(.callout)
                        .foregroundStyle(app.overheatAlarm ? Color.orange : Color.secondary)
                    Text(app.preview == .auto ? "整机功耗" : "正在预览光晕")
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
                Text("光晕")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("光晕模式", selection: $app.preview) {
                    Text("自动").tag(PreviewLevel.auto)
                    Text("关闭").tag(PreviewLevel.low)
                    Text("柔光").tag(PreviewLevel.medium)
                    Text("增强").tag(PreviewLevel.high)
                    Text("温度").tag(PreviewLevel.overheat)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            HStack {
                Text(app.preview == .auto ? "随负载自动变化" : "选择自动以恢复监测")
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
                .help("设置…")
                .accessibilityLabel("打开设置")
            }
        }
        .padding(20)
        .frame(width: 328, height: 234)
    }
}

