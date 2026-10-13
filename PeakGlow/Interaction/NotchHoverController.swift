import AppKit

/// 刘海悬停检测：驻留触发气泡；收起依据"真实鼠标位置轮询"（刘海∪气泡∪间隙之外持续1s）
final class NotchHoverController {
    var onShowBubble: (() -> Void)?
    var onHideBubble: (() -> Void)?
    var onEngageBubble: ((Bool) -> Void)?
    /// 气泡全局 frame 提供者（AppKit 全局坐标，与 NSEvent.mouseLocation 同系）
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

    // MARK: - 生命周期

    func start() {
        reposition()
        NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in self?.menuTracking = true }
        NotificationCenter.default.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            self?.menuTracking = false
            self?.outsideSince = nil
        }
        // 唤醒/切空间/屏幕参数变化会成串触发（3~6次/秒），
        // 全部合并防抖：此前每次都销毁重建 NSPanel，唤醒瞬间产生大量
        // WindowServer 窗口创建/销毁 RPC，造成数秒 CPU 尖峰
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in self?.scheduleReposition() }

        // 睡眠唤醒/空间切换后，系统可能隐藏 stationary 面板 → 主动恢复
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.screensDidWakeNotification,
                       object: nil, queue: .main) { [weak self] _ in self?.scheduleReposition() }
        ws.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification,
                       object: nil, queue: .main) { [weak self] _ in self?.scheduleReposition() }

        // 看门狗：周期自检悬停热区仍在屏（兜底上述通知未覆盖的场景）
        watchdogTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.ensureVisible()
        }
    }

    /// 合并 0.5s 内的连续 reposition 请求为一次
    private func scheduleReposition() {
        pendingReposition?.invalidate()
        pendingReposition = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            self?.pendingReposition = nil
            self?.reposition()
        }
    }

    /// 悬停热区健康检查：不可见/被遮蔽时恢复
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
        // 复用已有面板：仅 setFrame/orderFront，不做销毁重建
        guard let screen = NotchedScreenFinder.find(),
              let notch = NotchedScreenFinder.notchRect(of: screen) else {
            hoverPanel?.orderOut(nil)   // 仅隐藏；屏幕恢复后由 reposition 重新显示
            return
        }
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
            p.hidesOnDeactivate = false   // 关键：锁屏/切 App 时系统默认会收起面板
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

    // MARK: - 对外

    func dismissNow() {
        hideBubble()
    }

    func openForInteraction() {
        dwellTimer?.invalidate()
        dwellTimer = nil
        if !bubbleVisible { showBubble() }
        engage(forKeyboard: true)
    }

    private func engage(forKeyboard: Bool = false) {
        guard !engaged || (forKeyboard && !keyboardEngaged) else { return }
        engaged = true
        keyboardEngaged = keyboardEngaged || forKeyboard
        outsideSince = nil
        if outsidePoll == nil { startOutsideWatch() }
        onEngageBubble?(forKeyboard)
    }

    // MARK: - 内部

    fileprivate func mouseEnteredNotch() {
        cancelOutsideWatch()
        guard !bubbleVisible else { return }
        dwellTimer?.invalidate()
        let timer = Timer(timeInterval: max(0, AppSettings.shared.hoverDwell), repeats: false) { [weak self] _ in
            guard let self, !self.bubbleVisible, self.notchFrame.insetBy(dx: -4, dy: -4).contains(NSEvent.mouseLocation) else { return }
            self.dwellTimer = nil
            self.showBubble()
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
        // 触控板 haptic 反馈（Magic Trackpad/内建触控板有效，鼠标静默）
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
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

    // MARK: - 外部监测

    private func startOutsideWatch() {
        outsidePoll?.invalidate()
        outsidePoll = nil
        outsideSince = nil
        outsidePoll = Timer(
            timeInterval: 0.04, repeats: true) { [weak self] _ in
            self?.checkOutside()
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
            // 刘海与气泡之间的空隙带也算"在内"（移动路径）
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
            // 点击了其他 App 的窗口 → 立即收起
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

/// 纯热区视图
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

