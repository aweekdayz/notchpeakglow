import Foundation
import AppKit
import IOKit

/// Heuristic elevated-temperature detection from sustained temperature plateaus.
///
/// A stable hot sensor reading can suggest thermal pressure.
/// It does not prove that the processor is throttling.
/// Require a continuous dwell; ramping or cooling readings do not qualify.
///
/// Source: maximum available Tp* die-temperature reading.
/// Fallback: the system thermal state becomes critical.
@MainActor final class OverheatDetector {
    var onOverheatChange: ((Bool) -> Void)?

    private(set) var overheat = false

    private struct Params {
        let hotWall: Double       // Temperature plateau boundary in degrees Celsius.
        let band: Double          // Maximum temperature variation within the window.
        let stableSecs: Double    // Required plateau duration.
    }

    private var p: Params!
    private var timer: Timer?
    private let smc = ThermalSMC.shared

    private var win: [(t: TimeInterval, v: Double)] = []
    private var pinSince: Date?
    private var lastSampleAt: Date?

    func start(interval: TimeInterval = 1.0) {
        switch MachineProfile.current.family {
        case .air:
            p = Params(hotWall: 93, band: 3.5, stableSecs: 12)
        case .pro14, .pro16:
            p = Params(hotWall: 94, band: 3.5, stableSecs: 10)
        case .unknown:
            p = Params(hotWall: 95, band: 4.0, stableSecs: 12)
        }
        _ = smc.open()
        update()
        timer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
        // Let the system coalesce this wake-up with others; detection uses real timestamps.
        timer.tolerance = interval * 0.2
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        resetWindow()
    }

    private func update() {
        // Do not evaluate when automatic temperature alerts are disabled.
        guard AppSettings.shared.overheatAlertEnabled else {
            setOverheat(false)
            resetWindow()
            return
        }

        // The system critical state overrides the sensor heuristic.
        if ProcessInfo.processInfo.thermalState == .critical {
            setOverheat(true)
            resetWindow()
            return
        }

        guard MachineProfile.current.family != .unknown,
              let t = smc.maxTPTemp() else {
            // Missing samples cannot establish a continuous temperature plateau.
            resetWindow()
            setOverheat(false)
            return
        }

        // A long gap (for example system sleep) breaks continuity; observe the plateau afresh.
        let sampleDate = Date()
        if let last = lastSampleAt, sampleDate.timeIntervalSince(last) > Self.maxSampleGap {
            resetWindow()
        }
        lastSampleAt = sampleDate

        let now = sampleDate.timeIntervalSince1970
        win.append((now, t))
        while let first = win.first, now - first.t > 15.0 {
            win.removeFirst()
        }

        let vs = win.map(\.v)
        let vmax = vs.max() ?? t
        let vmin = vs.min() ?? t

        // A hot, narrow-range window qualifies as a plateau.
        let pinned = vmax >= p.hotWall && (vmax - vmin) <= p.band

        if pinned {
            if pinSince == nil { pinSince = Date() }
            if Date().timeIntervalSince(pinSince!) >= p.stableSecs {
                setOverheat(true)
            }
        } else {
            pinSince = nil
            // A ramping or cooling window no longer qualifies.
            if overheat { setOverheat(false) }
        }
    }

    /// Longest interval between samples that still counts as continuous observation.
    private static let maxSampleGap: TimeInterval = 5

    private func resetWindow() {
        win.removeAll()
        pinSince = nil
        lastSampleAt = nil
    }

    private func setOverheat(_ on: Bool) {
        guard on != overheat else { return }
        overheat = on
        NSLog("PeakGlow: overheat -> \(on)")
        onOverheatChange?(on)
    }
}

/// Two-step SMC reader for available Tp* die-temperature keys.
@MainActor final class ThermalSMC {
    static let shared = ThermalSMC()
    private var conn: io_connect_t = 0
    private var nextOpenAttempt: TimeInterval = 0
    private var keyInfoCache: [UInt32: KeyData.Info] = [:]
    /// Keys the driver answered with no usable float. Sensor keys differ by model, so asking again every
    /// second only costs time; the set is cleared whenever the connection is rebuilt.
    private var unavailableKeys: Set<UInt32> = []

