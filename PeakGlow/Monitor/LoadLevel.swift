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

/// 带滞回 + 保持时间的分级状态机
final class LoadLevelStateMachine {
    private(set) var level: LoadLevel = .low
    var onLevelChange: ((LoadLevel) -> Void)?

    private var candidate: LoadLevel?
    private var candidateSince: Date?

    func reset() {
        candidate = nil
        candidateSince = nil
        level = .low
    }

    /// Missing data must not count toward a continuous transition dwell.
    func discardPendingTransition() {
        candidate = nil
        candidateSince = nil
    }

    /// - Parameter watts: 滑动平均整机功率（W）
    func update(watts: Double, settings: AppSettings = .shared) {
        let medium = settings.mediumWatts
        let high = settings.highWatts
        let hyst = settings.hysteresisWatts
        let holdOn = settings.holdOnSeconds
        let holdOff = max(1.0, settings.holdOnSeconds + 2.0)

        // 计算目标档位（进入用原阈值，维持允许低 hyst —— 滞回）
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

