import AppKit
import ServiceManagement

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let powerSampler = PowerSampler()
    private let thermal = OverheatDetector()
    private let stateMachine = LoadLevelStateMachine()
    private let glow = GlowWindow()
    private let hover = NotchHoverController()
    private let gamepad = GamepadDetector()
    private var bubble: BubblePanelController?
    private var statusItem: NSStatusItem?

    private var lastAutoLevel: LoadLevel = .low
    private var lastPowerFraction: Float?
    private var samplingInterval = AppSettings.shared.sampleInterval
    private var settingsUpdate: DispatchWorkItem?
    private var glowGeometry = SIMD2<Double>(AppSettings.shared.glowScale, AppSettings.shared.overheatScale)

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Apply family presets on first launch without replacing custom thresholds.
        if !AppSettings.shared.powerTuned {
            let mp = MachineProfile.current
            AppSettings.shared.mediumWatts = mp.suggestedMediumWatts
            AppSettings.shared.highWatts = mp.suggestedHighWatts
            AppSettings.shared.powerTuned = true
            NSLog("PeakGlow: machine tuned \(mp.summary) -> \(mp.suggestedMediumWatts)W/\(mp.suggestedHighWatts)W")
        }

        installMainMenu()
        updateStatusItem()
        bubble = BubblePanelController(hover: hover)
        bubble?.glow = glow
        // Sample power directly; unused CPU readings must not gate this callback.
        var wattWindow: [Double] = []
        powerSampler.onSample = { [weak self] reading in
            guard let self else { return }
            let state = AppState.shared

            state.recordPower(reading)
            guard let w = reading, w.isFinite, w >= 0 else {
                wattWindow.removeAll()
                self.lastPowerFraction = nil
                self.glow.setPowerFraction(nil)
                stateMachine.discardPendingTransition()
                if self.lastAutoLevel != .low {
                    self.stateMachine.reset()
                    self.lastAutoLevel = .low
                    self.applyLevel()
                }
                return
            }
            // Five-sample average filters transient power spikes.
            wattWindow.append(w)
            if wattWindow.count > 5 { wattWindow.removeFirst() }
            let average = wattWindow.reduce(0, +) / Double(wattWindow.count)
            stateMachine.update(watts: average)
            let fraction = GlowRenderer.powerFraction(
                watts: average, medium: AppSettings.shared.mediumWatts, high: AppSettings.shared.highWatts)
            self.lastPowerFraction = fraction
            if AppSettings.shared.preview == .auto { self.glow.setPowerFraction(fraction) }
        }
        stateMachine.onLevelChange = { [weak self] level in
            guard let self else { return }
            self.lastAutoLevel = level
            self.applyLevel()
        }

        // Coalesce settings changes before updating the glow.
        NotificationCenter.default.addObserver(
            forName: AppSettings.changedNotification,
            object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.settingsUpdate == nil else { return }
                let update = DispatchWorkItem { [weak self] in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        self.settingsUpdate = nil
                        self.applySettings()
                    }
                }
                self.settingsUpdate = update
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 / 60.0, execute: update)
            }
        }

        // Automatic wallpaper tuning follows the system appearance.
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyLevel() }
        }

        // A connected controller pauses automatic glow.
        gamepad.onGamepadChange = { [weak self] connected in
            AppState.shared.gamepadConnected = connected
            self?.glow.setPaused(connected)
        }

        // Temperature warnings add a steady warm tint independently of previews.
        thermal.onOverheatChange = { [weak self] hot in
            guard let self else { return }
            AppSettings.shared.overheatAlarm = hot
            self.applyLevel()
        }

        // Display sleep and wake.
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.screensDidSleepNotification,
                       object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                // The glow window goes away with the display; take the island with it.
                self?.hover.dismissNow()
                self?.glow.setScreenAsleep(true)
            }
        }
        ws.addObserver(forName: NSWorkspace.screensDidWakeNotification,
                       object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.glow.setScreenAsleep(false) }
        }

        glow.start()
        hover.start()
        gamepad.start()
        thermal.start()
        powerSampler.start(interval: AppSettings.shared.sampleInterval)
        applyLevel()   // Apply again after the renderer has been created.

        FirstRunWindow.showIfNeeded()
        if NotchedScreenFinder.find() == nil {
            SettingsWindowController.shared.show()
        } else {
            // Build Settings while idle, so the first click does not wait for it.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                MainActor.assumeIsolated { SettingsWindowController.shared.prewarm() }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        settingsUpdate?.cancel()
        glow.shutdown()
        powerSampler.stop()
        thermal.stop()
    }

    private func installMainMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "PeakGlow")
        appItem.submenu = appMenu
        menu.addItem(appItem)
        let about = appMenu.addItem(withTitle: "About PeakGlow", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        appMenu.addItem(.separator())
        let settings = appMenu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide PeakGlow", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit PeakGlow", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editItem.submenu = editMenu
        menu.addItem(editItem)
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowItem.submenu = windowMenu
        menu.addItem(windowItem)
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(.separator())
        let close = windowMenu.addItem(withTitle: "Close Window", action: #selector(closeActiveWindow), keyEquivalent: "w")
        close.target = self
        NSApp.mainMenu = menu
        NSApp.windowsMenu = windowMenu
    }

    @objc private func openSettings() {
        hover.dismissNow()
        SettingsWindowController.shared.show()
    }

    @objc func showAbout() {
        let credits = Bundle.main.url(forResource: "Credits", withExtension: "rtf")
            .flatMap { try? NSAttributedString(url: $0, options: [:], documentAttributes: nil) }
            ?? NSAttributedString(string: "Maintained by aweekdayz. Credits: https://github.com/aweekdayz/notchpeakglow/blob/main/CREDITS.md")
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }

    /// Glow modes in the order shown by the controls panel.
    private static let glowMenuModes = PreviewLevel.quickChoices

    /// A menu bar icon gives pointer-free access to power, the Glow mode, Settings and Quit.
    private func updateStatusItem() {
        guard AppSettings.shared.menuBarIcon else {
            if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
            statusItem = nil
            return
        }
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "waveform.path", accessibilityDescription: "PeakGlow")
        let menu = NSMenu(title: "PeakGlow")
        menu.delegate = self
        let power = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        power.isEnabled = false
        power.tag = Self.powerItemTag
        menu.addItem(power)
        menu.addItem(.separator())
        let glowHeader = NSMenuItem(title: "Glow", action: nil, keyEquivalent: "")
        glowHeader.isEnabled = false
        menu.addItem(glowHeader)
        for mode in Self.glowMenuModes {
            let item = menu.addItem(withTitle: mode.label, action: #selector(selectGlowMode(_:)), keyEquivalent: "")
            item.target = self
            item.tag = mode.rawValue
            item.indentationLevel = 1
        }
        menu.addItem(.separator())
        let settings = menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: "")
        settings.target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit PeakGlow", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        item.menu = menu
        statusItem = item
    }

    private static let powerItemTag = 1000

    @objc private func selectGlowMode(_ sender: NSMenuItem) {
        guard let mode = PreviewLevel(rawValue: sender.tag) else { return }
        AppState.shared.preview = mode
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let state = AppState.shared
        state.refreshPower()
        let reading = state.power.reading
        menu.item(withTag: Self.powerItemTag)?.title = reading.availability == .current
            ? String(format: "System power: %.1f W", reading.watts)
            : "Power data unavailable"
        for mode in Self.glowMenuModes {
            menu.item(withTag: mode.rawValue)?.state = state.preview == mode ? .on : .off
        }
    }

    @objc private func closeActiveWindow() {
        if bubble?.isKey == true { hover.dismissNow() }
        else { NSApp.keyWindow?.performClose(nil) }
    }

    private func applySettings() {
        let s = AppSettings.shared
        let geometry = SIMD2<Double>(s.glowScale, s.overheatScale)
        if geometry != glowGeometry {
            glowGeometry = geometry
            glow.reposition()
        }
        applyLevel()
        updateStatusItem()
        if samplingInterval != s.sampleInterval {
            samplingInterval = s.sampleInterval
            powerSampler.start(interval: samplingInterval)
        }
    }

    /// Finder reopening a background-only app should offer a visible way back in.
    func applicationShouldHandleReopen(_ sender: NSApplication,
                                      hasVisibleWindows flag: Bool) -> Bool {
        SettingsWindowController.shared.show()
        return false
    }

    /// Previews override automatic load; Hot previews the temperature tint.
    /// Actual warnings are heuristic temperature indicators, not proof of throttling.
    private func applyLevel() {
        var overheat = false
        let effective: LoadLevel
        switch AppSettings.shared.preview {
        case .auto:
            effective = lastAutoLevel
            overheat = AppSettings.shared.overheatAlarm
        case .overheat:
            effective = .high          // High base with the warm warning tint.
            overheat = true
        case .low, .medium, .high:
            effective = LoadLevel(rawValue: AppSettings.shared.preview.rawValue) ?? lastAutoLevel
        }
        if AppState.shared.effectiveLevel != effective {
            AppState.shared.effectiveLevel = effective
        }
        // Distinguish real warnings from the Hot preview in the controls.
        let alarm = overheat && AppSettings.shared.preview != .overheat
            && AppSettings.shared.overheatAlarm
        if AppState.shared.overheatAlarm != alarm { AppState.shared.overheatAlarm = alarm }
        glow.setOverheat(overheat, gainBoost: Float(AppSettings.shared.overheatGain))
        glow.setLevel(effective)
        glow.setPowerFraction(AppSettings.shared.preview == .auto ? lastPowerFraction : nil)
    }
}