    private struct KeyData {
        typealias Bytes = (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                           UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                           UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                           UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)
        struct Vers { var a: UInt8 = 0; var b: UInt8 = 0; var c: UInt8 = 0; var d: UInt8 = 0; var rel: UInt16 = 0 }
        struct Limit { var v1: UInt16 = 0; var v2: UInt16 = 0; var v3: UInt32 = 0; var v4: UInt32 = 0; var v5: UInt32 = 0 }
        struct Info { var dataSize: UInt32 = 0; var dataType: UInt32 = 0; var attrs: UInt8 = 0 }
        var key: UInt32 = 0
        var vers = Vers(); var pLimitData = Limit(); var keyInfo = Info()
        var padding: UInt16 = 0; var result: UInt8 = 0; var status: UInt8 = 0
        var data8: UInt8 = 0; var data32: UInt32 = 0
        var bytes: Bytes = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    }

    func open() -> Bool {
        if conn != 0 { return true }
        let now = ProcessInfo.processInfo.systemUptime
        guard now >= nextOpenAttempt else { return false }
        nextOpenAttempt = now + 30
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != IO_OBJECT_NULL else { return false }
        defer { IOObjectRelease(service) }
        guard IOServiceOpen(service, mach_task_self_, 0, &conn) == KERN_SUCCESS else {
            conn = 0
            return false
        }
        return true
    }

    /// Maximum available Tp* temperature; nil when unsupported.
    func maxTPTemp() -> Double? {
        guard open() else { return nil }
        var maxV: Double?
        for key in Self.tpKeys {
            guard conn != 0 else { break }
            if let v = readFloat(key), v > 20, v < 130 {
                maxV = max(maxV ?? 0, v)
            }
        }
        return maxV
    }

    private func readFloat(_ keyName: String) -> Double? {
        let fourcc: UInt32 = keyName.utf8.reduce(0) { $0 << 8 | UInt32($1) }
        if unavailableKeys.contains(fourcc) { return nil }
        var i = KeyData(), o = KeyData()
        i.key = fourcc
        if let info = keyInfoCache[fourcc] {
            i.keyInfo = info
        } else {
            i.data8 = 9 // readKeyInfo
            let status = call(&i, &o)
            guard status == KERN_SUCCESS, o.result == 0,
                  o.keyInfo.dataSize >= 4, o.keyInfo.dataSize <= 32,
                  o.keyInfo.dataType == 0x66_6C_74_20 else {
                // A clean answer that is not a float key means this model does not have it.
                if status == KERN_SUCCESS { unavailableKeys.insert(fourcc) }
                return nil
            }
            i.keyInfo = o.keyInfo
            keyInfoCache[fourcc] = o.keyInfo
        }
        i.data8 = 5                      // readBytes
        o = KeyData()
        guard call(&i, &o) == KERN_SUCCESS, o.result == 0 else {
            keyInfoCache.removeValue(forKey: fourcc)
            return nil
        }
        var v: Double?
        withUnsafeBytes(of: o.bytes) { raw in
            let bits = UInt32(raw[0]) | UInt32(raw[1]) << 8 | UInt32(raw[2]) << 16 | UInt32(raw[3]) << 24
            v = Double(Float32(bitPattern: bits))
        }
        return v
    }

    private func call(_ i: inout KeyData, _ o: inout KeyData) -> kern_return_t {
        let size = MemoryLayout<KeyData>.stride
        var outSize = size
        let result = withUnsafeMutablePointer(to: &i) { ip in
            withUnsafeMutablePointer(to: &o) { op in
                IOConnectCallStructMethod(conn, 2, ip, size, op, &outSize)
            }
        }
        if result != KERN_SUCCESS {
            IOServiceClose(conn)
            conn = 0
            keyInfoCache.removeAll()
            unavailableKeys.removeAll()
            nextOpenAttempt = ProcessInfo.processInfo.systemUptime + 30
        }
        return result == KERN_SUCCESS && outSize != size ? KERN_FAILURE : result
    }

    private static let tpKeys = [
        "Tp00", "Tp04", "Tp08", "Tp0C", "Tp0G", "Tp0K", "Tp0O", "Tp0R",
        "Tp0U", "Tp0X", "Tp0a", "Tp0d", "Tp0g", "Tp0j", "Tp0m", "Tp0p",
        "Tp0u", "Tp0y", "Tp1E", "Tp1I", "Tp1Q", "Tp1U", "Tp1g",
    ]

    deinit { if conn != 0 { IOServiceClose(conn) } }
}
