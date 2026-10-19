import Foundation
import IOKit
import IOKit.ps

/// What the Mac's battery reports, from the `AppleSmartBattery` registry entry, which is where
/// the system's own battery readouts come from. Not every key exists on every Mac or macOS version,
/// so each value is optional.
struct BatterySnapshot: Equatable {
    /// 0...100.
    var percent: Int
    var externalConnected: Bool
    var isCharging: Bool
    var fullyCharged: Bool
    var cycleCount: Int?
    var designCycleCount: Int?
    /// Capacities in mAh.
    var designCapacity: Int?
    var maximumCapacity: Int?
    /// Volts and the battery's own current in amps, positive while charging.
    var voltage: Double?
    var current: Double?
    /// Degrees Celsius.
    var temperature: Double?
    /// The charger's rated power in watts.
    var adapterWatts: Int?
    /// Minutes, nil when the system does not know yet.
    var minutesToFull: Int?
    var minutesToEmpty: Int?
    /// Power into (positive) or out of (negative) the battery as the system's own power telemetry reports it, in watts.
    var telemetryBatteryWatts: Double? = nil
    /// The charger's own reason for not charging (`ChargerData.NotChargingReason`; 0 while charging), for diagnostics.
    var notChargingReason: Int? = nil
    /// The battery's present and full charge in mAh (`AppleRawCurrentCapacity`, `AppleRawMaxCapacity`).
    var rawCurrentCapacity: Int? = nil
    var rawMaxCapacity: Int? = nil
    /// Minutes until full or empty from `TimeEstimator`; nil until the estimate has settled.
    var estimatedMinutes: Int? = nil

    /// The battery's health as the share of its design capacity it can still hold.
    var healthPercent: Int? {
        guard let designCapacity, designCapacity > 0, let maximumCapacity else { return nil }
        return Int((Double(maximumCapacity) / Double(designCapacity) * 100).rounded())
    }

    /// Power flowing into (positive) or out of (negative) the battery, in watts.
    var batteryWatts: Double? {
        guard let voltage, let current else { return nil }
        return voltage * current
    }

    /// True while the battery is taking power in.
    var isChargingNow: Bool { externalConnected && isCharging }

    /// Whether the battery is taking power in, from three signals together. Right after the charger is
    /// connected the registry's flag can lag behind by several seconds, and some chargers never set it,
    /// so the system's own power-source state and the direction of the current count as well. A Mac that is
    /// plugged in and holding its charge, for example at 80%, has none of the three.
    static func charging(flag: Bool, systemSays: Bool?, current: Double?, external: Bool, fullyCharged: Bool) -> Bool {
        guard external, !fullyCharged else { return false }
        if flag || systemSays == true { return true }
        // The direction of the current only decides when the system's power-source API says nothing: while a
        // charger is being pulled the current is still positive for a moment after both sources say "not charging".
        if systemSays == nil, let current, current > 0.05 { return true }
        return false
    }

    /// A few words for what the battery is doing.
    var statusText: String {
        if externalConnected {
            if fullyCharged { return "Fully charged" }
            if isCharging { return "Charging" }
            return "Plugged in, not charging"
        }
        return "On battery"
    }

    /// The same in the words the panel uses, so the menu bar item, its menu and the panel always agree.
    var shortStatus: String {
        if externalConnected {
            if fullyCharged { return "Fully charged" }
            return isCharging ? "Charging" : "Not charging"
        }
        return "On battery"
    }

    /// "Adapter 100 W" while a charger is connected and reports its rating.
    var adapterText: String? {
        guard externalConnected, let adapterWatts else { return nil }
        return "Adapter \(adapterWatts) W"
    }

    /// Power going into the battery while it charges, in watts: the system's telemetry when it has the figure,
    /// otherwise voltage times current. The direction is not trusted while the battery is charging, since the
    /// battery is then taking power in, so only the size counts.
    var chargingWatts: Double? {
        guard isChargingNow else { return nil }
        let w = abs(telemetryBatteryWatts ?? batteryWatts ?? 0)
        return w >= 0.1 ? w : nil
    }

