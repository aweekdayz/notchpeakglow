import AppKit
import SwiftUI

/// Drives the island: false is the notch's own shape, true is the full panel.
@MainActor final class IslandMotion: ObservableObject {
  @Published var expanded = false
}

/// Shared geometry. The window is fixed; only the shape inside it changes size.
enum IslandMetrics {
  static let width: CGFloat = 328
  static let contentHeight: CGFloat = 258
  /// Room for the spring to overshoot without clipping at the window edge.
  static let margin: CGFloat = 14
  static let expandedCornerRadius: CGFloat = 24
  /// The hardware notch's lower corner radius; the glow shader uses the same proportion.
  static func notchCornerRadius(height: CGFloat) -> CGFloat { height * 0.28 }
}

/// A compact control surface that grows out of the notch like an island.
/// SwiftUI owns the motion and the controls; AppKit owns the fixed window.
struct BubbleContentView: View {
  var onClose: () -> Void
  @ObservedObject var motion: IslandMotion
  let notchSize: CGSize
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    IslandSurface(progress: motion.expanded ? 1 : 0, notchSize: notchSize,
                  reduceMotion: reduceMotion, onClose: onClose)
      .animation(animation, value: motion.expanded)
      // The island is black, so its content uses the dark appearance.
      .environment(\.colorScheme, .dark)
      // This utility surface is interactive even when the foreground app stays active.
      .environment(\.appearsActive, true)
  }

  /// Spring-driven, so reversing mid-motion keeps the current velocity.
  private var animation: Animation {
    if reduceMotion { return .easeInOut(duration: 0.16) }
    return motion.expanded
      ? .spring(response: 0.46, dampingFraction: 0.74)
      : .spring(response: 0.34, dampingFraction: 0.9)
  }
}

/// The island as a pure function of `progress`: 0 is the notch itself, 1 the full panel.
/// With Reduce Motion the shape stays full size and only its opacity changes.
struct IslandSurface: View, @preconcurrency Animatable {
  var progress: CGFloat
  let notchSize: CGSize
  let reduceMotion: Bool
  var onClose: () -> Void
  private let app = AppState.shared

  var animatableData: CGFloat {
    get { progress }
    set { progress = newValue }
  }

  var body: some View {
    let fullWidth = IslandMetrics.width
    let fullHeight = notchSize.height + IslandMetrics.contentHeight
    let shapeProgress: CGFloat = reduceMotion ? 1 : progress
    let width = notchSize.width + (fullWidth - notchSize.width) * shapeProgress
    let height = notchSize.height + (fullHeight - notchSize.height) * shapeProgress
    let notchRadius = IslandMetrics.notchCornerRadius(height: notchSize.height)
    let radius = notchRadius + (IslandMetrics.expandedCornerRadius - notchRadius) * min(max(shapeProgress, 0), 1)
    // The top merges with the screen edge, like the hardware notch; only the lower corners round.
    let shape = UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: radius,
                                       bottomTrailingRadius: radius, topTrailingRadius: 0, style: .continuous)

    ZStack(alignment: .top) {
      Color.black
      content
        .frame(width: fullWidth, height: fullHeight, alignment: .top)
    }
    .frame(width: max(width, 1), height: max(height, 1), alignment: .top)
    .clipShape(shape)
    .overlay(shape.strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5))
    // Hidden at rest so the shape cannot show beside the real notch.
    .opacity(reduceMotion ? min(max(progress, 0), 1) : min(max(progress / 0.06, 0), 1))
    .frame(width: fullWidth + IslandMetrics.margin * 2, height: fullHeight + IslandMetrics.margin, alignment: .top)
  }

  /// Layers settle in turn after the shell has started to open.
  private func reveal(_ from: CGFloat, _ to: CGFloat) -> CGFloat {
    if reduceMotion { return 1 }
    let t = min(max((progress - from) / (to - from), 0), 1)
    return t * t * (3 - 2 * t)
  }

  private func layer<V: View>(_ from: CGFloat, _ to: CGFloat, @ViewBuilder _ view: () -> V) -> some View {
    let r = reveal(from, to)
    return view()
      .opacity(r)
      .offset(y: (1 - r) * 6)
  }

  private var content: some View {
    VStack(alignment: .leading, spacing: 14) {
      layer(0.52, 0.80) {
        HStack {
          Label("PeakGlow", systemImage: "waveform.path")
            .font(.headline.weight(.semibold))
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
      }

      layer(0.58, 0.86) {
        BubblePowerView(app: app, power: app.power)
          .frame(height: 72)
      }

      layer(0.64, 0.92) {
        GlowModeControl(app: app)
          .frame(height: 48)
      }

      layer(0.70, 0.98) {
        BubbleFooter(app: app, onClose: onClose)
          .frame(height: 28)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .padding(.top, notchSize.height + 20)
    .padding([.horizontal, .bottom], 20)
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
          .font(.largeTitle.weight(.medium))
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
