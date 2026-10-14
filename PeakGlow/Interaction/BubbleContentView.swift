import AppKit
import SwiftUI

/// Drives the content's reveal: false while the island is in the notch, true once it opens.
/// The island's black shell and its glow are drawn by the Metal renderer; this window only
/// holds the controls, so it never animates its own size or layout.
@MainActor final class IslandMotion: ObservableObject {
  @Published var expanded = false
}

/// Shared geometry. The panel window is the expanded island; its top is the top of the screen.
enum IslandMetrics {
  static let width: CGFloat = 384
  /// Height below the notch, where the controls sit.
  static let contentHeight: CGFloat = 210
  static let expandedCornerRadius: CGFloat = 24
}

/// The glow's own color ramp laid out by power, shared by the panel and Settings meters.
@MainActor enum PowerRamp {
  static func gradient(medium: Double, high: Double) -> Gradient {
    let colors: [Color] = [
      Color(red: 0.18, green: 0.36, blue: 1.00), Color(red: 0.10, green: 0.78, blue: 1.00),
      Color(red: 0.22, green: 0.92, blue: 0.46), Color(red: 0.70, green: 0.93, blue: 0.26),
      Color(red: 0.99, green: 0.88, blue: 0.28)]
    let maximum = max(high * 1.4, 1)
    let stops = colors.enumerated().map { index, color -> Gradient.Stop in
      let watts = GlowRenderer.watts(forPowerFraction: Double(index) / 4, medium: medium, high: high)
      return Gradient.Stop(color: color, location: min(max(watts / maximum, 0), 1))
    }
    return Gradient(stops: stops)
  }
}

/// A read-only meter. The whole color scale stays visible at low brightness and the part up to the
/// current power is lit, with ticks at the two thresholds. It has no thumb, so it does not look adjustable.
/// The lit part follows the reading smoothly, fills up when `revealed` turns on, and a faint edge marks
/// where it ends. With Reduce Motion on nothing is animated.
struct PowerMeter: View {
    let watts: Double
    let medium: Double
    let high: Double
    let maximum: Double
    let gradient: Gradient
    /// False draws the meter empty; turning it on fills it, which the panel uses as it opens.
    var revealed: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let barHeight: CGFloat = 8
    private let edgeWidth: CGFloat = 14

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                let width = geo.size.width
                let lit = revealed ? width * min(max(watts / max(maximum, 1), 0), 1) : 0
                let fill = LinearGradient(gradient: gradient, startPoint: .leading, endPoint: .trailing)
                ZStack(alignment: .leading) {
                    Rectangle().fill(fill).opacity(0.28)
                    Rectangle().fill(fill)
                        .mask(alignment: .leading) { Rectangle().frame(width: lit) }
                    // A soft highlight on the leading edge of the lit part.
                    LinearGradient(colors: [.white.opacity(0), .white.opacity(0.45)], startPoint: .leading, endPoint: .trailing)
                        .frame(width: edgeWidth)
                        .offset(x: lit - edgeWidth)
                        .opacity(min(lit / edgeWidth, 1))
                }
                .clipShape(Capsule())
                .overlay(alignment: .leading) {
                    ZStack(alignment: .leading) {
                        tick(at: width * medium / max(maximum, 1))
                        tick(at: width * high / max(maximum, 1))
                    }
                }
                // Readings retarget a running animation, so the motion stays continuous.
                .animation(reduceMotion ? nil : .smooth(duration: 0.6), value: watts)
                // Opening fills the meter after the shell has started to open; closing empties it quickly.
                .animation(reduceMotion ? nil : (revealed ? .smooth(duration: 0.8).delay(0.24) : .easeIn(duration: 0.12)), value: revealed)
                .frame(height: barHeight)
            }
            .frame(height: barHeight)
            GeometryReader { geo in
                let width = geo.size.width
                // The lower threshold ends at its tick and the higher one starts at it, so they never overlap.
                let mediumX = max(width * medium / max(maximum, 1), 44)
                let highX = min(width * high / max(maximum, 1), width - 44)
                Text("\(Int(medium)) W")
                    .position(x: mediumX - 18, y: 7)
                Text("\(Int(high)) W")
                    .position(x: highX + 18, y: 7)
            }
            .frame(height: 14)
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
        .allowsHitTesting(false)
    }

    private func tick(at x: CGFloat) -> some View {
        Rectangle()
            .fill(Color.primary.opacity(0.55))
            .frame(width: 1.5, height: barHeight + 6)
            .offset(x: x - 0.75)
    }
}

/// The controls laid out for the island. The top band beside the notch carries the name and the
/// live power; the controls sit below it. The black shell behind them is drawn by the renderer.
struct BubbleContentView: View {
  var onClose: () -> Void
  @ObservedObject var motion: IslandMotion
  let notchSize: CGSize
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @ObservedObject private var power = AppState.shared.power
  @ObservedObject private var settings = AppSettings.shared
  private let app = AppState.shared

