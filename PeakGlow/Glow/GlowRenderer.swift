import AppKit
import Metal
import QuartzCore

/// Metal renderer driven by the main-run-loop CADisplayLink.
/// Interpolate load and appearance changes without rebuilding the pipeline.
@MainActor final class GlowRenderer {
    // Accessed on the main thread only.
    var targetLevel: LoadLevel = .low   // Auto may retain a subtle ambient glow.
    /// Smoothed system power as a 0...1 position on the colour ramp; nil uses a fixed position for the level.
    var powerFraction: Float?
    var headroom: Float = 1.0
    var ambientEnabled = false
    var paused = false                  // Paused by display or controller state.
    /// Temperature warning fades into a steady warm tint.
    var overheat = false
    /// Temperature-alert brightness multiplier supplied by Settings.
    var overheatGain: Float = 1.5
    /// True after the final transparent frame; the host stops its display link.
    private(set) var isIdle = true

    private let layer: CAMetalLayer
    private let commandQueue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let framesInFlight = DispatchSemaphore(value: 2)
    private var settings = RenderingSettings()

    /// Read preferences on state changes, not from the display-link hot path.
    @MainActor private struct RenderingSettings {
        let frameRate: Double
        let glowIntensity: Double
        let glowScale: Double
        let mediumAlpha: Double
        let hdrFactor: Double
        let pulseHz: Double
        let overheatScale: Double
        let reduceMotion: Bool
        /// 1 when the glow is tuned for a bright wallpaper, 0 for a dark one.
        let lightTarget: Float

