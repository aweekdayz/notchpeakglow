import AppKit
import Metal
import QuartzCore

/// Metal 渲染器：Timer 主线程驱动（单线程访问，无锁），
/// 档位间平滑过渡
final class GlowRenderer {
    // 仅主线程访问
    var targetLevel: LoadLevel = .low   // low → intensity 0
    var headroom: Float = 1.0
    var ambientEnabled = false
    var paused = false                  // 全屏/睡眠时
    /// Temperature warning fades into a steady warm tint.
    var overheat = false
    /// 过热红光相对蓝色的额外增益（×），由设置传入
    var overheatGain: Float = 1.5
    /// 完全淡出后为 true，宿主视图据此暂停 Timer（零功耗）
    private(set) var isIdle = true

    private let layer: CAMetalLayer
    private let commandQueue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState

    private var intensity: Float = 0
    private var modeMix: Float = 0
    private var lastRender: CFTimeInterval = 0
    private var animationTime: Float = 0

    private var warningMix: Float = 0          // 温度暖色过渡 0..1

    /// notch 中心（像素），由主线程设置
    var notchCenterPixels: CGPoint = .zero
    var notchSizePixels: CGSize = .zero

    init?(layer: CAMetalLayer) {
        self.layer = layer
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        layer.device = device
        guard let queue = device.makeCommandQueue() else { return nil }
        self.commandQueue = queue

        guard let lib = device.makeDefaultLibrary(),
              let fnv = lib.makeFunction(name: "vertexShader"),
              let fnf = lib.makeFunction(name: "fragmentShader") else {
            NSLog("PeakGlow: shader functions not found")
            return nil
        }
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = fnv
        desc.fragmentFunction = fnf
        desc.colorAttachments[0].pixelFormat = layer.pixelFormat
        guard let pso = try? device.makeRenderPipelineState(descriptor: desc) else {
            return nil
        }
        self.pipeline = pso
        layer.isOpaque = false
    }

    /// 有新目标（档位变化/恢复）时唤醒
    func wake() {
        isIdle = false
    }

    /// Off and pauses always override the automatic low-load glow.
    static func targetIntensity(level: LoadLevel, paused: Bool, ambient: Bool) -> Float {
        if paused { return 0 }
        return level == .low ? (ambient ? 0.55 : 0) : 1
    }

    // MARK: - 渲染（主线程，Timer 驱动）

    func renderFrame(now: CFTimeInterval) {
        if lastRender != 0, now - lastRender < (1.0 / AppSettings.shared.frameRate) * 0.9 { return }
        let s = AppSettings.shared

        let targetIntensity = Self.targetIntensity(level: targetLevel, paused: paused, ambient: ambientEnabled)
        let targetMix: Float = targetLevel == .high ? 1 : 0

        let dt = Float(min(0.1, lastRender == 0 ? 0.033 : now - lastRender))
        let fadeSpeed: Float = targetLevel == .low ? 2.0 : 1.25
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let fade = reduceMotion ? Float(1) : 1 - exp(-dt * fadeSpeed * 3)
        intensity += (targetIntensity - intensity) * fade
        modeMix += (targetMix - modeMix) * (reduceMotion ? 1 : 1 - exp(-dt * 3))
        warningMix += ((overheat ? Float(1) : 0) - warningMix) * (reduceMotion ? 1 : 1 - exp(-dt * 2))
        if !reduceMotion { animationTime += dt }
        lastRender = now

        // 完全隐藏 → 通知宿主暂停 Timer
        if intensity < 0.004, targetIntensity == 0 {
            intensity = 0
            isIdle = true
            return
        }
        isIdle = false

        guard let drawable = layer.nextDrawable() else { return }
        let drawableSize = layer.drawableSize

        // Never generate an EDR gain below SDR white or beyond screen headroom.
        let available = max(1, headroom)
        let baseBoost = min(available, 1 + (available - 1) * Float(s.hdrFactor) * 0.35)

        var uniforms = Uniforms(
            resolution: SIMD2<Float>(Float(drawableSize.width), Float(drawableSize.height)),
            notchCenter: SIMD2<Float>(Float(notchCenterPixels.x), Float(notchCenterPixels.y)),
            notchSize: SIMD2<Float>(Float(notchSizePixels.width), Float(notchSizePixels.height)),
            time: reduceMotion ? 0 : animationTime,
            intensity: intensity * Float(s.glowIntensity),
            modeMix: modeMix,
            hdrBoost: baseBoost,
            pulseHz: Float(s.pulseHz),
            glowScale: Float(s.glowScale) * Float(layer.contentsScale),
            mediumAlpha: Float(s.mediumAlpha),
            warningMix: warningMix,
            redGain: overheatGain,
            redScale: Float(s.overheatScale))

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)

        guard let cmd = commandQueue.makeCommandBuffer(),
              let encoder = cmd.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        encoder.endEncoding()
        cmd.present(drawable)
        cmd.commit()
    }
}

/// 与 shader 中结构体对齐
struct Uniforms {
    var resolution: SIMD2<Float>
    var notchCenter: SIMD2<Float>
    var notchSize: SIMD2<Float>
    var time: Float
    var intensity: Float
    var modeMix: Float
    var hdrBoost: Float
    var pulseHz: Float
    var glowScale: Float
    var mediumAlpha: Float
    var warningMix: Float
    var redGain: Float
    var redScale: Float
}

