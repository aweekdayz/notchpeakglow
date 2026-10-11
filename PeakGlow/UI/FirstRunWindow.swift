import AppKit
import SwiftUI

/// 首次启动引导窗口：告知用户无 Dock/菜单栏图标，通过刘海交互
enum FirstRunWindow {
    private static var retainedPanel: NSPanel?
    static func showIfNeeded() {
        guard !AppSettings.shared.firstRunDone else { return }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 340),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false)
        panel.title = "欢迎使用 PeakGlow"
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
        panel.level = .floating

        let view = FirstRunContentView {
            panel.orderOut(nil)
            retainedPanel = nil
        }
        panel.contentView = NSHostingView(rootView: view)
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        retainedPanel = panel

        AppSettings.shared.firstRunDone = true
    }
}

private struct FirstRunContentView: View {
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)

            Text("一点柔光，感知负载。")
                .font(.title2.weight(.semibold))

            VStack(alignment: .leading, spacing: 10) {
                Label {
                    Text("安静地运行在后台，不占用 Dock 或菜单栏。")
                } icon: {
                    Image(systemName: "eye.slash")
                        .foregroundStyle(.secondary)
                }
                Label {
                    Text("将指针停留在刘海上，即可查看功耗、预览光晕。")
                } icon: {
                    Image(systemName: "camera.metering.center")
                        .foregroundStyle(.secondary)
                }
                Label {
                    Text("打开设置，调整柔光范围与负载阈值。")
                } icon: {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            Button("开始使用") {
                onClose()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .padding(.top, 4)
        }
        .padding(24)
        .frame(width: 420, height: 340)
    }
}