        init() {
            let s = AppSettings.shared
            frameRate = s.frameRate
            glowIntensity = s.glowIntensity
            glowScale = s.glowScale
            mediumAlpha = s.mediumAlpha
            hdrFactor = s.hdrFactor
            pulseHz = s.pulseHz
            overheatScale = s.overheatScale
            reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            switch s.glowWallpaper {
            case 1: lightTarget = 1
            case 2: lightTarget = 0
            default:
                let match = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])
                lightTarget = match == .aqua ? 1 : 0
            }
        }
    }

    private var intensity: Float = 0
    private var modeMix: Float = 0
    private var powerMix: Float = 0
    private var lightMix: Float = 0
    private var lastRender: CFTimeInterval = 0
    private var animationTime: Float = 0

    private var smoothedBrightness: Float?
    private var smoothedScale: Float?
    private var smoothedOpacity: Float?
    private var warningMix: Float = 0          // Temperature tint interpolation, from zero to one.

    /// Notch center in drawable pixels, set on the main thread.
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

    /// Resume when the target changes or the display returns.
    func wake() {
        settings = RenderingSettings()
        if isIdle {
            guard Self.targetIntensity(level: targetLevel, paused: paused, ambient: ambientEnabled) > 0 else { return }
            // Don't integrate the whole time spent idle into the first resumed frame.
            lastRender = 0
        }
        isIdle = false
    }

    /// Position on the colour ramp for previews and for Auto before a reading arrives.
    static func fixedPowerFraction(for level: LoadLevel) -> Float {
        switch level {
        case .low: return 0.12
        case .medium: return 0.5
        case .high: return 0.9
        }
    }

    /// Map watts to 0...1 around the user's thresholds: about 0.4 at the full-glow threshold,
    /// 0.8 at the Boost threshold, and 1.0 at 1.4 times the Boost threshold.
    static func powerFraction(watts: Double, medium: Double, high: Double) -> Float {
        let points: [(Double, Double)] = [(medium * 0.25, 0), (medium, 0.4), (high, 0.8), (high * 1.4, 1)]
        guard watts > points[0].0 else { return 0 }
        for i in 1..<points.count where watts <= points[i].0 {
            let (x0, y0) = points[i - 1], (x1, y1) = points[i]
            return Float(y0 + (y1 - y0) * (watts - x0) / max(x1 - x0, 0.001))
        }
        return 1
    }

    /// The inverse of `powerFraction`: the power at which the glow reaches a ramp position.
    static func watts(forPowerFraction fraction: Double, medium: Double, high: Double) -> Double {
        let points: [(Double, Double)] = [(medium * 0.25, 0), (medium, 0.4), (high, 0.8), (high * 1.4, 1)]
        let f = min(max(fraction, 0), 1)
        for i in 1..<points.count where f <= points[i].1 {
            let (x0, y0) = points[i - 1], (x1, y1) = points[i]
            return x0 + (x1 - x0) * (f - y0) / max(y1 - y0, 0.001)
        }
        return points[3].0
    }

    /// Off and pauses always override the automatic low-load glow.
    static func targetIntensity(level: LoadLevel, paused: Bool, ambient: Bool) -> Float {
        if paused { return 0 }
        return level == .low ? (ambient ? 0.55 : 0) : 1
    }

    // MARK: - Main-thread rendering

    func renderFrame(now: CFTimeInterval) {
        let s = settings
        if lastRender != 0, now - lastRender < (1.0 / s.frameRate) * 0.9 { return }

        let targetIntensity = Self.targetIntensity(level: targetLevel, paused: paused, ambient: ambientEnabled)
        let targetMix: Float = targetLevel == .high ? 1 : 0

        let dt = Float(min(0.1, lastRender == 0 ? 0.033 : now - lastRender))
        let fadeSpeed: Float = targetLevel == .low ? 2.0 : 1.25
        let reduceMotion = s.reduceMotion
        let fade = reduceMotion ? Float(1) : 1 - exp(-dt * fadeSpeed * 3)
        intensity += (targetIntensity - intensity) * fade
        modeMix += (targetMix - modeMix) * (reduceMotion ? 1 : 1 - exp(-dt * 3))
        warningMix += ((overheat ? Float(1) : 0) - warningMix) * (reduceMotion ? 1 : 1 - exp(-dt * 2))
        let parameterFade: Float = reduceMotion ? 1 : 1 - exp(-dt * 18)
        let brightness = Float(s.glowIntensity)
        let scale = Float(s.glowScale)
        let opacity = Float(s.mediumAlpha)
        smoothedBrightness = (smoothedBrightness ?? brightness) + (brightness - (smoothedBrightness ?? brightness)) * parameterFade
        smoothedScale = (smoothedScale ?? scale) + (scale - (smoothedScale ?? scale)) * parameterFade
        smoothedOpacity = (smoothedOpacity ?? opacity) + (opacity - (smoothedOpacity ?? opacity)) * parameterFade
        let targetPower = powerFraction ?? Self.fixedPowerFraction(for: targetLevel)
        powerMix += (targetPower - powerMix) * (reduceMotion ? 1 : 1 - exp(-dt * 2.5))
        lightMix += (s.lightTarget - lightMix) * (reduceMotion ? 1 : 1 - exp(-dt * 3))
        if !reduceMotion { animationTime += dt }
        lastRender = now

        // Finish with a transparent frame before stopping rendering.
        let finishingFade = intensity < 0.004 && targetIntensity == 0
        if finishingFade { intensity = 0 }
        isIdle = false

        // Under GPU pressure, skip a frame instead of waiting on the UI thread.
        guard framesInFlight.wait(timeout: .now()) == .success else { return }
        var submitted = false
        defer { if !submitted { framesInFlight.signal() } }
        guard let drawable = layer.nextDrawable() else { return }
        let drawableSize = layer.drawableSize

        // Never generate an EDR gain below SDR white or beyond screen headroom.
        let available = max(1, headroom)
        let baseBoost = min(available, 1 + (available - 1) * Float(s.hdrFactor) * 0.35)

        var uniforms = Uniforms(
            resolution: SIMD2<Float>(Float(drawableSize.width), Float(drawableSize.height)),
            notchCenter: SIMD2<Float>(Float(notchCenterPixels.x), Float(notchCenterPixels.y)),
            notchSize: SIMD2<Float>(Float(notchSizePixels.width), Float(notchSizePixels.height)),
            time: animationTime,
            intensity: intensity * (smoothedBrightness ?? brightness),
            modeMix: modeMix,
            hdrBoost: baseBoost,
            pulseHz: Float(s.pulseHz),
            glowScale: (smoothedScale ?? scale) * Float(layer.contentsScale),
            mediumAlpha: smoothedOpacity ?? opacity,
            warningMix: warningMix,
            redGain: overheatGain,
            redScale: Float(s.overheatScale),
            powerMix: powerMix,
            lightMix: lightMix)

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
        let completionGate = framesInFlight
        cmd.addCompletedHandler { _ in completionGate.signal() }
        cmd.present(drawable)
        submitted = true
        cmd.commit()
        // Submit a truly transparent final frame before stopping the display link.
        if finishingFade { isIdle = true }
    }
}

/// Memory layout must match the Metal shader uniforms.
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
    var powerMix: Float
    var lightMix: Float
}

