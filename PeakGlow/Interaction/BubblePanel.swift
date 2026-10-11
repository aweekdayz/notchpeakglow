import AppKit
import SwiftUI

/// 刘海气泡菜单（Dynamic Island 风格）
final class BubblePanelController: NSObject {
    private var panel: NSPanel?
    private let hover: NotchHoverController
    /// 代数令牌：防止旧隐藏动画的 completion 关掉新弹出的气泡
    private var motionLink: CADisplayLink?
    private var motionStarted: CFTimeInterval = 0
    private var motionDuration: CFTimeInterval = 0.18
    private var motionStartFrame = CGRect.zero
    private var motionEndFrame = CGRect.zero
    private var motionStartAlpha: CGFloat = 0
    private var motionEndAlpha: CGFloat = 1
    private var closing = false

    init(hover: NotchHoverController) {
        self.hover = hover
        super.init()
        hover.onShowBubble = { [weak self] in self?.show() }
        hover.onHideBubble = { [weak self] in self?.hide() }
        hover.onEngageBubble = { [weak self] in
            NSApp.activate(ignoringOtherApps: true)
            self?.panel?.makeKeyAndOrderFront(nil)
        }
        hover.bubbleFrameProvider = { [weak self] in self?.panel?.frame }
        if let screen = NotchedScreenFinder.find(), let notch = NotchedScreenFinder.notchRect(of: screen) {
            panel = makePanel(notch: notch)
            panel?.contentView?.layoutSubtreeIfNeeded()
        }
    }

    var isKey: Bool { panel?.isKeyWindow == true }

    private func makePanel(notch: CGRect) -> NSPanel {
        let size = CGSize(width: 328, height: 258)
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
        hosting.sizingOptions = []
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

        let p: NSPanel
        if let panel { p = panel }
        else { p = makePanel(notch: notch); panel = p }
        let destination = CGRect(x: notch.midX - p.frame.width / 2,
                                 y: notch.minY - p.frame.height - 8,
                                 width: p.frame.width, height: p.frame.height)
        if !p.isVisible {
            p.alphaValue = 0
            p.setFrame(destination.offsetBy(dx: 0, dy: 4), display: false)
        }
        AppState.shared.refreshPower()
        AppState.shared.bubbleVisible = true
        p.orderFrontRegardless()
        animate(to: destination, alpha: 1, closing: false)
    }

    func hide() {
        guard let panel else { return }
        AppState.shared.bubbleVisible = false
        animate(to: panel.frame.offsetBy(dx: 0, dy: 3), alpha: 0, closing: true)
    }

    private func animate(to frame: CGRect, alpha: CGFloat, closing: Bool) {
        motionLink?.invalidate()
        motionLink = nil
        guard let panel else { return }
        self.closing = closing
        motionStartFrame = panel.frame
        motionEndFrame = frame
        motionStartAlpha = panel.alphaValue
        motionEndAlpha = alpha
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            panel.setFrame(frame, display: true)
            panel.alphaValue = alpha
            if closing { panel.orderOut(nil) }
            return
        }
        motionStarted = CACurrentMediaTime()
        motionDuration = closing ? 0.12 : 0.18
        guard let view = panel.contentView else { return }
        let link = view.displayLink(target: self, selector: #selector(animateFrame(_:)))
        link.add(to: .main, forMode: .common)
        motionLink = link
    }

    @objc private func animateFrame(_ link: CADisplayLink) {
        guard let panel else { link.invalidate(); motionLink = nil; return }
        let fraction = min(1, max(0, (CACurrentMediaTime() - motionStarted) / motionDuration))
        let eased = CGFloat(PanelMotion.progress(fraction))
        let y = motionStartFrame.minY + (motionEndFrame.minY - motionStartFrame.minY) * eased
        panel.setFrameOrigin(CGPoint(x: motionEndFrame.minX, y: y))
        panel.alphaValue = motionStartAlpha + (motionEndAlpha - motionStartAlpha) * eased
        if fraction >= 1 {
            link.invalidate()
            motionLink = nil
            if closing { panel.orderOut(nil) }
        }
    }

}

/// Hover never takes focus; clicking a control can enable native keyboard navigation.
private final class BubbleControlPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}


/// A bounded ease-out curve; reversing starts from the current visible state.
enum PanelMotion {
    static func progress(_ fraction: Double) -> Double {
        let x = min(1, max(0, fraction))
        return 1 - pow(1 - x, 3)
    }
}
