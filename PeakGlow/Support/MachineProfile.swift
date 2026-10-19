import IOKit
import Foundation
import AppKit

/// Detect the MacBook family and suggest initial power thresholds.
/// Presets are not calibrated or verified for every chip and core configuration.
@MainActor struct MachineProfile {
    enum Family: String {
        case air, pro14, pro16, unknown
    }

    let family: Family
    let productName: String
    let chipName: String
    let coreCount: Int
    /// Suggested full-glow threshold in watts.
    let suggestedMediumWatts: Double
    /// Suggested Boost threshold in watts.
    let suggestedHighWatts: Double
    /// Cache system metadata once per process.
    static let current: MachineProfile = detect()

    static func detect() -> MachineProfile {
        let model = sysctlString("hw.model") ?? "unknown"
        let chip = sysctlString("machdep.cpu.brand_string") ?? "Apple Silicon"
        let cores = sysctlInt("hw.physicalcpu")

        var product = model
        if let name = ioProductName(), !name.isEmpty {
            product = name
        }

        let family = classify(productName: product, model: model,
                              displayWidthMM: builtInDisplayWidthMM())

        // Family presets are starting points, not per-chip power calibrations.
        let medium: Double = family == .air ? 13 : 30
        let high: Double = family == .air ? 19 : 55

        return MachineProfile(
            family: family,
            productName: product,
            chipName: chip,
            coreCount: cores,
            suggestedMediumWatts: medium,
            suggestedHighWatts: high)
    }

    /// Compact device description for Settings.
    var summary: String {
        "\(productName) · \(chipName) \(coreCount) cores"
    }

    /// Prefer product names and legacy family identifiers. Physical display width
    /// avoids misclassifying a 16-inch Pro when its scaled resolution changes.
    static func classify(productName: String, model: String, displayWidthMM: Double?) -> Family {
        let name = (productName + " " + model).lowercased()
            .filter { !$0.isWhitespace }
        if name.contains("macbookair") { return .air }
        guard name.contains("macbookpro") else { return .unknown }
        if name.contains("16-inch") || name.contains("16inch") || name.contains("16\"") { return .pro16 }
        if let displayWidthMM, displayWidthMM > 330 { return .pro16 }
        return .pro14
    }

    private static func builtInDisplayWidthMM() -> Double? {
        guard let screen = NotchedScreenFinder.find(),
              let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
        let width = CGDisplayScreenSize(CGDirectDisplayID(number.uint32Value)).width
        return width > 0 ? Double(width) : nil
    }

    // MARK: - System metadata


    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buf = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return nil }
        return String(decoding: buf.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func sysctlInt(_ name: String) -> Int {
        var v: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &v, &size, nil, 0) == 0 else { return 0 }
        return Int(v)
    }

    private static func ioProductName() -> String? {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        guard service != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(service) }
        guard let value = IORegistryEntrySearchCFProperty(
            service, kIOServicePlane, "product-name" as CFString,
            kCFAllocatorDefault, IOOptionBits(kIORegistryIterateRecursively)
        ) else { return nil }
        if let name = value as? String {
            return name.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let data = value as? Data else { return nil }
        return String(data: data, encoding: .utf8)?
            .replacingOccurrences(of: "\0", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}



/// A plain-text summary of this Mac and PeakGlow's sensors for bug reports.
/// It contains no serial number, user name, file path or other personal data.
@MainActor enum Diagnostics {
    static func report() -> String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = info?["CFBundleVersion"] as? String ?? "unknown"
        let profile = MachineProfile.current
        let settings = AppSettings.shared
        let state = AppState.shared

        state.refreshPower()
        let reading = state.power.reading
        let power: String
        switch reading.availability {
        case .current: power = String(format: "available (%.1f W)", reading.watts)
        case .waiting: power = "waiting for the first reading"
        case .unavailable: power = "unavailable"
        }
        let temperature: String
        if let t = ThermalSMC.shared.maxTPTemp() {
            temperature = String(format: "available (%.0f C)", t)
        } else {
            temperature = "unavailable"
        }
        let thermalState: String
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: thermalState = "nominal"
        case .fair: thermalState = "fair"
        case .serious: thermalState = "serious"
        case .critical: thermalState = "critical"
        @unknown default: thermalState = "unknown"
        }

        let batteryLine: String
        if let b = state.battery.snapshot {
            var parts = ["\(b.percent)%", b.statusText.lowercased()]
            if let h = b.healthPercent { parts.append("maximum capacity \(h)%") }
            if let c = b.cycleCount { parts.append("\(c) cycles") }
            if let w = b.adapterWatts, b.externalConnected { parts.append("charger \(w) W") }
            if b.externalConnected, !b.isCharging, let r = b.notChargingReason, r != 0 { parts.append("not-charging reason \(r)") }
            batteryLine = parts.joined(separator: ", ")
        } else {
            batteryLine = "none"
        }
        return [
            "PeakGlow \(version) (\(build))",
            "macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "Model: \(profile.productName)",
            "Chip: \(profile.chipName), \(profile.coreCount) cores",
            "Family: \(profile.family.rawValue)",
            "Notch display: \(NotchedScreenFinder.find() != nil ? "available" : "unavailable")",
            "Power sensor: \(power)",
            "Temperature sensor: \(temperature)",
            "Battery: \(batteryLine)",
            "System thermal state: \(thermalState)",
            "Thresholds: \(Int(settings.mediumWatts)) W / \(Int(settings.highWatts)) W",
            "Glow mode: \(settings.preview.label)",
            "Menu bar icon: \(settings.menuBarIcon ? "on" : "off")",
            "Wallpaper setting: \(["automatic", "light", "dark"][settings.glowWallpaper]) (system appearance: \(NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua ? "light" : "dark"))",
        ].joined(separator: "\n")
    }
}