  var body: some View {
    let wing = (IslandMetrics.width - notchSize.width) / 2
    VStack(spacing: 0) {
      HStack(spacing: 0) {
        Label("PeakGlow", systemImage: "waveform.path")
          .font(.caption.weight(.semibold))
          .lineLimit(1)
          .minimumScaleFactor(0.8)
          .padding(.leading, 12)
          .frame(width: wing, alignment: .leading)
        Spacer(minLength: 0)
        HStack(alignment: .firstTextBaseline, spacing: 3) {
          Text(powerText)
            .font(.system(.callout, design: .rounded).weight(.semibold))
            .monospacedDigit()
            .contentTransition(.numericText())
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: power.reading.watts)
          Text("W")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.trailing, 14)
        .frame(width: wing, alignment: .trailing)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("System power")
        .accessibilityValue(power.reading.availability == .current ? "\(powerText) watts" : "unavailable")
      }
      .frame(height: notchSize.height)
      .islandReveal(motion.expanded, delay: 0.10, reduceMotion: reduceMotion)

      VStack(alignment: .leading, spacing: 12) {
        BubbleStatusView(app: app, power: power)
          .frame(height: 40)
          .islandReveal(motion.expanded, delay: 0.16, reduceMotion: reduceMotion)
        PowerMeter(watts: meterWatts, medium: settings.mediumWatts, high: settings.highWatts,
                   maximum: max(settings.highWatts * 1.4, 1),
                   gradient: PowerRamp.gradient(medium: settings.mediumWatts, high: settings.highWatts),
                   revealed: motion.expanded)
          .frame(height: 28)
          .accessibilityHidden(true)
          .islandReveal(motion.expanded, delay: 0.20, reduceMotion: reduceMotion)
        GlowModeControl(app: app)
          .frame(height: 48)
          .islandReveal(motion.expanded, delay: 0.24, reduceMotion: reduceMotion)
        BubbleFooter(app: app, onClose: onClose)
          .frame(height: 28)
          .islandReveal(motion.expanded, delay: 0.28, reduceMotion: reduceMotion)
      }
      .padding(.top, 14)
      .padding(.horizontal, 20)
      .padding(.bottom, 16)
    }
    .frame(width: IslandMetrics.width, height: notchSize.height + IslandMetrics.contentHeight, alignment: .top)
    // Nearly invisible, so a click on the black shell is not passed to the window behind it.
    .background(Color.black.opacity(0.01))
    // The island is black, so its content uses the dark appearance.
    .environment(\.colorScheme, .dark)
    // This utility surface is interactive even when the foreground app stays active.
    .environment(\.appearsActive, true)
  }

  private var powerText: String {
    power.reading.availability == .current ? String(format: "%.1f", power.reading.watts) : "—"
  }
  private var meterWatts: Double { power.reading.availability == .current ? power.reading.watts : 0 }
}

private extension View {
  /// Layers settle in turn after the shell has started to open and leave quickly. Opacity and
  /// offset are animated by SwiftUI without re-evaluating the content each frame.
  func islandReveal(_ expanded: Bool, delay: Double, reduceMotion: Bool) -> some View {
    self
      .opacity(expanded ? 1 : 0)
      .offset(y: (expanded || reduceMotion) ? 0 : 6)
      .animation(
        reduceMotion ? .easeInOut(duration: 0.16)
          : (expanded ? .easeOut(duration: 0.26).delay(delay) : .easeIn(duration: 0.10)),
        value: expanded)
  }
}

/// What the glow is doing, and where the reading stands.
private struct BubbleStatusView: View {
  @ObservedObject var app: AppState
  @ObservedObject var power: PowerReadingState

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

  private var powerDescription: String {
    switch power.reading.availability {
    case .waiting: return "Waiting for power data"
    case .current: return "System power"
    case .unavailable: return "Power data unavailable"
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Label(status, systemImage: app.overheatAlarm ? "thermometer.high" : "circle.fill")
        .font(.callout)
        .lineLimit(1)
        .foregroundStyle(app.overheatAlarm ? Color.orange : Color.secondary)
      Text(powerDescription)
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
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
    HStack(spacing: 8) {
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
  }
}

/// A system segmented control, not a drawn replacement. AppKit exposes equal segment
/// distribution and the macOS 27 tabs role to SwiftUI hosting.
private struct NativeGlowSelector: NSViewRepresentable {
  @Binding var selection: PreviewLevel
  private static let modes: [PreviewLevel] = [.auto, .low, .medium, .high, .overheat]
  private static let labels = ["Auto", "Off", "Soft", "Boost", "Warm"]
  private static let help = [
    "Adapt glow to system load", "Turn glow off", "Preview soft glow",
    "Preview boost glow", "Preview the warm temperature-alert glow",
  ]

  func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }

  func makeNSView(context: Context) -> NSSegmentedControl {
    let control = NSSegmentedControl(
      labels: Self.labels, trackingMode: .selectOne,
      target: context.coordinator, action: #selector(Coordinator.select(_:)))
    control.role = .tabs
    control.segmentStyle = .automatic
    control.borderShape = .capsule
    control.segmentDistribution = .fillEqually
    control.controlSize = .regular
    control.setAccessibilityLabel("Glow mode")
    for index in Self.modes.indices {
      control.setToolTip(Self.help[index], forSegment: index)
    }
    control.selectedSegment = Self.modes.firstIndex(of: selection) ?? 0
    return control
  }

  func updateNSView(_ control: NSSegmentedControl, context: Context) {
    context.coordinator.selection = $selection
    let index = Self.modes.firstIndex(of: selection) ?? 0
    // Tracking already set the selected segment. Avoid resetting it during the
    // state publication, which can invalidate native metrics mid-interaction.
    if control.selectedSegment != index { control.selectedSegment = index }
  }

  func sizeThatFits(
    _ proposal: ProposedViewSize, nsView: NSSegmentedControl,
    context: Context
  ) -> CGSize? {
    CGSize(width: proposal.width ?? 288, height: nsView.intrinsicContentSize.height)
  }

  @MainActor final class Coordinator: NSObject {
    var selection: Binding<PreviewLevel>
    init(selection: Binding<PreviewLevel>) { self.selection = selection }
    @objc func select(_ sender: NSSegmentedControl) {
      guard NativeGlowSelector.modes.indices.contains(sender.selectedSegment) else { return }
      let mode = NativeGlowSelector.modes[sender.selectedSegment]
      if selection.wrappedValue != mode { selection.wrappedValue = mode }
    }
  }
}
