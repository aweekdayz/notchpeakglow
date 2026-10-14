import AppKit
import SwiftUI

/// Control panel that grows out of the notch like an island.
/// The window is fixed and transparent, with its top at the screen edge; only the shape inside it
/// moves, so native controls keep their layout while the island expands and contracts.
@MainActor final class BubblePanelController: NSObject {
    private var panel: NSPanel?
    private let hover: NotchHoverController
    private let motion = IslandMotion()
    private var hostingView: NSView?
    private var notchSize: CGSize = .zero
    /// Guards the delayed removal of the window after the island has contracted.
    private var presentationGeneration: UInt = 0

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
        // Pointer tests use the island itself, not the transparent margin around it.
        hover.bubbleFrameProvider = { [weak self] in
            guard let frame = self?.panel?.frame else { return nil }
            let m = IslandMetrics.margin
            return CGRect(x: frame.minX + m, y: frame.minY + m,
                          width: frame.width - m * 2, height: frame.height - m)
        }
        if let screen = NotchedScreenFinder.find(), let notch = NotchedScreenFinder.notchRect(of: screen) {
            panel = makePanel(screen: screen, notch: notch)
            panel?.contentView?.layoutSubtreeIfNeeded()
        }
    }

    var isKey: Bool { panel?.isKeyWindow == true }

    /// Top of the window is the top of the screen, centered on the notch.
    private func windowFrame(screen: NSScreen, notch: CGRect) -> CGRect {
        let m = IslandMetrics.margin
        let width = IslandMetrics.width + m * 2
        let height = notch.height + IslandMetrics.contentHeight + m
        return CGRect(x: notch.midX - width / 2, y: screen.frame.maxY - height, width: width, height: height)
    }

    private func makePanel(screen: NSScreen, notch: CGRect) -> NSPanel {
        let frame = windowFrame(screen: screen, notch: notch)
        notchSize = notch.size

        let p = BubbleControlPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        // A borderless NSPanel's system shadow follows its rectangular frame.
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
        }, motion: motion, notchSize: notch.size)
        let hosting = BubbleHostingView(rootView: view)
        // The island is black; native AppKit controls inside it use the dark appearance.
        hosting.appearance = NSAppearance(named: .darkAqua)
        // The island has no rectangular host-level focus outline.
        // Child controls retain their native keyboard focus indicators.
        hosting.focusRingType = .none
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        hosting.sizingOptions = []
        hosting.frame = NSRect(origin: .zero, size: frame.size)
        hosting.autoresizingMask = [.width, .height]
        hostingView = hosting
        p.contentView = hosting
        return p
    }

    func show() {
        guard let screen = NotchedScreenFinder.find(),
              let notch = NotchedScreenFinder.notchRect(of: screen) else { return }

        // The shape is built from the notch's size; rebuild if the display changed.
        if panel == nil || notch.size != notchSize {
            panel?.orderOut(nil)
            motion.expanded = false
            panel = makePanel(screen: screen, notch: notch)
        }
        guard let p = panel else { return }
        let frame = windowFrame(screen: screen, notch: notch)
        if p.frame != frame { p.setFrame(frame, display: false) }

        // Establish the requested post-click appearance before the first visible frame.
        // The nonactivating panel keeps the foreground application active.
        (p as? BubbleControlPanel)?.allowsKeyboardFocus = true
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { AppState.shared.refreshPower() }
        AppState.shared.bubbleVisible = true
        presentationGeneration &+= 1
        let generation = presentationGeneration

        let overlayLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 2)
        if p.level != overlayLevel { p.level = overlayLevel }
        let wasVisible = p.isVisible
        if !wasVisible { motion.expanded = false }
        if !p.isKeyWindow { p.makeKeyAndOrderFront(nil) }
        p.orderFrontRegardless()
        if wasVisible {
            motion.expanded = true
            return
        }
        // At rest the island is the notch's own shape and invisible. Window attachment changes
        // native control metrics, so let SwiftUI lay out once before the island opens.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.presentationGeneration == generation,
                  AppState.shared.bubbleVisible else { return }
            self.hostingView?.needsLayout = true
            self.hostingView?.layoutSubtreeIfNeeded()
            p.contentView?.layoutSubtreeIfNeeded()
            self.motion.expanded = true
        }
    }

    func hide() {
        guard panel != nil else { return }
        AppState.shared.bubbleVisible = false
        presentationGeneration &+= 1
        let generation = presentationGeneration
        // The island contracts back into the notch, then the window is removed.
        motion.expanded = false
        let delay: TimeInterval = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.2 : 0.6
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.presentationGeneration == generation, !self.motion.expanded else { return }
            self.panel?.orderOut(nil)
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
