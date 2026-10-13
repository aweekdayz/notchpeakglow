import AppKit
import SwiftUI

/// Native control panel anchored beneath the notch.
@MainActor final class BubblePanelController: NSObject {
    private var panel: NSPanel?
    private let hover: NotchHoverController
    /// Interruptible presentation animation; generation guards prevent stale completions.
    private var motionLink: CADisplayLink?
    private var motionStarted: CFTimeInterval = 0
    private var motionDuration: CFTimeInterval = 0.18
    private var motionStartAlpha: CGFloat = 0
    private var motionEndAlpha: CGFloat = 1
    private var motionStartOrigin: CGPoint = .zero
    private var motionEndOrigin: CGPoint = .zero
    private var restingFrame: CGRect?
    private var closing = false
    private var preparingPresentation = false
    private var presentationGeneration: UInt = 0
    private var hostingView: NSView?

    init(hover: NotchHoverController) {
        self.hover = hover
        super.init()
        hover.onShowBubble = { [weak self] in self?.show() }
        hover.onHideBubble = { [weak self] in self?.hide() }
        hover.onEngageBubble = { [weak self] forKeyboard in
            guard forKeyboard, let panel = self?.panel as? BubbleControlPanel else { return }
            panel.allowsKeyboardFocus = true
            panel.makeKeyAndOrderFront(nil)
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
        let hosting = BubbleHostingView(rootView: view)
        // The borderless glass panel has no rectangular host-level focus outline.
        // Child controls retain their native keyboard focus indicators.
        hosting.focusRingType = .none
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        hosting.layer?.cornerRadius = 24
        hosting.layer?.cornerCurve = .continuous
        hosting.layer?.masksToBounds = true
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
        // Establish the requested post-click appearance before the first visible frame.
        // The nonactivating panel keeps the foreground application active.
        (p as? BubbleControlPanel)?.allowsKeyboardFocus = true
        let destination = CGRect(x: notch.midX - p.frame.width / 2,
                                 y: notch.minY - p.frame.height - 8,
                                 width: p.frame.width, height: p.frame.height)
        restingFrame = destination
        if !p.isVisible {
            p.alphaValue = 0
            let entranceOffset: CGFloat = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 6
            p.setFrame(destination.offsetBy(dx: 0, dy: entranceOffset), display: false)
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
        if !p.isKeyWindow { p.makeKeyAndOrderFront(nil) }
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
        let destination = (restingFrame ?? panel.frame).offsetBy(dx: 0, dy: 4)
        animate(to: destination, alpha: 0, closing: true)
    }

    private func animate(to frame: CGRect, alpha: CGFloat, closing: Bool) {
        motionLink?.invalidate()
        motionLink = nil
        guard let panel else { return }
        self.closing = closing
        // Translate the whole window; never animate its size or internal layout.
        motionStartOrigin = panel.frame.origin
        motionEndOrigin = frame.origin
        motionStartAlpha = panel.alphaValue
        motionEndAlpha = alpha
        let distance = abs(motionEndAlpha - motionStartAlpha)
        let travel = hypot(motionEndOrigin.x - motionStartOrigin.x,
                           motionEndOrigin.y - motionStartOrigin.y)
        if distance < 0.001, travel < 0.01, !preparingPresentation {
            panel.alphaValue = alpha
            if closing { panel.orderOut(nil) }
            return
        }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            preparingPresentation = false
            // Reduce Motion retains the settled anchor without spatial movement.
            panel.setFrameOrigin((restingFrame ?? frame).origin)
            panel.alphaValue = alpha
            if closing { panel.orderOut(nil) }
            return
        }
        motionStarted = CACurrentMediaTime()
        // Reverse from the current opacity without restarting a full-length fade.
        let remaining = max(Double(distance), min(1, Double(travel / 6)))
        motionDuration = max(1.0 / 60.0, (closing ? 0.14 : 0.22) * remaining)
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
        let eased = CGFloat(PanelMotion.progress(fraction, closing: closing))
        let origin = CGPoint(
            x: motionStartOrigin.x + (motionEndOrigin.x - motionStartOrigin.x) * eased,
            y: motionStartOrigin.y + (motionEndOrigin.y - motionStartOrigin.y) * eased)
        if panel.frame.origin != origin { panel.setFrameOrigin(origin) }
        panel.alphaValue = motionStartAlpha + (motionEndAlpha - motionStartAlpha) * eased
        if fraction >= 1 {
            link.invalidate()
            motionLink = nil
            if closing { panel.orderOut(nil) }
        }
    }

}

/// Clip the complete composited host, including any focus-time backing surface.
private final class BubbleHostingView: NSHostingView<BubbleContentView> {
    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Presentations establish key appearance before revealing the nonactivating panel.
private final class BubbleControlPanel: NSPanel {
    var allowsKeyboardFocus = false
    override var canBecomeKey: Bool { allowsKeyboardFocus }
    override var canBecomeMain: Bool { false }
}


/// Arrival settles gently; departure accelerates toward the notch without overshoot.
enum PanelMotion {
    static func progress(_ fraction: Double, closing: Bool = false) -> Double {
        let x = min(1, max(0, fraction))
        if closing { return x * x }
        return 1 - pow(1 - x, 3)
    }
}
