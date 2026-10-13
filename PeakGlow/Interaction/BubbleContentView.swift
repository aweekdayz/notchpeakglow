import AppKit
import SwiftUI

/// A compact native control surface. SwiftUI owns the glass; AppKit owns the window.
struct BubbleContentView: View {
  var onClose: () -> Void
  private let app = AppState.shared
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Label("PeakGlow", systemImage: "waveform.path")
          .font(.system(size: 13, weight: .semibold))
        Spacer()
        Button { NSApp.terminate(nil) } label: {
          Label("Quit", systemImage: "power")
        }
          .labelStyle(.iconOnly)
          .buttonStyle(.glass)
          .buttonBorderShape(.circle)
          .controlSize(.small)
          .help("Quit PeakGlow")
          .accessibilityLabel("Quit PeakGlow")
      }

      .frame(height: 28)

      BubblePowerView(app: app, power: app.power)
        .frame(height: 72)

      GlowModeControl(app: app)
        .frame(height: 48)

      BubbleFooter(app: app, onClose: onClose)
        .frame(height: 28)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .padding(20)
    .frame(width: 328, height: 258)
    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24))
    // This utility surface is interactive even when the foreground app stays active.
    .environment(\.appearsActive, true)
  }
}

/// Keep streaming data outside the menu and segmented-control view identity.
private struct BubblePowerView: View {
  @ObservedObject var app: AppState
  @ObservedObject var power: PowerReadingState
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var status: String {
    switch app.preview {
    case .low: return "Glow off"
    case .medium: return "Soft preview"
    case .high: return "Boost preview"
    case .overheat: return "Warm preview"
    case .auto: break
    }
    if app.gamepadConnected { return "Glow paused" }
    if app.overheatAlarm { return "Temperature elevated" }
    if power.reading.availability != .current { return "Load unavailable" }
    switch app.effectiveLevel {
    case .low: return "Low load"
    case .medium: return "Moderate load"
    case .high: return "High load"
    }
  }

  private var powerText: String {
    power.reading.availability == .current ? String(format: "%.1f", power.reading.watts) : "—"
  }

  private var powerDescription: String {
    switch power.reading.availability {
    case .waiting: return "Waiting for power data"
    case .current: return "System power"
    case .unavailable: return "Power data unavailable"
    }
  }

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      VStack(alignment: .leading, spacing: 5) {
        Label(status, systemImage: app.overheatAlarm ? "thermometer.high" : "circle.fill")
          .font(.callout)
          .lineLimit(2)
          .frame(maxWidth: .infinity, alignment: .leading)
          .frame(height: 34, alignment: .leading)
          .foregroundStyle(app.overheatAlarm ? Color.orange : Color.secondary)
        Text(powerDescription)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(2)
          .frame(maxWidth: .infinity, alignment: .leading)
          .frame(height: 28, alignment: .topLeading)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      HStack(alignment: .firstTextBaseline, spacing: 4) {
        Text(powerText)
          .font(.system(size: 30, weight: .medium))
          .monospacedDigit()
          .contentTransition(.numericText())
          .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: power.reading.watts)
        Text("W")
          .font(.callout)
          .foregroundStyle(.secondary)
      }
      .frame(width: 100, alignment: .trailing)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("System power")
      .accessibilityValue(
        power.reading.availability == .current ? "\(powerText) watts" : powerDescription)
    }

  }
}

/// The native macOS mode selector updates independently of the static panel shell.
private struct GlowModeControl: View {
  @ObservedObject var app: AppState
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Glow")
        .font(.caption)
        .foregroundStyle(.secondary)
      NativeGlowSelector(selection: $app.preview)
        .frame(maxWidth: .infinity)

    }

  }
}

private struct BubbleFooter: View {
  @ObservedObject var app: AppState
  var onClose: () -> Void
  var body: some View {

    HStack {
      Text(
        app.preview == .auto
          ? (app.gamepadConnected ? "Game controller connected" : "Adapts to system load")
          : "Choose Auto to resume"
      )
      .font(.caption)
      .foregroundStyle(.secondary)
      .lineLimit(1)
      .frame(maxWidth: .infinity, alignment: .leading)
      Button {
        SettingsWindowController.shared.show()
        onClose()
      } label: {
        Image(systemName: "gearshape").frame(width: 28, height: 28)
      }
      .buttonStyle(.borderless)
      .help("Settings…")
      .accessibilityLabel("Open Settings")
    }

  }
}

/// Keep the native tabs-style selector in SwiftUI's active-appearance environment.
private struct NativeGlowSelector: View {
  @Binding var selection: PreviewLevel
  private static let modes: [PreviewLevel] = [.auto, .low, .medium, .high, .overheat]

  var body: some View {
    Picker("Glow mode", selection: $selection) {
      ForEach(Self.modes, id: \.self) { mode in
        Text(mode.label).tag(mode)
      }
    }
    .pickerStyle(.tabs)
    .labelsHidden()
    .controlSize(.regular)
    .frame(maxWidth: .infinity)
    .environment(\.appearsActive, true)
    .help("Choose Auto to follow system load, or preview a glow mode")
    .accessibilityLabel("Glow mode")
  }
}