    /// The estimated time, or, when there is none, what the battery is doing.
    var panelCaption: String {
        timeText ?? shortStatus
    }

    /// "1 h 20 min" for a number of minutes.
    static func duration(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m) min" }
        return m == 0 ? "\(h) h" : "\(h) h \(m) min"
    }

    /// Time until full while charging, or until empty on battery, when the system knows it.
    var timeText: String? {
        guard let m = estimatedMinutes else { return nil }
        if isChargingNow { return "\(Self.duration(m)) until full" }
        if !externalConnected { return "\(Self.duration(m)) remaining" }
        return nil
    }

    /// Reads the fields from the registry properties; nil if there is no battery.
    static func parse(_ p: [String: Any]) -> BatterySnapshot? {
        guard (p["BatteryInstalled"] as? Bool) ?? true else { return nil }
        // Capacities and several other values live in the nested `BatteryData` dictionary on newer systems.
        let nested = p["BatteryData"] as? [String: Any] ?? [:]
        func int(_ key: String) -> Int? { ((p[key] ?? nested[key]) as? NSNumber)?.intValue }
        func bool(_ key: String) -> Bool { (p[key] as? Bool) ?? ((p[key] as? NSNumber)?.boolValue ?? false) }
        // A negative current is stored as a large unsigned number.
        func signed(_ key: String) -> Int? {
            guard let n = (p[key] ?? nested[key]) as? NSNumber else { return nil }
            return Int(Int64(bitPattern: n.uint64Value))
        }
        // On Apple silicon `CurrentCapacity` and `MaxCapacity` are percentages; the raw milliamp-hours
        // are in `AppleRawMaxCapacity`, and `NominalChargeCapacity` is the figure the system's own
        // "Maximum Capacity" is based on.
        guard let percent = int("CurrentCapacity") else { return nil }
        let maximum = int("NominalChargeCapacity") ?? int("AppleRawMaxCapacity")
        func minutes(_ key: String) -> Int? {
            guard let m = int(key), m > 0, m < 65535 else { return nil }
            return m
        }
        // Some Macs and macOS versions report no battery temperature at all.
        var temperature: Double?
        if let t = int("Temperature"), t > 0 { temperature = Double(t) / 100 }
        // The system's own power telemetry (the figures System Information shows) is in milliwatts.
        var telemetryWatts: Double?
        if let telemetry = p["PowerTelemetryData"] as? [String: Any], let n = telemetry["BatteryPower"] as? NSNumber {
            telemetryWatts = Double(Int64(bitPattern: n.uint64Value)) / 1000
        }
        var watts: Int?
        if let adapter = p["AdapterDetails"] as? [String: Any], let w = (adapter["Watts"] as? NSNumber)?.intValue, w > 0 {
            watts = w
        }
        return BatterySnapshot(
            percent: min(max(percent, 0), 100),
            externalConnected: bool("ExternalConnected"),
            isCharging: bool("IsCharging"),
            fullyCharged: bool("FullyCharged"),
            cycleCount: int("CycleCount"),
            designCycleCount: int("DesignCycleCount9C"),
            designCapacity: int("DesignCapacity"),
            maximumCapacity: maximum,
            voltage: int("Voltage").map { Double($0) / 1000 },
            current: (signed("InstantAmperage") ?? signed("Amperage")).map { Double($0) / 1000 },
            temperature: temperature,
            adapterWatts: watts,
            minutesToFull: minutes("AvgTimeToFull"),
            minutesToEmpty: minutes("AvgTimeToEmpty"),
            telemetryBatteryWatts: telemetryWatts,
            notChargingReason: ((p["ChargerData"] as? [String: Any])?["NotChargingReason"] as? NSNumber)?.intValue,
            rawCurrentCapacity: int("AppleRawCurrentCapacity"),
            rawMaxCapacity: int("AppleRawMaxCapacity"))
    }
}

