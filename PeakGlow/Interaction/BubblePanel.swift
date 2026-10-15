import AppKit
import SwiftUI

/// Control panel that grows out of the notch like an island.
/// The island's black shell and the glow around it are drawn together by the Metal renderer with
/// one spring. This window is fixed and transparent, flush with the top of the screen, and holds
/// only the controls, so native controls keep their layout while the island moves.
@MainActor final class BubblePanelController: NSObject {
    private var panel: NSPanel?
    private let hover: NotchHoverController
    private let motion = IslandMotion()
    private var hostingView: NSView?
    private var notchSize: CGSize = .zero
    /// Guards the delayed removal of the window after the island has contracted.
    private var presentationGeneration: UInt = 0
    /// How long the shell waits after the content starts to leave.
    private static let shellContractionDelay: TimeInterval = 0.05
    /// Draws the island's shell and glow; it tells us when the island is back in the notch.
    weak var glow: GlowWindow? {
        didSet { glow?.onIslandHidden = { [weak self] in self?.islandHidden() } }
    }

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
            panel = makePanel(screen: screen, notch: notch)
            panel?.contentView?.layoutSubtreeIfNeeded()
        }
    }

    var isKey: Bool { panel?.isKeyWindow == true }

    /// Top of the window is the top of the screen, centered on the notch.
    private func windowFrame(screen: NSScreen, notch: CGRect) -> CGRect {
        let width = IslandMetrics.width
        let height = notch.height + IslandMetrics.contentHeight
        return CGRect(x: notch.midX - width / 2, y: screen.frame.maxY - height, width: width, height: height)
    }

    private var islandSize: CGSize { CGSize(width: IslandMetrics.width, height: notchSize.height + IslandMetrics.contentHeight) }

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
        // Like the glow, the island asks to stay out of screenshots and recordings.
        p.sharingType = AppSettings.overlaySharingType
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
        // The island is black; native AppKit controls on it use the dark appearance.
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

        motion.fallbackShell = !(glow?.canDrawIsland ?? false)

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
            glow?.setIsland(expanded: true, size: islandSize)
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
            self.glow?.setIsland(expanded: true, size: self.islandSize)
        }
    }

    func hide() {
        guard panel != nil else { return }
        AppState.shared.bubbleVisible = false
        presentationGeneration &+= 1
        let generation = presentationGeneration
        // The island contracts back into the notch; the window is removed once the renderer
        // reports it is hidden. The timer is a fallback if the renderer is unavailable.
        motion.expanded = false
        // The content leaves first; the shell follows a moment later so it never trails the content.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.shellContractionDelay) { [weak self] in
            guard let self, self.presentationGeneration == generation, !self.motion.expanded else { return }
            self.glow?.setIsland(expanded: false, size: self.islandSize)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self, self.presentationGeneration == generation, !self.motion.expanded else { return }
            self.panel?.orderOut(nil)
        }
    }

    private func islandHidden() {
        guard !motion.expanded, !AppState.shared.bubbleVisible else { return }
        panel?.orderOut(nil)
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
