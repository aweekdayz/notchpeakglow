import IOKit
import Foundation

/// Sample the AppleSMC PSTR float sensor in watts.
/// Two-step driver protocol: selector 2, with subcommands in data8.
/// This driver protocol is not a documented public power-measurement API.
@MainActor final class PowerSampler {
    var onSample: ((Double?) -> Void)?
    // Accessed from deinit, which is nonisolated; the timer is only otherwise touched on the main actor.
    nonisolated(unsafe) private var timer: Timer?

    func start(interval: TimeInterval) {
        stop()
        onSample?(readWatts())
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.onSample?(self.readWatts())
            }
        }
        timer.tolerance = min(0.05, interval * 0.1)
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // Preserve the driver-compatible field order and types.
    private struct SMCKeyData {
        typealias SMCBytes = (
            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)

        struct Vers {
            var major: UInt8 = 0
            var minor: UInt8 = 0
            var build: UInt8 = 0
            var reserved: UInt8 = 0
            var release: UInt16 = 0
        }
        struct LimitData {
            var version: UInt16 = 0
            var length: UInt16 = 0
            var cpuPLimit: UInt32 = 0
            var gpuPLimit: UInt32 = 0
            var memPLimit: UInt32 = 0
        }
        struct KeyInfo {
            var dataSize: UInt32 = 0
            var dataType: UInt32 = 0
            var dataAttributes: UInt8 = 0
        }

        var key: UInt32 = 0
        var vers = Vers()
        var pLimitData = LimitData()
        var keyInfo = KeyInfo()
        var padding: UInt16 = 0
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes = SMCBytes(
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    }

    private var conn: io_connect_t = 0
    private var nextOpenAttempt: TimeInterval = 0
    private var keyInfoCache: [UInt32: SMCKeyData.KeyInfo] = [:]

    private static let kernelIndex: UInt8 = 2
    private static let readKeyInfo: UInt8 = 9
    private static let readBytes: UInt8 = 5
    private static let typeFloat: UInt32 = 0x66_6C_74_20  // 'flt '

    /// System power in watts; nil when the sensor is unavailable.
    func readWatts() -> Double? {
        guard openIfNeeded() else { return nil }
        guard let data = readKey("PSTR"), data.count >= 4 else { return nil }

        // Decode the four-byte little-endian float.
        let bits = UInt32(data[0])
            | UInt32(data[1]) << 8
            | UInt32(data[2]) << 16
            | UInt32(data[3]) << 24
        let watts = Float32(bitPattern: bits)
        guard watts.isFinite, watts >= 0, watts < 500 else { return nil }
        return Double(watts)
    }

    // MARK: - Two-step SMC reads

    private func readKey(_ keyStr: String) -> [UInt8]? {
        let key: UInt32 = keyStr.utf8.reduce(0) { $0 << 8 | UInt32($1) }

        var input = SMCKeyData()
        var output = SMCKeyData()

        // Metadata is stable for this connection; only read values each sample.
        input.key = key
        let info: SMCKeyData.KeyInfo
        if let cached = keyInfoCache[key] {
            info = cached
        } else {
            input.data8 = Self.readKeyInfo
            guard call(Self.kernelIndex, input: &input, output: &output) == KERN_SUCCESS,
                  output.result == 0, output.keyInfo.dataSize >= 4,
                  output.keyInfo.dataSize <= 32, output.keyInfo.dataType == Self.typeFloat else { return nil }
            info = output.keyInfo
            keyInfoCache[key] = info
        }

        // Read the current value after obtaining metadata.
        let size = Int(info.dataSize)
        input.keyInfo.dataSize = info.dataSize
        input.data8 = Self.readBytes
        output = SMCKeyData()
        guard call(Self.kernelIndex, input: &input, output: &output) == KERN_SUCCESS,
              output.result == 0 else {
            keyInfoCache.removeValue(forKey: key)
            return nil
        }

        return withUnsafeBytes(of: output.bytes) { raw in
            Array(raw.prefix(size))
        }
    }

    private func call(_ index: UInt8,
                      input: inout SMCKeyData, output: inout SMCKeyData) -> kern_return_t {
        let size = MemoryLayout<SMCKeyData>.stride
        var outSize = size
        let result = withUnsafeMutablePointer(to: &input) { inPtr in
            withUnsafeMutablePointer(to: &output) { outPtr in
                IOConnectCallStructMethod(
                    conn, UInt32(index),
                    inPtr, size,
                    outPtr, &outSize)
            }
        }
        if result != KERN_SUCCESS {
            IOServiceClose(conn)
            conn = 0
            keyInfoCache.removeAll()
            nextOpenAttempt = ProcessInfo.processInfo.systemUptime + 30
        }
        return result == KERN_SUCCESS && outSize != size ? KERN_FAILURE : result
    }

    private func openIfNeeded() -> Bool {
        if conn != 0 { return true }
        let now = ProcessInfo.processInfo.systemUptime
        guard now >= nextOpenAttempt else { return false }
        nextOpenAttempt = now + 30
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != IO_OBJECT_NULL else { return false }
        defer { IOObjectRelease(service) }
        guard IOServiceOpen(service, mach_task_self_, 0, &conn) == KERN_SUCCESS else {
            conn = 0
            return false
        }
        return true
    }

    deinit {
        timer?.invalidate()
        if conn != 0 {
            IOServiceClose(conn)
        }
    }
}

