import SwiftUI

/// The battery's symbol and color, from the system's own battery symbols. Those come in quarters, so
/// the number beside the symbol gives the exact charge. While charging the symbol is the green battery
/// with a bolt; on battery it is red at 20% or less.
enum BatterySymbol {
    /// See `ChargeBatteryGlyph` for the charging look.
    static func quarter(_ percent: Int) -> String {
        switch percent {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    static func tint(_ b: BatterySnapshot) -> Color {
        if b.isChargingNow || (b.externalConnected && b.fullyCharged) { return .green }
        if !b.externalConnected && b.percent <= 20 { return .red }
        return .primary
    }
}

/// The system battery symbol, sized by a text style.
struct BatterySymbolView: View {
    let snapshot: BatterySnapshot
    var font: Font = .body

    var body: some View {
        ChargeBatteryGlyph(percent: snapshot.percent, charging: snapshot.isChargingNow,
                           tint: BatterySymbol.tint(snapshot), font: font)
    }
}

/// The battery wherever the app shows one, made only of unchanged system symbols whose size follows a
/// text style. Not charging, it is the system's battery for the level. Charging, it is that battery in
/// green with the system's `bolt.fill` on it, which is how the system's own battery looks; the system draws
/// a bolt battery only when it is full, so the two symbols are combined to keep the level visible.
struct ChargeBatteryGlyph: View {
    let percent: Int
    let charging: Bool
    let tint: Color
    var font: Font = .body

    var body: some View {
        Image(systemName: BatterySymbol.quarter(percent))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(charging ? Color.green : tint)
            .font(font)
            .overlay {
                if charging && percent < 100 {
                    // Small enough to sit inside the body of the battery, as on iOS.
                    Image(systemName: "bolt.fill")
                        .font(font.weight(.semibold))
                        .imageScale(.small)
                        .scaleEffect(0.62)
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.35), radius: 0.6)
                        .padding(.trailing, 2)
                }
            }
            .accessibilityHidden(true)
    }
}

/// The Battery page of Settings: the charge, the battery's health, the power flowing in or out and how
/// charging shows in the glow. It takes the reading as a value, so it can be drawn from any snapshot.
struct BatterySettingsContent: View {
    let snapshot: BatterySnapshot?
    @Binding var chargingGlow: Bool
    @Binding var chargeIsland: Bool

    @ViewBuilder var body: some View {
        if let b = snapshot {
            Section {
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(b.percent)%")
                            .font(.largeTitle.weight(.semibold))
                            .monospacedDigit()
                        Text(b.statusText)
                            .foregroundStyle(.secondary)
                        if let time = b.timeText {
                            Text(time)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    BatterySymbolView(snapshot: b, font: .largeTitle)
                        .imageScale(.large)
                }
                .padding(.vertical, 6)
                .accessibilityElement(children: .combine)
            } header: {
                Text("Charge")
            }
            Section {
                if let health = b.healthPercent {
                    MeterRow(title: "Maximum capacity", value: "\(health)%", fraction: Double(health) / 100,
                             tint: health < 80 ? .orange : .green)
                }
                if let design = b.designCapacity, let maximum = b.maximumCapacity {
                    LabeledContent("Capacity", value: "\(maximum) of \(design) mAh")
                }
                if let cycles = b.cycleCount {
                    if let limit = b.designCycleCount, limit > 0 {
                        MeterRow(title: "Cycle count", value: "\(cycles) of \(limit)",
                                 fraction: Double(cycles) / Double(limit), tint: .gray)
                    } else {
                        LabeledContent("Cycle count", value: "\(cycles)")
                    }
                }
                if let temperature = b.temperature {
                    LabeledContent("Temperature", value: String(format: "%.1f °C", temperature))
                }
            } header: {
                Text("Health")
            } footer: {
                if let health = b.healthPercent, health < 80 {
                    SettingsNote("macOS may recommend service for a battery below 80% of its design capacity.")
                }
            }
            Section {
                LabeledContent("Power adapter", value: b.externalConnected ? (b.adapterWatts.map { "\($0) W" } ?? "Connected") : "Not connected")
                if let watts = b.batteryWatts, abs(watts) >= 0.1 {
                    LabeledContent(watts > 0 ? "Charging power" : "Battery power", value: String(format: "%.1f W", abs(watts)))
                }
                if let current = b.current, abs(current) >= 0.01 {
                    LabeledContent("Current", value: String(format: "%.0f mA", abs(current) * 1000))
                }
                if let voltage = b.voltage {
                    LabeledContent("Voltage", value: String(format: "%.2f V", voltage))
                }
            } header: {
                Text("Power")
            } footer: {
                if b.externalConnected && !b.isCharging && !b.fullyCharged && b.percent < 100 {
                    SettingsNote("The Mac is plugged in but not charging. macOS may be holding the charge, for example at 80% to protect the battery.")
                }
            }
            Section {
                Toggle("Show charging in the glow", isOn: $chargingGlow)
                Toggle("Show the charge when the charger is connected", isOn: $chargeIsland)
                    .disabled(!chargingGlow)
            } header: {
                Text("Charging")
            }
        } else {
            Section {
                Text("This Mac has no battery.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// A measure as one row: the label on the left, then a thin system progress bar and the value.
private struct MeterRow: View {
    let title: String
    let value: String
    let fraction: Double
    let tint: Color

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 12) {
                ProgressView(value: min(max(fraction, 0), 1))
                    .progressViewStyle(.linear)
                    .tint(tint)
                    .frame(width: 150)
                Text(value)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 84, alignment: .trailing)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }
}
