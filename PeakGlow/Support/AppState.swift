import Foundation
import Combine

/// 全局可观察状态（气泡显示用）
final class AppState: ObservableObject {
    static let shared = AppState()

    /// 气泡是否可见：不可见时冻结 @Published 更新，避免 SwiftUI 每秒空转重渲染
    var bubbleVisible = false
    var latestWatts: Double = 0
    private var lastPowerSample: Date?
    enum PowerAvailability { case waiting, current, unavailable }
    var latestPowerAvailability: PowerAvailability = .waiting
    let power = PowerReadingState()
    @Published var gamepadConnected = false

    func recordPower(_ reading: Double?) {
        if let reading, reading.isFinite, reading > 0 {
            lastPowerSample = Date()
            latestWatts = reading
            latestPowerAvailability = .current
        } else {
            latestPowerAvailability = .unavailable
        }
        if bubbleVisible { refreshPower() }
    }

    func refreshPower() {
        let availability: PowerAvailability
        if latestPowerAvailability == .current,
           let lastPowerSample,
           Date().timeIntervalSince(lastPowerSample) > max(2, AppSettings.shared.sampleInterval * 3) {
            availability = .unavailable
        } else {
            availability = latestPowerAvailability
        }
        // UI shows tenths of a watt; retain full precision for load detection only.
        let displayWatts = (latestWatts * 10).rounded() / 10
        let reading = PowerReadingState.Reading(watts: displayWatts, availability: availability)
        if power.reading != reading { power.reading = reading }
    }
    @Published var effectiveLevel: LoadLevel = .low
    /// 真实过热降频告警激活中（区分于普通高档）
    @Published var overheatAlarm = false
    @Published var preview: PreviewLevel {
        didSet { AppSettings.shared.previewLevelRaw = preview.rawValue }
    }

    private init() {
        preview = AppSettings.shared.preview
    }
}


/// Sampling changes only the measurement subtree, never the native controls.
final class PowerReadingState: ObservableObject {
    struct Reading: Equatable {
        var watts: Double = 0
        var availability: AppState.PowerAvailability = .waiting
    }
    @Published var reading = Reading()
}
