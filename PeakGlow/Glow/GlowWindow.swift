import AppKit

/// Transparent, pointer-pass-through glow anchored to the built-in notch.
@MainActor final class GlowWindow {
    private var panel: NSPanel?
    private var metalView: GlowMetalView?
    private var currentScreen: NSScreen?
    private var headroomTimer: Timer?
    private var screenChangeDebounce: Timer?
    private var pendingLevel: LoadLevel?
    private var pendingPowerFraction: Float?
    private var pausedByGamepad = false
    private var screenAsleep = false
    private var pendingOverheat = false
    private var pendingOverheatGain: Float = 1.5
    /// Called after the island has contracted into the notch and the window is back to its small size.
    var onIslandHidden: (() -> Void)?
    /// The window always holds the full island and its halo, so it is never resized while the
    /// island moves: a resize shows one stretched frame of the old drawable.
    private var islandSize: CGSize = .zero

    // MARK: - Lifecycle

    func start() {
        reposition()
        startHeadroomPolling()
        observeScreenChanges()
    }

    func shutdown() {
        headroomTimer?.invalidate()
        screenChangeDebounce?.invalidate()
        metalView?.sleep()
        panel?.orderOut(nil)
    }

    // MARK: - State

    func setLevel(_ level: LoadLevel) {
        pendingLevel = level
        metalView?.renderer?.targetLevel = level
        syncPauseState()
    }

    /// Whether the renderer is available to draw the island's shell.
    var canDrawIsland: Bool { metalView?.renderer != nil }

    /// Run the shared spring; the window is already large enough for the island.
    func setIsland(expanded: Bool, size: CGSize, radius: CGFloat = IslandMetrics.expandedCornerRadius) {
        if expanded {
            metalView?.renderer?.islandSizePoints = size
            metalView?.renderer?.islandRadiusPoints = radius
        }
        metalView?.renderer?.setIsland(expanded: expanded)
        metalView?.wake()
    }

    /// Take the island away at once, for example when the controls open over it.
    func cancelIsland() {
        metalView?.renderer?.resetIsland()
        metalView?.wake()
    }

    private func islandFinished() {
        onIslandHidden?()
    }

    /// Charging shows in the glow while it lasts; one ripple marks plugging in the charger.
    func setCharging(_ on: Bool) {
        if metalView?.renderer?.setCharging(on) == true { metalView?.wake() }
    }

    func chargePulse() {
        metalView?.renderer?.triggerChargePulse()
        metalView?.wake()
    }

    /// The power reading moves a little every half second (a watt or so at idle). The glow only follows it
    /// once it has moved enough to show, about seven percent of the color ramp (or at once if it jumps), so a steady glow can stop
    /// drawing instead of redrawing a picture that no eye can tell from the last one.
    private var shownPowerFraction: Float?
    private var shownPowerAt: CFTimeInterval = 0

    func setPowerFraction(_ fraction: Float?) {
        pendingPowerFraction = fraction
        let now = CACurrentMediaTime()
        let changed: Bool
        switch (fraction, shownPowerFraction) {
        case (nil, nil): changed = false
        case let (new?, old?):
            // A big move is followed at once; a small one only after a couple of seconds, and only if
            // it is still there then.
            let delta = abs(new - old)
            changed = delta > 0.25 || (delta > 0.07 && now - shownPowerAt > 2.5)
        default: changed = true
        }
        guard changed else { return }
        shownPowerFraction = fraction
        shownPowerAt = now
        metalView?.renderer?.powerFraction = fraction
        metalView?.nudge()
    }

    func setOverheat(_ on: Bool, gainBoost: Float = 1.5) {
        pendingOverheat = on
        pendingOverheatGain = gainBoost
        if let r = metalView?.renderer { r.overheatGain = gainBoost }
        metalView?.renderer?.overheat = on
    }

    func setPaused(_ paused: Bool) {
        pausedByGamepad = paused
        syncPauseState()
    }

    func setScreenAsleep(_ asleep: Bool) {
        screenAsleep = asleep
        if asleep { syncPauseState() }
        else { reposition() }
    }

