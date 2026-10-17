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
    /// Frame rate the display link should run at: the configured rate while the glow is changing,
    /// at most `calmFrameRate` once it has been steady for a couple of seconds.
    private(set) var preferredFrameRate: Double = 60
    static let calmFrameRate: Double = 30
    /// The charging light alone is slow, so it is drawn at a lower rate.
    static let chargeFrameRate: Double = 20
    /// While the island moves the loop asks for the display's best rate (120 Hz on ProMotion).
    static let islandFrameRate: Double = 120
    private var calmSince: CFTimeInterval = 0

    // MARK: - Control island
    // The island's black shell is drawn here with the glow around it, so one spring drives both.
    /// Full size of the expanded island in points.
    var islandSizePoints: CGSize = .zero
    /// Called once the island has contracted back into the notch.
    var onIslandHidden: (() -> Void)?
    private var islandTarget: Float = 0
    private var islandProgress: Float = 0
    private var islandVelocity: Float = 0
    private var islandAlpha: Float = 0
    private var islandWasActive = false
    var islandActive: Bool { islandTarget > 0.5 || islandProgress > 0.0005 || islandAlpha > 0.002 }
    /// Lower corner radius of the full island in points. The control panel is a rounded block; the
    /// charging pill, which is only as tall as the notch, is rounded to its full height.
    var islandRadiusPoints: CGFloat = IslandMetrics.expandedCornerRadius

    /// Put the island away at once, without the spring and without telling anyone it has gone.
    func resetIsland() {
        islandTarget = 0
        islandProgress = 0
        islandVelocity = 0
        islandAlpha = 0
        islandWasActive = false
    }

    func setIsland(expanded: Bool) {
        islandTarget = expanded ? 1 : 0
        if expanded { islandWasActive = true }
        calmSince = CACurrentMediaTime()
        preferredFrameRate = Self.islandFrameRate
        if isIdle { lastRender = 0 }
        isIdle = false
    }

    /// Damped spring toward the target; expansion is bouncier than contraction.
    private func stepIsland(dt: Float, reduceMotion: Bool) {
        if reduceMotion {
            // No change of shape: the shell stays full size and only fades.
            islandAlpha += (islandTarget - islandAlpha) * (1 - exp(-dt * 14))
            islandVelocity = 0
            islandProgress = (islandTarget > 0.5 || islandAlpha > 0.002) ? 1 : 0
            return
        }
        let expanding = islandTarget > 0.5
        let response: Float = expanding ? 0.46 : 0.34
        let damping: Float = expanding ? 0.74 : 0.9
        let omega = 2 * Float.pi / response
        let steps = max(1, Int((dt / (1.0 / 240)).rounded(.up)))
        let h = dt / Float(steps)
        for _ in 0..<steps {
            let acceleration = -omega * omega * (islandProgress - islandTarget) - 2 * damping * omega * islandVelocity
            islandVelocity += acceleration * h
            islandProgress += islandVelocity * h
        }
        if abs(islandProgress - islandTarget) < 0.0005, abs(islandVelocity) < 0.003 {
            islandProgress = islandTarget
            islandVelocity = 0
        }
        // The shell fades in over the first few percent so it cannot show beside the real notch.
        islandAlpha = min(1, max(0, islandProgress / 0.06))
    }
    // MARK: - Charging
    // While the battery charges the glow carries a soft green light that travels along the notch, and
    // plugging in the charger sends one ripple out from it.
    private var chargeTarget: Float = 0
    private var chargeMix: Float = 0
    private var chargePulseStart: CFTimeInterval = 0
    private var chargePulse: Float = -1
    private static let chargePulseDuration: CFTimeInterval = 1.3

    /// Charging is on while the battery takes power in and the setting allows it.
    /// Returns whether the state changed, so a caller polling the battery does not wake the loop for nothing.
    @discardableResult
    func setCharging(_ on: Bool) -> Bool {
        guard (chargeTarget > 0.5) != on else { return false }
        chargeTarget = on ? 1 : 0
        resumeForCharge()
        return true
    }

    /// One ripple, for plugging in the charger or for reaching full charge.
    func triggerChargePulse() {
        chargePulseStart = CACurrentMediaTime()
        chargePulse = 0
        resumeForCharge()
    }

    private var chargeActive: Bool { chargeTarget > 0.5 || chargeMix > 0.004 || chargePulse >= 0 }

    private func resumeForCharge() {
        calmSince = CACurrentMediaTime()
        if isIdle { lastRender = 0 }
        isIdle = false
    }

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
    /// Since when every value has been at its target with nothing animating; the loop stops after a moment of that.
    private var settledSince: CFTimeInterval?

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
        // The shader reads this struct byte for byte; refuse to draw rather than draw wrongly.
        guard MemoryLayout<Uniforms>.stride == 104 else {
            NSLog("PeakGlow: unexpected uniform layout")
            return nil
        }
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

    /// Resume for a small change without treating it as a new event: the glow settles at the calm rate.
    func nudge() {
        if isIdle { lastRender = 0 }
        isIdle = false
        settledSince = nil
        calmSince = CACurrentMediaTime() - 3
        preferredFrameRate = min(settings.frameRate, Self.calmFrameRate)
    }

    /// Resume when the target changes or the display returns.
    func wake() {
        settings = RenderingSettings()
        settledSince = nil
        // A change of state restores the full rate at once.
        calmSince = CACurrentMediaTime()
        preferredFrameRate = islandActive ? Self.islandFrameRate : settings.frameRate
        if isIdle {
            // A loop that stopped on a steady glow must wake to fade it out as well as to show a new one.
            guard Self.targetIntensity(level: targetLevel, paused: paused, ambient: ambientEnabled) > 0 || islandActive
                    || (chargeActive && !paused) || intensity > 0.004 || chargeMix > 0.004 else { return }
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
        if lastRender != 0, now - lastRender < (1.0 / (islandActive ? Self.islandFrameRate : s.frameRate)) * 0.9 { return }

        // Charging keeps a soft glow on even when the load is low.
        let targetIntensity = paused ? 0 : max(Self.targetIntensity(level: targetLevel, paused: paused, ambient: ambientEnabled),
                                               chargeTarget * 0.65)
        let targetMix: Float = targetLevel == .high ? 1 : 0

        let dt = Float(min(0.1, lastRender == 0 ? 0.033 : now - lastRender))
        let before = (intensity, modeMix, powerMix, lightMix, warningMix)
        stepIsland(dt: dt, reduceMotion: s.reduceMotion)
        let islandNowActive = islandActive
        let islandJustHidden = islandWasActive && !islandNowActive
        islandWasActive = islandNowActive
        // Leave the render pass before the window is resized.
        if islandJustHidden { DispatchQueue.main.async { [weak self] in self?.onIslandHidden?() } }
        let fadeSpeed: Float = targetLevel == .low ? 2.0 : 1.25
        let reduceMotion = s.reduceMotion
        let fade = reduceMotion ? Float(1) : 1 - exp(-dt * fadeSpeed * 3)
        intensity += (targetIntensity - intensity) * fade
        modeMix += (targetMix - modeMix) * (reduceMotion ? 1 : 1 - exp(-dt * 3))
        warningMix += ((overheat ? Float(1) : 0) - warningMix) * (reduceMotion ? 1 : 1 - exp(-dt * 2))
        let parameterFade: Float = reduceMotion ? 1 : 1 - exp(-dt * 18)
        chargeMix += (chargeTarget - chargeMix) * (reduceMotion ? 1 : 1 - exp(-dt * 2.5))
        if chargeTarget == 0 && chargeMix < 0.004 { chargeMix = 0 }
        if chargePulse >= 0 {
            // Reduce Motion drops the ripple; the steady charging tint is enough.
            let progress = Float((now - chargePulseStart) / Self.chargePulseDuration)
            chargePulse = (reduceMotion || progress >= 1) ? -1 : progress
        }
        let brightness = Float(s.glowIntensity)
        let scale = Float(s.glowScale)
        let opacity = Float(s.mediumAlpha)
        smoothedBrightness = (smoothedBrightness ?? brightness) + (brightness - (smoothedBrightness ?? brightness)) * parameterFade
        smoothedScale = (smoothedScale ?? scale) + (scale - (smoothedScale ?? scale)) * parameterFade
        smoothedOpacity = (smoothedOpacity ?? opacity) + (opacity - (smoothedOpacity ?? opacity)) * parameterFade
        let targetPower = powerFraction ?? Self.fixedPowerFraction(for: targetLevel)
        powerMix += (targetPower - powerMix) * (reduceMotion ? 1 : 1 - exp(-dt * 2.5))
        lightMix += (s.lightTarget - lightMix) * (reduceMotion ? 1 : 1 - exp(-dt * 3))
        // Rate of change of everything that moves the glow's look, per second.
        let moved = abs(intensity - before.0) + abs(modeMix - before.1) + abs(powerMix - before.2)
            + abs(lightMix - before.3) + abs(warningMix - before.4)
        if moved / max(dt, 0.001) > 0.08 || calmSince == 0 { calmSince = now }
        if chargePulse >= 0 { calmSince = now }
        if islandActive {
            calmSince = now
            preferredFrameRate = Self.islandFrameRate
        } else {
            preferredFrameRate = now - calmSince > 2 ? min(s.frameRate, Self.calmFrameRate) : s.frameRate
        }
        // Nothing is moving once every value has reached its target and nothing animates by itself
        // (the island, the plug-in ripple, the charging light, the breathing at high load, the warning
        // tint's drift). A steady glow is one still picture, so the loop stops instead of redrawing it.
        let eps: Float = 0.002
        let converging = abs(intensity - targetIntensity) > eps || abs(modeMix - targetMix) > eps
            || abs(powerMix - targetPower) > eps || abs(lightMix - s.lightTarget) > eps
            || abs(warningMix - (overheat ? 1 : 0)) > eps
            || abs((smoothedBrightness ?? brightness) - brightness) > eps
            || abs((smoothedScale ?? scale) - scale) > eps || abs((smoothedOpacity ?? opacity) - opacity) > eps
            || abs(chargeMix - chargeTarget) > eps
        let animating = islandActive || chargePulse >= 0 || modeMix > 0.003
            || (!reduceMotion && (chargeMix > 0.004 || warningMix > 0.003))
        if converging || animating { settledSince = nil } else if settledSince == nil { settledSince = now }
        let sleepAfterFrame = settledSince.map { now - $0 > 0.4 } ?? false
        // The charging light alone moves slowly (one pass in five seconds), so it does not need many frames.
        if !islandActive, chargePulse < 0, !converging, modeMix < 0.003, chargeMix > 0.004, !reduceMotion, warningMix < 0.003 {
            preferredFrameRate = min(preferredFrameRate, Self.chargeFrameRate)
        }
        if !reduceMotion { animationTime += dt }
        lastRender = now

        // Finish with a transparent frame before stopping rendering.
        let finishingFade = intensity < 0.004 && targetIntensity == 0 && !chargeActive
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
            lightMix: lightMix,
            islandSize: SIMD2<Float>(Float(islandSizePoints.width * layer.contentsScale),
                                     Float(islandSizePoints.height * layer.contentsScale)),
            islandProgress: islandProgress,
            islandAlpha: islandAlpha,
            islandRadius: Float(islandRadiusPoints * layer.contentsScale),
            chargeMix: chargeMix,
            chargePulse: chargePulse,
            chargeMotion: reduceMotion ? 0 : 1)

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
        if (finishingFade && !islandActive) || sleepAfterFrame { isIdle = true }
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
    var islandSize: SIMD2<Float>
    var islandProgress: Float
    var islandAlpha: Float
    var islandRadius: Float
    var chargeMix: Float
    var chargePulse: Float
    var chargeMotion: Float
}

