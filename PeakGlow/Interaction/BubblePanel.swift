import AppKit
import SwiftUI

/// 刘海气泡菜单（Dynamic Island 风格）
final class BubblePanelController: NSObject {
    private var panel: NSPanel?
    private let hover: NotchHoverController
    /// 代数令牌：防止旧隐藏动画的 completion 关掉新弹出的气泡
    private var generation = 0

    init(hover: NotchHoverController) {
        self.hover = hover
        super.init()
        hover.onShowBubble = { [weak self] in self?.show() }
        hover.onHideBubble = { [weak self] in self?.hide() }
        hover.bubbleFrameProvider = { [weak self] in self?.panel?.frame }
        if let screen = NotchedScreenFinder.find(), let notch = NotchedScreenFinder.notchRect(of: screen) {
            panel = makePanel(notch: notch)
            panel?.contentView?.layoutSubtreeIfNeeded()
        }
    }

    private func makePanel(notch: CGRect) -> NSPanel {
        let size = CGSize(width: 328, height: 234)
        let frame = CGRect(
            x: notch.midX - size.width / 2,
            y: notch.minY - size.height - 8,
            width: size.width,
            height: size.height)

        let p = BubbleControlPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 2)
        p.collectionBehavior = [.moveToActiveSpace, .ignoresCycle]
        p.isMovable = false
        p.hidesOnDeactivate = false
        p.acceptsMouseMovedEvents = true
        p.becomesKeyOnlyIfNeeded = true

        let view = BubbleContentView(onClose: { [weak self] in
            self?.hover.dismissNow()
        }).environmentObject(AppState.shared)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: size)
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: hosting.frame)
            glass.cornerRadius = 24
            glass.contentView = hosting
            p.contentView = glass
        } else {
            let material = NSVisualEffectView(frame: hosting.frame)
            material.material = .popover
            material.blendingMode = .behindWindow
            material.state = .active
            material.wantsLayer = true
            material.layer?.cornerRadius = 20
            material.layer?.masksToBounds = true
            hosting.autoresizingMask = [.width, .height]
            material.addSubview(hosting)
            p.contentView = material
        }
        return p
    }

    func show() {
        guard let screen = NotchedScreenFinder.find(),
              let notch = NotchedScreenFinder.notchRect(of: screen) else { return }

        generation += 1
        let p: NSPanel
        if let panel {
            p = panel
        } else {
            p = makePanel(notch: notch)
            panel = p
        }
        p.setFrameOrigin(CGPoint(x: notch.midX - p.frame.width / 2,
                                 y: notch.minY - p.frame.height - 8))
        let animate = !p.isVisible && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        p.alphaValue = animate ? 0 : 1
        AppState.shared.watts = AppState.shared.latestWatts
        AppState.shared.bubbleVisible = true
        p.orderFrontRegardless()
        if animate {
            let destination = p.frame
            p.setFrameOrigin(CGPoint(x: destination.minX, y: destination.minY + 3))
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.10
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                p.animator().setFrame(destination, display: true)
                p.animator().alphaValue = 1
            }
        }
    }

    func hide() {
        let gen = generation
        guard let panel else { return }
        AppState.shared.bubbleVisible = false
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.08
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, gen == self.generation else { return }
            panel.orderOut(nil)
            panel.alphaValue = 1
        })
    }
}

/// Hover never takes focus; clicking a control can enable native keyboard navigation.
private final class BubbleControlPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