    /// Pause automatic glow while a controller is connected.
    /// Let the renderer fade to transparent before stopping its display link.
    /// Display sleep or an unavailable notch display stops rendering immediately.
    private func syncPauseState() {
        guard currentScreen != nil, !screenAsleep else {
            metalView?.sleep()
            panel?.orderOut(nil)
            return
        }
        let effective = screenAsleep || (pausedByGamepad && AppSettings.shared.preview == .auto)
        if let r = metalView?.renderer {
            r.paused = effective
            r.ambientEnabled = AppSettings.shared.preview == .auto && AppSettings.shared.ambientGlow
        }
        metalView?.wake()   // Wake the display link only when needed to render or finish a fade.
    }

    // MARK: - Layout

    func reposition() {
        guard let screen = NotchedScreenFinder.find(),
              let notch = NotchedScreenFinder.notchRect(of: screen) else {
            panel?.orderOut(nil)
            metalView?.sleep()
            currentScreen = nil
            return
        }
        currentScreen = screen

        // Keep enough transparent padding for the widest soft halo.
        let scale = CGFloat(AppSettings.shared.glowScale)
        let padding = 150.0 * scale * max(1, CGFloat(AppSettings.shared.overheatScale))
        var width = notch.width + padding * 2
        var height = notch.height + padding
        islandSize = CGSize(width: IslandMetrics.width, height: notch.height + IslandMetrics.contentHeight)
        width = max(width, islandSize.width + padding * 2)
        height = max(height, islandSize.height + padding)
        let frame = CGRect(
            x: notch.midX - width / 2,
            y: screen.frame.maxY - height,   // Anchor at the top of the display in bottom-left AppKit coordinates.
            width: width,
            height: height)

        let isNewPanel = (panel == nil)
        if let panel {
            // Skip redundant frame updates.
            if panel.frame != frame {
                panel.setFrame(frame, display: true)
            }
        } else {
            let p = NSPanel(
                contentRect: frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false)
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = false
            p.ignoresMouseEvents = true
            p.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
            p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            p.sharingType = AppSettings.overlaySharingType          // Request capture exclusion; capture behavior depends on macOS and the capture API.
            p.isMovable = false

            let view = GlowMetalView(frame: NSRect(origin: .zero, size: frame.size))
            view.autoresizingMask = [.width, .height]
            p.contentView = view
            metalView = view
            panel = p
        }

        metalView?.setup(screen: screen, notchRectGlobal: notch)
        metalView?.renderer?.overheat = pendingOverheat
        metalView?.renderer?.overheatGain = pendingOverheatGain
        // Restore the pending level when a renderer is first created.
        if let lvl = pendingLevel {
            metalView?.renderer?.targetLevel = lvl
        }
        metalView?.renderer?.powerFraction = pendingPowerFraction
        metalView?.renderer?.islandSizePoints = islandSize
        metalView?.renderer?.onIslandHidden = { [weak self] in self?.islandFinished() }
        syncPauseState()

        // Configure the EDR layer once, then refresh headroom on reposition.
        if isNewPanel, let metalLayer = metalView?.layer as? CAMetalLayer {
            metalLayer.wantsExtendedDynamicRangeContent = true
            metalLayer.colorspace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)
        }
        updateHeadroom(screen: screen)

        if !screenAsleep { panel?.orderFrontRegardless() }
    }

    private func updateHeadroom(screen: NSScreen) {
        let h = screen.maximumExtendedDynamicRangeColorComponentValue
        metalView?.renderer?.headroom = Float(max(1.0, h))
    }

    private func startHeadroomPolling() {
        headroomTimer?.invalidate()
        headroomTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let s = self.currentScreen {
                    self.updateHeadroom(screen: s)
                }
                // Restore an occluded stationary panel after wake or Space changes.
                if let p = self.panel, p.isVisible, !p.occlusionState.contains(.visible) {
                    p.orderFrontRegardless()
                }
            }
        }
    }

    private func observeScreenChanges() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.metalView?.wake() }
            }
        // Coalesce display-change notifications to avoid redundant drawable resizing.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.screenChangeDebounce?.invalidate()
                self.screenChangeDebounce = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.screenChangeDebounce = nil
                        self?.reposition()
                    }
                }
            }
        }
    }
}

