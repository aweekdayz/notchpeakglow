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
        w.title = "PeakGlow 设置"
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
                    LabeledContent("当前设备", value: MachineProfile.current.summary)
                    Text("光晕随整机功耗变化。低负载时自动隐去。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Section("外观") {
                    slider("光晕范围", binding(\.glowScale), in: 0.4...1.6,
                           value: "\(Int(s.glowScale * 100))%")
                    slider("亮度", binding(\.glowIntensity), in: 0.2...2,
                           value: "\(Int(s.glowIntensity * 100))%")
                    Text("柔光沿刘海边缘缓慢流动，高负载时过渡为冰蓝色。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("使用柔和外观") {
                        s.resetAppearance()
                    }
                }

                Section("负载") {
                    slider("柔光阈值", Binding(get: { s.mediumWatts },
                        set: { s.mediumWatts = min($0, s.highWatts - 1) }),
                        in: 8...60, value: "\(Int(s.mediumWatts)) W")
                    slider("增强阈值", Binding(get: { s.highWatts },
                        set: { s.highWatts = max($0, s.mediumWatts + 1) }),
                        in: 9...90, value: "\(Int(s.highWatts)) W")
                    Button("使用此设备的建议阈值") {
                        s.mediumWatts = MachineProfile.current.suggestedMediumWatts
                        s.highWatts = MachineProfile.current.suggestedHighWatts
                    }
                }

                Section("行为") {
                    Toggle("登录时启动", isOn: $loginEnabled)
                        .onChange(of: loginEnabled) { _, enabled in
                            updateLogin(enabled)
                        }
                    Toggle("温度偏高时提醒", isOn: binding(\.overheatAlertEnabled))
                    slider("悬停展开延迟", binding(\.hoverDwell), in: 0.2...1.5,
                           value: String(format: "%.1f s", s.hoverDwell))
                    if let loginError {
                        Text(loginError).font(.caption).foregroundStyle(.red)
                    }
                }

                Section {
                    DisclosureGroup("高级设置", isExpanded: $showAdvanced) {
                        slider("柔光透明度", binding(\.mediumAlpha), in: 0.2...0.8,
                               value: "\(Int(s.mediumAlpha * 100))%")
                        slider("呼吸频率", binding(\.pulseHz), in: 0.1...2,
                               value: String(format: "%.1f Hz", s.pulseHz))
                        slider("HDR 增益", binding(\.hdrFactor), in: 1...8,
                               value: String(format: "%.1f×", s.hdrFactor))
                        slider("温度提醒强度", binding(\.overheatGain), in: 0.5...8,
                               value: String(format: "%.1f×", s.overheatGain))
                        slider("温度提醒范围", binding(\.overheatScale), in: 0.6...1.8,
                               value: "\(Int(s.overheatScale * 100))%")
                        slider("帧率上限", binding(\.frameRate), in: 15...60,
                               value: "\(Int(s.frameRate)) fps")
                        slider("滞回区间", binding(\.hysteresisWatts), in: 1...10,
                               value: String(format: "%.1f W", s.hysteresisWatts))
                        slider("切换保持时间", binding(\.holdOnSeconds), in: 0.5...10,
                               value: String(format: "%.1f s", s.holdOnSeconds))
                        slider("采样周期", binding(\.sampleInterval), in: 0.2...3,
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
                Button("恢复默认…") { confirmReset = true }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
        .frame(width: 520, height: 620)
        .alert("恢复默认设置？", isPresented: $confirmReset) {
            Button("取消", role: .cancel) {}
            Button("恢复默认") {
                s.resetAll()
                AppState.shared.preview = .auto
            }
        } message: {
            Text("恢复光晕外观和此设备的建议负载阈值。")
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
                ? "请在系统设置的登录项中允许 PeakGlow。" : nil
        } catch {
            loginError = "无法更新登录项：\(error.localizedDescription)"
        }
        loginEnabled = SMAppService.mainApp.status == .enabled
    }
}

