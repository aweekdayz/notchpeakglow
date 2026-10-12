import AppKit
import Metal
import QuartzCore

/// CAMetalLayer 宿主视图：主线程 CADisplayLink 驱动渲染（common mode，空闲自动停止）
final class GlowMetalView: NSView {
    override var wantsUpdateLayer: Bool { true }
    private(set) var renderer: GlowRenderer?
    private var renderLink: CADisplayLink?
    private var timerHz: Double = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func makeBackingLayer() -> CALayer {
        let layer = CAMetalLayer()
        layer.pixelFormat = .rgba16Float
        layer.framebufferOnly = true
        layer.isOpaque = false
        layer.backgroundColor = NSColor.clear.cgColor
        return layer
    }

    func setup(screen: NSScreen, notchRectGlobal: CGRect) {
        guard let metalLayer = layer as? CAMetalLayer else { return }
        metalLayer.contentsScale = screen.backingScaleFactor
        // 显式同步 bounds（AppKit 可能不替我们更新自定义 backing layer）
        if metalLayer.bounds != bounds {
            metalLayer.bounds = bounds
        }
        if renderer == nil {
            renderer = GlowRenderer(layer: metalLayer)
        }
        updateDrawableSize()
        updateNotchCenter(notchRectGlobal: notchRectGlobal)
    }

    /// macOS 的 CAMetalLayer.drawableSize 不随 bounds 自动更新，必须手动同步
    private func updateDrawableSize() {
        guard let metalLayer = layer as? CAMetalLayer else { return }
        let size = CGSize(width: bounds.width * metalLayer.contentsScale,
                          height: bounds.height * metalLayer.contentsScale)
        if metalLayer.drawableSize != size {
            metalLayer.drawableSize = size
        }
    }

    override func layout() {
        super.layout()
        updateDrawableSize()
    }

    /// 档位变化时由外部调用：唤醒渲染
    func wake() {
        renderer?.wake()
        guard renderer?.isIdle == false else { return }
        startDisplayLinkIfNeeded()
    }

    func sleep() {
        renderLink?.invalidate()
        renderLink = nil
    }

    private func startDisplayLinkIfNeeded() {
        let hz = Float(AppSettings.shared.frameRate)
        if renderLink != nil, timerHz == Double(hz) { return }
        sleep()
        let link = self.displayLink(target: self, selector: #selector(renderTick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: min(15, hz), maximum: hz, preferred: hz)
        link.add(to: .main, forMode: .common)
        renderLink = link
        timerHz = Double(hz)
    }

    @objc private func renderTick(_ link: CADisplayLink) {
        guard let renderer else { sleep(); return }
        renderer.renderFrame(now: link.timestamp)
        if renderer.isIdle { sleep() }
    }

    /// notch 中心 → 本视图像素坐标（左上原点）。
    /// 纯算术：不依赖 convert()（实测其在非翻转视图/无边框窗口下结果错误）
    func updateNotchCenter(notchRectGlobal: CGRect) {
        guard let metalLayer = layer as? CAMetalLayer else { return }
        lastNotchRect = notchRectGlobal
        guard let winFrame = window?.frame else { return }
        let scale = metalLayer.contentsScale
        let x = (notchRectGlobal.midX - winFrame.minX) * scale
        // Preserve physical notch geometry; the shader lights its outer contour.
        let y = (winFrame.maxY - notchRectGlobal.midY) * scale
        renderer?.notchCenterPixels = CGPoint(x: x, y: y)
        renderer?.notchSizePixels = CGSize(width: notchRectGlobal.width * scale,
                                          height: notchRectGlobal.height * scale)
    }

    private var lastNotchRect: CGRect?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil, let n = lastNotchRect {
            updateNotchCenter(notchRectGlobal: n)
        }
    }
}