/// Time until full or empty from the battery's own figures, instead of the registry's averages, which keep
/// the history of the last charger or load (after replugging, "51 min" became "1 h 20 min" with nothing
/// changed). The power is smoothed over about two minutes; the estimate waits 20 s after charging or
/// discharging begins, so it never shows a number built from the moment of the change.
struct TimeEstimator {
    private var mode: Bool?          // true charging, false discharging, nil neither
    private var since = Date.distantPast
    private var lastSample = Date.distantPast
    private var power: Double?       // smoothed watts, always positive

    /// Fraction of the capacity up to which a charger holds its full current; above it the current tapers.
    static let taperStart = 0.8
    /// Average power of the tapering part relative to the power below it.
    static let taperRatio = 0.4

    mutating func minutes(for b: BatterySnapshot, now: Date = Date()) -> Int? {
        let newMode: Bool? = b.isChargingNow ? true : (!b.externalConnected ? false : nil)
        if newMode != mode { mode = newMode; since = now; power = nil; lastSample = now }
        guard let charging = newMode else { return nil }
        let sample = charging ? b.chargingWatts : abs(b.telemetryBatteryWatts ?? b.batteryWatts ?? 0)
        guard let sample, sample >= 0.5 else { return nil }
        let dt = min(max(now.timeIntervalSince(lastSample), 0), 60)
        lastSample = now
        let alpha = power == nil ? 1 : 1 - exp(-dt / 120)
        power = (power ?? sample) * (1 - alpha) + sample * alpha
        guard now.timeIntervalSince(since) >= 20, let power, let v = b.voltage,
              let current = b.rawCurrentCapacity, let full = b.rawMaxCapacity, full > 0 else { return nil }
        let wattHoursPerMilliampHour = v / 1000
        let hours: Double
        if charging {
            let held = max(0, Double(full) * Self.taperStart - Double(current))
            let tapered = Double(full) - max(Double(current), Double(full) * Self.taperStart)
            hours = held * wattHoursPerMilliampHour / power + tapered * wattHoursPerMilliampHour / (power * Self.taperRatio)
        } else {
            hours = Double(current) * wattHoursPerMilliampHour / power
        }
        let m = hours * 60
        guard m.isFinite, m > 0, m < 24 * 60 else { return nil }
        // Rounded, so a figure that moves by a minute does not flicker.
        return m > 20 ? Int((m / 5).rounded()) * 5 : Int(m.rounded())
    }
}

/// Watches the battery. The system announces plugging in and out and the charge level changing; the
/// details (current, time left) are read again while something on screen shows them.
@MainActor final class BatteryMonitor: ObservableObject {
    enum Event { case pluggedIn, unplugged, fullyCharged }

    @Published private(set) var snapshot: BatterySnapshot?
    /// Called on the main actor when the power source changes in a way worth showing.
    var onEvent: ((Event) -> Void)?
    /// Called after each read.
    var onUpdate: ((BatterySnapshot?) -> Void)?

    private var source: CFRunLoopSource?
    private var timer: Timer?
    private var watching = false
    private var unpluggedAt: Date?
    private var estimator = TimeEstimator()
    /// After a charger is connected (or the app starts with one connected and the battery not yet charging) the
    /// reading is taken every few seconds for a while: on a MacBook Air the charging flag came on 27 s after plugging in.
    private var fastUntil = Date.distantPast

