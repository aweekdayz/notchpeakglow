import SwiftUI

/// The Battery page of Settings: the charge, the battery's health and the power flowing in or out.
/// It takes the reading as a value, so it can be drawn from any snapshot.
struct BatterySettingsContent: View {
    let snapshot: BatterySnapshot?

    @ViewBuilder var body: some View {
        if let b = snapshot {
            Section {
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(b.percent)%")
                            .font(.system(size: 34, weight: .semibold, design: .rounded))
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
                    BatteryGraphic(level: Double(b.percent) / 100, charging: b.isChargingNow, tint: Self.batteryTint(b))
                        .frame(width: 84, height: 40)
                        .accessibilityHidden(true)
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
                                 fraction: Double(cycles) / Double(limit), tint: .accentColor)
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
        } else {
            Section {
                Text("This Mac has no battery.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Green while charging, red when low on battery, otherwise the standard color.
    static func batteryTint(_ b: BatterySnapshot) -> Color {
        if b.isChargingNow { return .green }
        if !b.externalConnected && b.percent <= 20 { return .red }
        return .primary
    }
}

/// A title and value with a thin bar underneath.
private struct MeterRow: View {
    let title: String
    let value: String
    let fraction: Double
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(value)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.22))
                    Capsule().fill(tint)
                        .frame(width: max(6, geo.size.width * min(max(fraction, 0), 1)))
                }
            }
            .frame(height: 6)
            .accessibilityHidden(true)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }
}

/// A battery drawn to fill with the charge, with a bolt over it while charging. Everything scales with the height.
struct BatteryGraphic: View {
    let level: Double
    let charging: Bool
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let line = max(1.5, h * 0.09)
            let corner = h * 0.30
            let inset = max(1.8, h * 0.13)
            let nubWidth = max(2.2, h * 0.14)
            let gap = max(0.8, h * 0.05)
            let bodyWidth = geo.size.width - nubWidth - gap
            HStack(spacing: gap) {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.6), lineWidth: line)
                    RoundedRectangle(cornerRadius: max(1, corner - inset * 0.6), style: .continuous)
                        .fill(tint)
                        .frame(width: max(h * 0.25, (bodyWidth - inset * 2) * min(max(level, 0), 1)))
                        .padding(inset)
                    if charging {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: h * 0.55, weight: .bold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.4), radius: max(0.8, h * 0.04))
                            .frame(width: bodyWidth)
                    }
                }
                .frame(width: bodyWidth)
                UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0,
                                       bottomTrailingRadius: nubWidth, topTrailingRadius: nubWidth)
                    .fill(Color.secondary.opacity(0.6))
                    .frame(width: nubWidth, height: h * 0.38)
            }
        }
    }
}
