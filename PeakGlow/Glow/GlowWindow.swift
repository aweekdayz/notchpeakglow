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
    private var islandWindowActive = false
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

    /// Grow the window to hold the island and its halo, then run the shared spring.
    func setIsland(expanded: Bool, size: CGSize) {
        if expanded {
            islandSize = size
            if !islandWindowActive {
                islandWindowActive = true
                reposition()
            }
            metalView?.renderer?.islandSizePoints = size
            metalView?.renderer?.setIsland(expanded: true)
            metalView?.wake()
        } else {
            metalView?.renderer?.setIsland(expanded: false)
            metalView?.wake()
        }
    }

    private func islandFinished() {
        islandWindowActive = false
        reposition()
        onIslandHidden?()
    }

    func setPowerFraction(_ fraction: Float?) {
        pendingPowerFraction = fraction
        metalView?.renderer?.powerFraction = fraction
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
        if islandWindowActive {
            width = max(width, islandSize.width + padding * 2)
            height = max(height, islandSize.height + padding)
        }
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
            p.sharingType = .none          // Request capture exclusion; capture behavior depends on macOS and the capture API.
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

