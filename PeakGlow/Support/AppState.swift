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
    @Published var powerAvailability: PowerAvailability = .waiting
    @Published var gamepadConnected = false
    @Published var watts: Double = 0

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
        watts = latestWatts
        if latestPowerAvailability == .current,
           let lastPowerSample,
           Date().timeIntervalSince(lastPowerSample) > max(2, AppSettings.shared.sampleInterval * 3) {
            powerAvailability = .unavailable
        } else {
            powerAvailability = latestPowerAvailability
        }
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

