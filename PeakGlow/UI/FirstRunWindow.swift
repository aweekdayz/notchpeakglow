import AppKit
import SwiftUI

/// Initial guidance for accessing the background application through the notch.
enum FirstRunWindow {
    private static var retainedPanel: NSPanel?
    static func showIfNeeded() {
        guard !AppSettings.shared.firstRunDone else { return }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 340),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false)
        panel.title = "Welcome to PeakGlow"
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
    private var notchAvailable: Bool { NotchedScreenFinder.find() != nil }

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)

            Text("A little light. A sense of load.")
                .font(.title2.weight(.semibold))

            VStack(alignment: .leading, spacing: 10) {
                Label {
                    Text("Runs quietly in the background, without a Dock or menu bar icon.")
                } icon: {
                    Image(systemName: "eye.slash")
                        .foregroundStyle(.secondary)
                }
                Label {
                    Text(notchAvailable
                         ? "Hover over the notch to see power usage and preview the glow."
                         : "Glow and hover controls require an available built-in notch display.")
                } icon: {
                    Image(systemName: "camera.metering.center")
                        .foregroundStyle(.secondary)
                }
                Label {
                    Text("Open Settings to adjust the glow and power thresholds.")
                } icon: {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            Button("Get Started") {
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

