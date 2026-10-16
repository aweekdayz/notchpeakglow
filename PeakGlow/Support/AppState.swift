import Foundation
import Combine

/// Observable state shared by the controls.
@MainActor final class AppState: ObservableObject {
    static let shared = AppState()

    /// Publish streaming power only while controls are visible.
    var bubbleVisible = false
    /// True while the Settings window is open and shows the live power gauge.
    var settingsVisible = false
    var latestWatts: Double = 0
    private var lastPowerSample: Date?
    /// The readout shows the mean of the last few samples and changes about every second and a half;
    /// the sensor itself is read faster, and raw samples jump around too much to read.
    private var recentWatts: [Double] = []
    private var lastPublish = Date.distantPast
    private static let readoutSamples = 5
    private static let readoutInterval: TimeInterval = 1.5
    enum PowerAvailability { case waiting, current, unavailable }
    var latestPowerAvailability: PowerAvailability = .waiting
    let power = PowerReadingState()
    @Published var gamepadConnected = false

    func recordPower(_ reading: Double?) {
        if let reading, reading.isFinite, reading >= 0 {
            lastPowerSample = Date()
            latestWatts = reading
            recentWatts.append(reading)
            if recentWatts.count > Self.readoutSamples { recentWatts.removeFirst() }
            latestPowerAvailability = .current
        } else {
            latestPowerAvailability = .unavailable
        }
        if bubbleVisible || settingsVisible { refreshPower(throttled: true) }
    }

    /// `throttled` is for the stream of samples; opening the controls or Settings refreshes at once.
    func refreshPower(throttled: Bool = false) {
        let availability: PowerAvailability
        if latestPowerAvailability == .current,
           let lastPowerSample,
           Date().timeIntervalSince(lastPowerSample) > max(2, AppSettings.shared.sampleInterval * 3) {
            availability = .unavailable
        } else {
            availability = latestPowerAvailability
        }
        let now = Date()
        if throttled, availability == power.reading.availability,
           now.timeIntervalSince(lastPublish) < Self.readoutInterval { return }
        // UI shows tenths of a watt; retain full precision for load detection only.
        let mean = recentWatts.isEmpty ? latestWatts : recentWatts.reduce(0, +) / Double(recentWatts.count)
        let displayWatts = (mean * 10).rounded() / 10
        let reading = PowerReadingState.Reading(watts: displayWatts, availability: availability)
        if power.reading != reading { power.reading = reading }
        lastPublish = now
    }
    @Published var effectiveLevel: LoadLevel = .low
    /// Actual temperature warning, independent of the Hot preview.
    @Published var overheatAlarm = false
    @Published var preview: PreviewLevel {
        didSet { AppSettings.shared.previewLevelRaw = preview.rawValue }
    }

    private init() {
        preview = AppSettings.shared.preview
    }
}


/// Sampling changes only the measurement subtree, never the native controls.
@MainActor final class PowerReadingState: ObservableObject {
    struct Reading: Equatable {
        var watts: Double = 0
        var availability: AppState.PowerAvailability = .waiting
    }
    @Published var reading = Reading()
}
