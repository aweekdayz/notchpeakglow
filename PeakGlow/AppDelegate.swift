import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let sampler = CPUSampler()
    private let powerSampler = PowerSampler()
    private let thermal = OverheatDetector()
    private let stateMachine = LoadLevelStateMachine()
    private let glow = GlowWindow()
    private let hover = NotchHoverController()
    private let gamepad = GamepadDetector()
    private var bubble: BubblePanelController?

    private var lastAutoLevel: LoadLevel = .low
    private var samplingInterval = AppSettings.shared.sampleInterval
    private var settingsUpdate: DispatchWorkItem?
    private var glowGeometry = SIMD2<Double>(AppSettings.shared.glowScale, AppSettings.shared.overheatScale)

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 机型自动调优：仅首次启动写入建议阈值（不覆盖手动调整）
        if !AppSettings.shared.powerTuned {
            let mp = MachineProfile.current
            AppSettings.shared.mediumWatts = mp.suggestedMediumWatts
            AppSettings.shared.highWatts = mp.suggestedHighWatts
            AppSettings.shared.powerTuned = true
            NSLog("PeakGlow: machine tuned \(mp.summary) -> \(mp.suggestedMediumWatts)W/\(mp.suggestedHighWatts)W")
        }

        installMainMenu()
        bubble = BubblePanelController(hover: hover)
        // 采样 → 状态机（仅整机功率信号；CPU% 仅作显示）
        var wattWindow: [Double] = []
        sampler.onSample = { [weak self] avg in
            guard let self else { return }
            let state = AppState.shared

            let reading = powerSampler.readWatts()
            state.recordPower(reading)
            guard let w = reading, w.isFinite, w > 0 else {
                wattWindow.removeAll()
                stateMachine.discardPendingTransition()
                return
            }
            // 5 样本滑动平均（默认 0.5s 采样 = 2.5s 窗口），滤除瞬时尖峰
            wattWindow.append(w)
            if wattWindow.count > 5 { wattWindow.removeFirst() }
            stateMachine.update(watts: wattWindow.reduce(0, +) / Double(wattWindow.count))
        }
        stateMachine.onLevelChange = { [weak self] level in
            guard let self else { return }
            self.lastAutoLevel = level
            self.applyLevel()
        }

        // 设置变化：光晕宽度/预览即时生效
        NotificationCenter.default.addObserver(
            forName: AppSettings.changedNotification,
            object: nil, queue: .main) { [weak self] _ in
            guard let self, self.settingsUpdate == nil else { return }
            let update = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.settingsUpdate = nil
                self.applySettings()
            }
            self.settingsUpdate = update
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 / 60.0, execute: update)
        }

        // 手柄检测：连接任意手柄 → 暂停光晕（游戏中不打扰）
        gamepad.onGamepadChange = { [weak self] connected in
            AppState.shared.gamepadConnected = connected
            self?.glow.setPaused(connected)
        }

        // 过热监测：真实过热时自动开启红闪（预览"热"档外的叠加通道）
        thermal.onOverheatChange = { [weak self] hot in
            guard let self else { return }
            AppSettings.shared.overheatAlarm = hot
            self.applyLevel()
        }

        // 屏幕睡眠/唤醒
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.screensDidSleepNotification,
                       object: nil, queue: .main) { [weak self] _ in
            self?.glow.setScreenAsleep(true)
        }
        ws.addObserver(forName: NSWorkspace.screensDidWakeNotification,
                       object: nil, queue: .main) { [weak self] _ in
            self?.glow.setScreenAsleep(false)
        }

        glow.start()
        hover.start()
        gamepad.start()
        thermal.start()
        sampler.start(interval: AppSettings.shared.sampleInterval)
        applyLevel()   // start 之后再应用一次（renderer 此时已创建）

        FirstRunWindow.showIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        settingsUpdate?.cancel()
        glow.shutdown()
        sampler.stop()
    }

    private func installMainMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "PeakGlow")
        appItem.submenu = appMenu
        menu.addItem(appItem)
        let settings = appMenu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide PeakGlow", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
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
        let controls = windowMenu.addItem(withTitle: "Show PeakGlow Controls", action: #selector(openControls), keyEquivalent: "")
        controls.target = self
        let close = windowMenu.addItem(withTitle: "Close Window", action: #selector(closeActiveWindow), keyEquivalent: "w")
        close.target = self
        NSApp.mainMenu = menu
        NSApp.windowsMenu = windowMenu
    }

    @objc private func openSettings() {
        hover.dismissNow()
        SettingsWindowController.shared.show()
    }

    @objc private func openControls() { hover.openForInteraction() }

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
        if samplingInterval != s.sampleInterval {
            samplingInterval = s.sampleInterval
            sampler.start(interval: samplingInterval)
        }
    }

    /// Finder reopening a background-only app should offer a visible way back in.
    func applicationShouldHandleReopen(_ sender: NSApplication,
                                      hasVisibleWindows flag: Bool) -> Bool {
        SettingsWindowController.shared.show()
        return false
    }

    /// 预览优先，否则自动档位；温度预览叠加平滑暖色提醒
    /// 真实过热（SMC Tp 温度 ≥96°C / thermalState critical）在非关闭档下叠加暖色提醒
    private func applyLevel() {
        var overheat = false
        let effective: LoadLevel
        switch AppSettings.shared.preview {
        case .auto:
            effective = lastAutoLevel
            overheat = AppSettings.shared.overheatAlarm
        case .overheat:
            effective = .high          // 蓝色呼吸基底 + 红闪
            overheat = true
        case .low, .medium, .high:
            effective = LoadLevel(rawValue: AppSettings.shared.preview.rawValue) ?? lastAutoLevel
        }
        if AppState.shared.effectiveLevel != effective {
            AppState.shared.effectiveLevel = effective
        }
        // 真实过热（非预览）时同步给气泡 UI 做状态区分
        let alarm = overheat && AppSettings.shared.preview != .overheat
            && AppSettings.shared.overheatAlarm
        if AppState.shared.overheatAlarm != alarm { AppState.shared.overheatAlarm = alarm }
        glow.setOverheat(overheat, gainBoost: Float(AppSettings.shared.overheatGain))
        glow.setLevel(effective)
    }
}

