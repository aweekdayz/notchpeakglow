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
        if let current, current > 0.05 { return true }
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

    /// The same in fewer words, for the panel and the menu.
    var shortStatus: String {
        if externalConnected {
            if fullyCharged { return "Full" }
            return isCharging ? "Charging" : "Plugged in"
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

    /// "Charging 35.7 W" while charging. On battery the system power shown beside the charge already is the
    /// discharge, so nothing is added; a Mac that is plugged in and not charging has no power going in.
    var powerText: String? {
        guard let w = chargingWatts else { return nil }
        return String(format: "Charging %.1f W", w)
    }

    /// The estimated time, or, when there is none, what the battery is doing.
    var panelCaption: String {
        if let t = timeText { return t }
        if externalConnected {
            if fullyCharged { return "Fully charged" }
            return isCharging ? "Charging" : "Not charging"
        }
        return "On battery"
    }

    /// "1 h 20 min" for a number of minutes.
    static func duration(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m) min" }
        return m == 0 ? "\(h) h" : "\(h) h \(m) min"
    }

    /// Time until full while charging, or until empty on battery, when the system knows it.
    var timeText: String? {
        if isChargingNow, let m = minutesToFull { return "\(Self.duration(m)) until full" }
        if !externalConnected, let m = minutesToEmpty { return "\(Self.duration(m)) remaining" }
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
            telemetryBatteryWatts: telemetryWatts)
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

    func start() {
        refresh(announce: false)
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

    /// The charging flag can take a few seconds to follow a newly connected charger, so look again soon.
    private func settleReads() {
        for delay in [1.0, 3.0, 6.0, 12.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                MainActor.assumeIsolated { self?.refresh(announce: true) }
            }
        }
    }

    private func scheduleTimer() {
        timer?.invalidate()
        let t = Timer(timeInterval: watching ? 2 : 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh(announce: true) }
        }
        t.tolerance = watching ? 0.5 : 10
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func refresh(announce: Bool) {
        apply(Self.read(), announce: announce)
    }

    /// Takes a reading, publishes it, and reports plugging in or out and reaching full charge.
    func apply(_ new: BatterySnapshot?, announce: Bool) {
        let old = snapshot
        // Just after the charger is pulled, a read can still carry the old connected state for a moment.
        // Hold that back and look again, instead of showing "Charging" for an instant.
        if announce, let new, new.externalConnected, let at = unpluggedAt, Date().timeIntervalSince(at) < 2 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                MainActor.assumeIsolated { self?.refresh(announce: true) }
            }
            return
        }
        if let new, !new.externalConnected, old?.externalConnected == true { unpluggedAt = Date() }
        if new != old { snapshot = new }
        onUpdate?(new)
        guard announce, let old, let new else { return }
        if !old.externalConnected && new.externalConnected {
            onEvent?(.pluggedIn)
            settleReads()
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
