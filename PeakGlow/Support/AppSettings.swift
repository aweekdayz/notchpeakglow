import Foundation
import Combine

enum PreviewLevel: Int, CaseIterable {
    case low = 0, medium = 1, high = 2, auto = 3, overheat = 4

    var label: String {
        switch self {
        case .low: return "Off"
        case .medium: return "Mid"
        case .high: return "High"
        case .auto: return "Auto"
        case .overheat: return "Hot"
        }
    }

    /// One plain sentence for what the choice does. Mid, High and Hot are previews.
    var explanation: String {
        switch self {
        case .auto: return "Follows your Mac's power"
        case .low: return "Glow is off"
        case .medium: return "Preview: medium power"
        case .high: return "Preview: high power"
        case .overheat: return "Preview: temperature warning"
        }
    }

    /// The order shown in the panel, the menu bar menu and Settings.
    static let displayOrder: [PreviewLevel] = [.auto, .low, .medium, .high, .overheat]
}

/// Preferences accessed by main-thread sampling, rendering and SwiftUI controls.
@MainActor final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    static let changedNotification = Notification.Name("AppSettingsChanged")

    private let d = UserDefaults.standard

    private init() {
        if !d.bool(forKey: "aweekdayzPreferencesV1") {
            // Compatibility-only namespace: preserve settings from the previous app.
            let legacy = d.persistentDomain(forName: "com.sirosafc.peakglow") ?? [:]
            let existing = Bundle.main.bundleIdentifier.flatMap { d.persistentDomain(forName: $0) } ?? [:]
            for (key, value) in Self.preferencesToMigrate(legacy: legacy, existing: existing) {
                d.set(value, forKey: key)
            }
            d.set(true, forKey: "aweekdayzPreferencesV1")
        }
        // An alert belongs to the current process, never the previous launch.
        d.removeObject(forKey: Key.overheatAlarm)
        // Migrate the previous factory delay once; preserve custom delays.
        if !d.bool(forKey: "responsiveHoverV1") {
            if let delay = d.object(forKey: "hoverDwell") as? Double, abs(delay - 0.3) < 0.001 {
                d.set(Defaults.hoverDwell, forKey: "hoverDwell")
            }
            d.set(true, forKey: "responsiveHoverV1")
        }
    }

    // MARK: - Keys
    private enum Key {
        static let mediumWatts = "mediumWatts"
        static let highWatts = "highWatts"
        static let holdOnSeconds = "holdOnSeconds"
        static let hysteresisWatts = "hysteresisWatts"
        static let sampleInterval = "sampleInterval"
        static let ambientGlow = "ambientGlow"
        static let glowScale = "glowScale"
        static let glowIntensity = "glowIntensity"
        static let mediumAlpha = "mediumAlpha"
        static let pulseHz = "pulseHz"
        static let hdrFactor = "hdrFactor"
        static let overheatGain = "overheatGain"
        static let overheatScale = "overheatScale"
        static let frameRate = "frameRate"
        static let hoverDwell = "hoverDwell"
        static let previewLevel = "previewLevel"
        static let powerTuned = "powerTuned"
        static let firstRunDone = "firstRunDone"
        static let overheatAlarm = "overheatAlarm"
        static let overheatAlertEnabled = "overheatAlertEnabled"
        static let menuBarIcon = "menuBarIcon"
        static let glowWallpaper = "glowWallpaper"
        static let migratable = [mediumWatts, highWatts, holdOnSeconds, hysteresisWatts,
            sampleInterval, ambientGlow, glowScale, glowIntensity, mediumAlpha, pulseHz,
            hdrFactor, overheatGain, overheatScale, frameRate, hoverDwell, previewLevel,
            powerTuned, firstRunDone, overheatAlertEnabled, "responsiveHoverV1"]
    }

    /// Import recognized preferences only; values already in the new domain win.
    static func preferencesToMigrate(legacy: [String: Any], existing: [String: Any]) -> [String: Any] {
        var result: [String: Any] = [:]
        for key in Key.migratable where existing[key] == nil {
            if let value = legacy[key] { result[key] = value }
        }
        return result
    }

    // MARK: - Defaults
    // Factory defaults; power thresholds depend on the detected family.
    @MainActor struct Defaults {
        static let mediumWatts = MachineProfile.current.suggestedMediumWatts
        static let highWatts = MachineProfile.current.suggestedHighWatts
        static let holdOnSeconds = 1.2
        static let hysteresisWatts = 4.0
        static let sampleInterval = 0.5
        static let glowScale = 0.90
        static let glowIntensity = 0.80
        static let mediumAlpha = 0.48
        static let pulseHz = 0.22
        static let hdrFactor = 1.2
        static let overheatGain = 1.1
        static let overheatScale = 1.0
        // Maximum rate; the glow slows to 30 fps when nothing is changing.
        static let frameRate = 60.0
        static let hoverDwell = 0.08
        static let previewLevel = PreviewLevel.auto.rawValue
        static let powerTuned = false
        static let firstRunDone = false
    }

    private func get<T>(_ key: String, _ fallback: T) -> T {
        let v = d.object(forKey: key)
        return (v as? T) ?? fallback
    }

    private func set<T: Equatable>(_ value: T, _ key: String) {
        guard (d.object(forKey: key) as? T) != value else { return }
        objectWillChange.send()
        d.set(value, forKey: key)
        NotificationCenter.default.post(name: Self.changedNotification, object: nil)
    }

    // MARK: - Power thresholds
    var mediumWatts: Double {
        get { get(Key.mediumWatts, Defaults.mediumWatts) }
        set { set(Double(newValue), Key.mediumWatts) }
    }
    var highWatts: Double {
        get { get(Key.highWatts, Defaults.highWatts) }
        set { set(Double(newValue), Key.highWatts) }
    }
    var holdOnSeconds: Double {
        get { get(Key.holdOnSeconds, Defaults.holdOnSeconds) }
        set { set(Double(newValue), Key.holdOnSeconds) }
    }
    var hysteresisWatts: Double {
        get { get(Key.hysteresisWatts, Defaults.hysteresisWatts) }
        set { set(Double(newValue), Key.hysteresisWatts) }
    }
    var sampleInterval: Double {
        // Match the Settings range so a stored out-of-range value cannot stall or flood the timer.
        get { min(3, max(0.2, get(Key.sampleInterval, Defaults.sampleInterval))) }
        set { set(Double(newValue), Key.sampleInterval) }
    }

    // MARK: - Appearance
    /// Whether Auto retains a subtle glow at low load.
    var ambientGlow: Bool {
        get { get(Key.ambientGlow, true) }
        set { set(newValue, Key.ambientGlow) }
    }

    var glowScale: Double {
        get { get(Key.glowScale, Defaults.glowScale) }
        set { set(Double(newValue), Key.glowScale) }
    }
    var glowIntensity: Double {
        get { get(Key.glowIntensity, Defaults.glowIntensity) }
        set { set(Double(newValue), Key.glowIntensity) }
    }
    var mediumAlpha: Double {
        get { get(Key.mediumAlpha, Defaults.mediumAlpha) }
        set { set(Double(newValue), Key.mediumAlpha) }
    }
    var pulseHz: Double {
        get { get(Key.pulseHz, Defaults.pulseHz) }
        set { set(Double(newValue), Key.pulseHz) }
    }
    var hdrFactor: Double {
        get { get(Key.hdrFactor, Defaults.hdrFactor) }
        set { set(Double(newValue), Key.hdrFactor) }
    }
    /// Temperature-alert brightness relative to the normal glow.
    var overheatGain: Double {
        get { min(2, max(0.5, get(Key.overheatGain, Defaults.overheatGain))) }
        set { if newValue.isFinite { set(min(2, max(0.5, newValue)), Key.overheatGain) } }
    }
    /// Temperature-alert spread relative to the normal glow.
    var overheatScale: Double {
        get { get(Key.overheatScale, Defaults.overheatScale) }
        set { set(Double(newValue), Key.overheatScale) }
    }
    var frameRate: Double {
        get { min(60, max(15, get(Key.frameRate, Defaults.frameRate))) }
        set { set(Double(newValue), Key.frameRate) }
    }

    // MARK: - Behavior
    var hoverDwell: Double {
        get { get(Key.hoverDwell, Defaults.hoverDwell) }
        set { set(Double(newValue), Key.hoverDwell) }
    }
    var previewLevelRaw: Int {
        get { get(Key.previewLevel, Defaults.previewLevel) }
        set { set(newValue, Key.previewLevel) }
    }
    /// Whether initial family presets have been applied; preserve subsequent custom values.
    var powerTuned: Bool {
        get { get(Key.powerTuned, Defaults.powerTuned) }
        set { set(newValue, Key.powerTuned) }
    }
    /// Whether the initial welcome window has been shown.
    var firstRunDone: Bool {
        get { get(Key.firstRunDone, false) }
        set { set(newValue, Key.firstRunDone) }
    }
    /// Temperature warning state, refreshed by the detector at launch.
    var overheatAlarm: Bool {
        get { get(Key.overheatAlarm, false) }
        set { set(newValue, Key.overheatAlarm) }
    }
    /// Disable automatic temperature alerts without disabling the Hot preview.
    var overheatAlertEnabled: Bool {
        get { get(Key.overheatAlertEnabled, true) }
        set { set(newValue, Key.overheatAlertEnabled) }
    }

    /// Which wallpaper the glow is tuned for: 0 follows the system appearance, 1 is a bright wallpaper, 2 a dark one.
    var glowWallpaper: Int {
        get { min(2, max(0, get(Key.glowWallpaper, 0))) }
        set { set(newValue, Key.glowWallpaper) }
    }

    /// Whether the menu bar icon, a keyboard- and VoiceOver-reachable way to the controls, is shown.
    var menuBarIcon: Bool {
        get { get(Key.menuBarIcon, true) }
        set { set(newValue, Key.menuBarIcon) }
    }

    var preview: PreviewLevel { PreviewLevel(rawValue: previewLevelRaw) ?? .auto }

    /// Apply the new visual defaults without touching power thresholds or behavior.
    func resetAppearance() {
        ambientGlow = true
        glowWallpaper = 0
        glowScale = Defaults.glowScale
        glowIntensity = Defaults.glowIntensity
        mediumAlpha = Defaults.mediumAlpha
        pulseHz = Defaults.pulseHz
        hdrFactor = Defaults.hdrFactor
        overheatGain = Defaults.overheatGain
        overheatScale = Defaults.overheatScale
        frameRate = Defaults.frameRate
    }

    func resetAll() {
        mediumWatts = Defaults.mediumWatts
        highWatts = Defaults.highWatts
        holdOnSeconds = Defaults.holdOnSeconds
        hysteresisWatts = Defaults.hysteresisWatts
        sampleInterval = Defaults.sampleInterval
        resetAppearance()
        hoverDwell = Defaults.hoverDwell
        previewLevelRaw = Defaults.previewLevel
        powerTuned = Defaults.powerTuned
    }
}

