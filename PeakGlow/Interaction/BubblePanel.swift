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
    private var motionStartAlpha: CGFloat = 0
    private var motionEndAlpha: CGFloat = 1
    private var closing = false
    private var preparingPresentation = false
    private var presentationGeneration: UInt = 0
    private var hostingView: NSView?

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
        // A borderless NSPanel's system shadow follows its rectangular frame,
        // exposing square corners around SwiftUI's rounded Liquid Glass surface.
        p.hasShadow = false
        p.isFloatingPanel = true
        p.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 2)
        // Hover doesn't activate this app, so moving on activation isn't enough.
        // Join the foreground app's Space, including full screen and Stage Manager.
        p.collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .ignoresCycle]
        p.isMovable = false
        p.hidesOnDeactivate = false
        p.acceptsMouseMovedEvents = true
        p.becomesKeyOnlyIfNeeded = true

        let view = BubbleContentView(onClose: { [weak self] in
            self?.hover.dismissNow()
        })
        let hosting = NSHostingView(rootView: view)
        // The borderless glass panel has no rectangular host-level focus outline.
        // Child controls retain their native keyboard focus indicators.
        hosting.focusRingType = .none
        hosting.sizingOptions = []
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.autoresizingMask = [.width, .height]
        hostingView = hosting
        // SwiftUI owns the material and its control context; AppKit owns only the window.
        p.contentView = hosting
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
            p.setFrame(destination, display: false)
        }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { AppState.shared.refreshPower() }
        AppState.shared.bubbleVisible = true
        presentationGeneration &+= 1
        let generation = presentationGeneration
        let needsPreparation = !p.isVisible
        if needsPreparation {
            motionLink?.invalidate()
            motionLink = nil
            preparingPresentation = true
        }
        let overlayLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 2)
        if p.level != overlayLevel { p.level = overlayLevel }
        p.orderFrontRegardless()
        if !needsPreparation {
            animate(to: destination, alpha: 1, closing: false)
            return
        }
        // Window attachment changes native control metrics. Let SwiftUI consume the
        // atomic measurement update while the attached window is still transparent.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.presentationGeneration == generation,
                  AppState.shared.bubbleVisible else { return }
            self.hostingView?.needsLayout = true
            self.hostingView?.layoutSubtreeIfNeeded()
            p.contentView?.layoutSubtreeIfNeeded()
            self.animate(to: destination, alpha: 1, closing: false)
        }
    }

    func hide() {
        guard let panel else { return }
        AppState.shared.bubbleVisible = false
        presentationGeneration &+= 1
        preparingPresentation = false
        animate(to: panel.frame, alpha: 0, closing: true)
    }

    private func animate(to frame: CGRect, alpha: CGFloat, closing: Bool) {
        motionLink?.invalidate()
        motionLink = nil
        guard let panel else { return }
        self.closing = closing
        // Keep the control surface anchored; entrance motion must not move its contents.
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        motionStartAlpha = panel.alphaValue
        motionEndAlpha = alpha
        let distance = abs(motionEndAlpha - motionStartAlpha)
        if distance < 0.001, !preparingPresentation {
            panel.alphaValue = alpha
            if closing { panel.orderOut(nil) }
            return
        }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            preparingPresentation = false
            panel.setFrame(frame, display: true)
            panel.alphaValue = alpha
            if closing { panel.orderOut(nil) }
            return
        }
        motionStarted = CACurrentMediaTime()
        // Reverse from the current opacity without restarting a full-length fade.
        motionDuration = max(1.0 / 60.0, (closing ? 0.12 : 0.18) * Double(distance))
        guard let view = panel.contentView else { return }
        let link = view.displayLink(target: self, selector: #selector(animateFrame(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        motionLink = link
    }

    @objc private func animateFrame(_ link: CADisplayLink) {
        guard let panel else { link.invalidate(); motionLink = nil; return }
        if preparingPresentation {
            // First display-link tick lays out the attached native controls without
            // exposing an intermediate frame; subsequent ticks perform the fade.
            hostingView?.needsLayout = true
            hostingView?.layoutSubtreeIfNeeded()
            panel.contentView?.layoutSubtreeIfNeeded()
            panel.contentView?.displayIfNeeded()
            preparingPresentation = false
            motionStarted = CACurrentMediaTime()
            return
        }
        let fraction = min(1, max(0, (CACurrentMediaTime() - motionStarted) / motionDuration))
        let eased = CGFloat(PanelMotion.progress(fraction))
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
