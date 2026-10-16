import AppKit

/// Notch hover detection with dwell-to-open and pointer-based dismissal after 180 ms.
@MainActor final class NotchHoverController {
    var onShowBubble: (() -> Void)?
    var onHideBubble: (() -> Void)?
    var onEngageBubble: ((Bool) -> Void)?
    /// Panel bounds in global AppKit coordinates, matching NSEvent.mouseLocation.
    var bubbleFrameProvider: (() -> CGRect?)?

    private var hoverPanel: NSPanel?
    private var dwellTimer: Timer?
    private var outsidePoll: Timer?
    private var outsideSince: CFTimeInterval?
    private var menuTracking = false
    private var globalClickMonitor: Any?
    private var escapeMonitor: Any?
    private var localClickMonitor: Any?
    private var engaged = false
    private var keyboardEngaged = false
    private var watchdogTimer: Timer?
    private var pendingReposition: Timer?
    private var bubbleVisible = false
    private var notchFrame: CGRect = .zero

    // MARK: - Lifecycle

    func start() {
        reposition()
        NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.menuTracking = true } }
        NotificationCenter.default.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.menuTracking = false
                self?.outsideSince = nil
            }
        }
        // Wake, Space and display notifications can arrive in bursts.
        // Coalesce them and reuse the panel instead of rebuilding it.
        // This avoids unnecessary WindowServer window creation.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.scheduleReposition() } }

        // Restore stationary panels after display wake or Space changes.
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.screensDidWakeNotification,
                       object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.scheduleReposition() } }
        ws.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification,
                       object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.scheduleReposition() } }

        // Periodically check the hover target in case a notification was missed.
        watchdogTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.ensureVisible() }
        }
    }

    /// Coalesce reposition requests over 0.5 seconds.
    private func scheduleReposition() {
        pendingReposition?.invalidate()
        pendingReposition = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.pendingReposition = nil
                self?.reposition()
            }
        }
    }

    /// Restore the hover target if hidden or occluded.
    func ensureVisible() {
        guard let p = hoverPanel else {
            reposition()
            return
        }
        if !p.isVisible {
            reposition()
            return
        }
        if !p.occlusionState.contains(.visible) {
            p.orderFrontRegardless()
        }
    }

    func reposition() {
        // Reuse the existing panel rather than destroy and recreate it.
        guard let screen = NotchedScreenFinder.find(),
              let notch = NotchedScreenFinder.notchRect(of: screen) else {
            dismissNow()
            notchFrame = .zero
            hoverPanel?.orderOut(nil)   // Hide until a notch display becomes available again.
            return
        }
        if bubbleVisible, notchFrame != notch { dismissNow() }
        notchFrame = notch

        let p: NSPanel
        if let existing = hoverPanel {
            p = existing
        } else {
            p = NSPanel(
                contentRect: notch,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false)
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = false
            p.hidesOnDeactivate = false   // Keep the hit target present when another application activates.
            p.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)))
            // The hit target must also join the foreground app's fullscreen Space.
            p.collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .stationary, .ignoresCycle]
            p.isMovable = false

            let view = HoverTargetView(frame: NSRect(origin: .zero, size: notch.size))
            view.controller = self
            p.contentView = view
            hoverPanel = p
        }

        if p.frame != notch {
            p.setFrame(notch, display: false)
        }
        p.orderFrontRegardless()
    }

    // MARK: - Public actions

    func dismissNow() {
        hideBubble()
    }


    private func engage(forKeyboard: Bool = false) {
        guard !engaged || (forKeyboard && !keyboardEngaged) else { return }
        engaged = true
        keyboardEngaged = keyboardEngaged || forKeyboard
        outsideSince = nil
        if outsidePoll == nil { startOutsideWatch() }
        onEngageBubble?(forKeyboard)
    }

    // MARK: - Pointer interaction

    fileprivate func mouseEnteredNotch() {
        cancelOutsideWatch()
        guard !bubbleVisible else { return }
        dwellTimer?.invalidate()
        let timer = Timer(timeInterval: max(0, AppSettings.shared.hoverDwell), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.bubbleVisible, self.notchFrame.insetBy(dx: -4, dy: -4).contains(NSEvent.mouseLocation) else { return }
                self.dwellTimer = nil
                self.showBubble()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        dwellTimer = timer
    }

    fileprivate func clickNotch() {
        dwellTimer?.invalidate()
        dwellTimer = nil
        if bubbleVisible && engaged {
            hideBubble()
        } else {
            if !bubbleVisible { showBubble() }
            engage()
        }
    }

    fileprivate func mouseExitedNotch() {
        dwellTimer?.invalidate()
        dwellTimer = nil
        if bubbleVisible { startOutsideWatch() }
    }

    private func showBubble() {
        bubbleVisible = true
        Haptics.play(.generic)
        onShowBubble?()
        startOutsideWatch()
        installClickMonitor()
    }

    private func hideBubble() {
        dwellTimer?.invalidate()
        dwellTimer = nil
        guard bubbleVisible else { return }
        bubbleVisible = false
        engaged = false
        keyboardEngaged = false
        cancelOutsideWatch()
        removeClickMonitor()
        onHideBubble?()
    }

    // MARK: - Outside interaction

    private func startOutsideWatch() {
        outsidePoll?.invalidate()
        outsidePoll = nil
        outsideSince = nil
        outsidePoll = Timer(
            timeInterval: 0.04, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkOutside() }
        }
        if let outsidePoll { RunLoop.main.add(outsidePoll, forMode: .common) }
        outsidePoll?.tolerance = 0.004
    }

    private func cancelOutsideWatch() {
        outsidePoll?.invalidate()
        outsidePoll = nil
        outsideSince = nil
    }

    private func checkOutside() {
        guard bubbleVisible else {
            cancelOutsideWatch()
            return
        }
        guard !menuTracking, NSEvent.pressedMouseButtons == 0 else {
            outsideSince = nil
            return
        }
        let loc = NSEvent.mouseLocation

        var inside = notchFrame.insetBy(dx: -6, dy: -6).contains(loc)
        if !inside, let bf = bubbleFrameProvider?() {
            inside = bf.insetBy(dx: -8, dy: -8).contains(loc)
            // Include the gap between the notch and panel in the pointer travel region.
            if !inside {
                let gap = CGRect(
                    x: bf.minX, y: bf.maxY,
                    width: bf.width,
                    height: max(0, notchFrame.minY - bf.maxY))
                inside = gap.insetBy(dx: 0, dy: -8).contains(loc)
            }
        }

        if inside {
            outsideSince = nil
            return
        }
        let now = CACurrentMediaTime()
        if outsideSince == nil {
            outsideSince = now
            return
        }
        if now - outsideSince! >= 0.18 {
            hideBubble()
        }
    }

    private func installClickMonitor() {
        guard globalClickMonitor == nil else { return }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53, self?.bubbleVisible == true else { return event }
            self?.hideBubble()
            return nil
        }
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, self.bubbleVisible, !self.menuTracking else { return event }
            let location = NSEvent.mouseLocation
            if self.bubbleFrameProvider?()?.contains(location) == true { self.engage() }
            else if !self.notchFrame.contains(location) { self.hideBubble() }
            return event
        }
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            // An outside click in another application dismisses the controls.
            self?.hideBubble()
        }
    }

    private func removeClickMonitor() {
        if let monitor = localClickMonitor {
            NSEvent.removeMonitor(monitor)
            localClickMonitor = nil
        }
        if let monitor = escapeMonitor {
            NSEvent.removeMonitor(monitor)
            escapeMonitor = nil
        }
        if let m = globalClickMonitor {
            NSEvent.removeMonitor(m)
            globalClickMonitor = nil
        }
    }
}

/// Invisible view providing the notch hit target.
private final class HoverTargetView: NSView {
    weak var controller: NotchHoverController?
    private var tracking: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let t = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self, userInfo: nil)
        addTrackingArea(t)
        tracking = t
    }

    override func mouseDown(with event: NSEvent) {
        controller?.clickNotch()
    }

    override func mouseEntered(with event: NSEvent) {
        controller?.mouseEnteredNotch()
    }

    override func mouseExited(with event: NSEvent) {
        controller?.mouseExitedNotch()
    }
}

