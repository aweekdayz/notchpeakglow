import Foundation

enum LoadLevel: Int {
    case low = 0
    case medium = 1
    case high = 2

    var label: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Soft"
        case .high: return "Boost"
        }
    }
}

/// Load state machine with hysteresis and continuous dwell.
final class LoadLevelStateMachine {
    private(set) var level: LoadLevel = .low
    var onLevelChange: ((LoadLevel) -> Void)?

    private var candidate: LoadLevel?
    private var candidateSince: Date?
    private var lastUpdate: Date?

    func reset() {
        candidate = nil
        candidateSince = nil
        lastUpdate = nil
        level = .low
    }

    /// Missing data must not count toward a continuous transition dwell.
    func discardPendingTransition() {
        candidate = nil
        candidateSince = nil
        lastUpdate = nil
    }

    /// - Parameter watts: Smoothed system power in watts.
    func update(watts: Double, settings: AppSettings = .shared) {
        let medium = settings.mediumWatts
        let high = settings.highWatts
        let hyst = settings.hysteresisWatts
        let holdOn = settings.holdOnSeconds
        let holdOff = max(1.0, settings.holdOnSeconds + 2.0)

        // A gap between samples (for example system sleep) breaks the continuous dwell.
        let now = Date()
        if let last = lastUpdate, now.timeIntervalSince(last) > max(2, settings.sampleInterval * 3) {
            candidate = nil
            candidateSince = nil
        }
        lastUpdate = now

        // Use thresholds to enter a level and a lower hysteresis boundary to leave it.
        let target: LoadLevel
        switch level {
        case .low:
            target = watts >= high ? .high : (watts >= medium ? .medium : .low)
        case .medium:
            target = watts >= high ? .high
                : (watts >= medium - hyst ? .medium : .low)
        case .high:
            target = watts >= high - hyst ? .high
                : (watts >= medium ? .medium : .low)
        }

        let hold = target.rawValue > level.rawValue ? holdOn : holdOff

        if target == level {
            candidate = nil
            candidateSince = nil
            return
        }
        if candidate == target, let since = candidateSince {
            if Date().timeIntervalSince(since) >= hold {
                let old = level
                level = target
                candidate = nil
                candidateSince = nil
                if old != level { onLevelChange?(level) }
            }
        } else {
            candidate = target
            candidateSince = Date()
        }
    }
}