    func start() {
        refresh(announce: false)
        if let s = snapshot, s.externalConnected, !s.isCharging, !s.fullyCharged { fastUntil = Date().addingTimeInterval(60) }
        // The callback has no context object of its own, so it is handed `self` unretained;
        // the monitor lives for the whole run of the app.
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let loop = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<BatteryMonitor>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async { MainActor.assumeIsolated { monitor.refresh(announce: true) } }
        }, context)?.takeRetainedValue() {
            source = loop
            CFRunLoopAddSource(CFRunLoopGetMain(), loop, .commonModes)
        }
        scheduleTimer()
    }

    /// Faster reads while the controls or Settings are showing the current and the time left.
    func setWatching(_ on: Bool) {
        guard on != watching else { return }
        watching = on
        scheduleTimer()
        if on { refresh(announce: false) }
    }

    private func scheduleTimer() {
        timer?.invalidate()
        let fast = Date() < fastUntil
        let t = Timer(timeInterval: watching ? 2 : fast ? 3 : 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.refresh(announce: true)
                if !self.watching, self.timer?.timeInterval == 3, Date() >= self.fastUntil { self.scheduleTimer() }
            }
        }
        t.tolerance = watching ? 0.5 : fast ? 1 : 10
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func refresh(announce: Bool) {
        apply(Self.read(), announce: announce)
    }

    /// Looks every few seconds for the next minute, until the charging flag has caught up with a new charger.
    private func lookOftenForAMinute() {
        fastUntil = Date().addingTimeInterval(60)
        scheduleTimer()
    }

    /// Takes a reading, publishes it, and reports plugging in or out and reaching full charge.
    func apply(_ read: BatterySnapshot?, announce: Bool) {
        let old = snapshot
        var new = read
        // Just after the charger is pulled, a read can still carry the old connected state for a moment.
        // Hold that back and look again, instead of showing "Charging" for an instant.
        if announce, let new, new.externalConnected, let at = unpluggedAt, Date().timeIntervalSince(at) < 2 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                MainActor.assumeIsolated { self?.refresh(announce: true) }
            }
            return
        }
        if let new, !new.externalConnected, old?.externalConnected == true { unpluggedAt = Date() }
        if let b = new { new?.estimatedMinutes = estimator.minutes(for: b) } else { estimator = TimeEstimator() }
        if new != old { snapshot = new }
        onUpdate?(new)
        guard announce, let old, let new else { return }
        if !old.externalConnected && new.externalConnected {
            onEvent?(.pluggedIn)
            lookOftenForAMinute()
        }
        else if old.externalConnected && !new.externalConnected { onEvent?(.unplugged) }
        else if new.externalConnected && !old.fullyCharged && new.fullyCharged { onEvent?(.fullyCharged) }
    }

    /// One read of the registry; nil on a Mac without a battery.
    nonisolated static func read() -> BatterySnapshot? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dictionary = props?.takeRetainedValue() as? [String: Any] else { return nil }
        guard var snapshot = BatterySnapshot.parse(dictionary) else { return nil }
        // At 100% the registry can keep saying "charging" (a trickle) without ever setting FullyCharged, which
        // showed "Charging power 5.0 W" and "25 min until full" at 100%. A full battery on a charger is full.
        if snapshot.percent >= 100, snapshot.externalConnected { snapshot.fullyCharged = true }
        let system = systemState()
        // The registry's ExternalConnected can lag behind a plug or unplug by a moment (and keep its old
        // time and charging flag); the power-source API the system's own battery menu uses is current.
        // Either source saying "unplugged" is enough; a charger counts as connected only when both agree.
        if let ac = system?.ac { snapshot.externalConnected = snapshot.externalConnected && ac }
        snapshot.isCharging = BatterySnapshot.charging(
            flag: snapshot.isCharging, systemSays: system?.charging, current: snapshot.current,
            external: snapshot.externalConnected, fullyCharged: snapshot.fullyCharged)
        return snapshot
    }

    /// The power-source state that `pmset -g batt` and the battery menu use, from the public power-source API.
    nonisolated static func systemState() -> (ac: Bool, charging: Bool)? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in list {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  (description[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType,
                  let state = description[kIOPSPowerSourceStateKey] as? String else { continue }
            return (state == kIOPSACPowerValue, (description[kIOPSIsChargingKey] as? Bool) ?? false)
        }
        return nil
    }
}
