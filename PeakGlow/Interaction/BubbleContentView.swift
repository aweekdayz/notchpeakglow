import AppKit
import SwiftUI

/// Drives the content's reveal: false while the island is in the notch, true once it opens.
/// The island's black shell and its glow are drawn by the Metal renderer; this window only
/// holds the controls, so it never animates its own size or layout.
@MainActor final class IslandMotion: ObservableObject {
  @Published var expanded = false
  /// True when the renderer cannot draw the shell, so the controls draw a plain black one themselves.
  @Published var fallbackShell = false
}

/// Shared geometry. The panel window is the expanded island; its top is the top of the screen.
enum IslandMetrics {
  static let width: CGFloat = 384
  /// Height below the notch, where the controls sit.
  static let contentHeight: CGFloat = 250
  static let expandedCornerRadius: CGFloat = 24
}

/// The glow's own color ramp laid out by power, shared by the panel and Settings meters.
@MainActor enum PowerRamp {
  /// The glow's color at a given power, for small accents that should match it.
  static func color(watts: Double, medium: Double, high: Double) -> Color {
    let stops: [(Double, Double, Double)] = [
      (0.18, 0.36, 1.00), (0.10, 0.78, 1.00), (0.22, 0.92, 0.46), (0.70, 0.93, 0.26), (0.99, 0.88, 0.28)]
    let t = Double(GlowRenderer.powerFraction(watts: watts, medium: medium, high: high)) * 4
    let i = min(3, max(0, Int(t)))
    let f = min(1, max(0, t - Double(i)))
    let (a, b) = (stops[i], stops[i + 1])
    return Color(red: a.0 + (b.0 - a.0) * f, green: a.1 + (b.1 - a.1) * f, blue: a.2 + (b.2 - a.2) * f)
  }

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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    private let barHeight: CGFloat = 8
    private let edgeWidth: CGFloat = 14

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                let width = geo.size.width
                let lit = width * min(max(watts / max(maximum, 1), 0), 1)
                let fill = LinearGradient(gradient: gradient, startPoint: .leading, endPoint: .trailing)
                ZStack(alignment: .leading) {
                    // With Increase Contrast on, the unlit part is easier to tell from the background.
                    Rectangle().fill(fill).opacity(contrast == .increased ? 0.5 : 0.28)
                    // The lit part is the full-width gradient cut off at `lit`; a plain clip is much cheaper
                    // to animate than a mask.
                    Rectangle().fill(fill)
                        .frame(width: width)
                        .frame(width: lit, alignment: .leading)
                        .clipped()
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
            .fill(Color.primary.opacity(contrast == .increased ? 0.95 : 0.55))
            .frame(width: contrast == .increased ? 2.5 : 1.5, height: barHeight + 6)
            .offset(x: x - (contrast == .increased ? 1.25 : 0.75))
    }
}

/// The controls laid out for the island. The top band beside the notch carries the name and what the
/// glow is doing; the large power reading and the controls sit below it. The black shell behind them
/// is drawn by the renderer.
struct BubbleContentView: View {
  var onClose: () -> Void
  @ObservedObject var motion: IslandMotion
  let notchSize: CGSize
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @ObservedObject private var power = AppState.shared.power
  @ObservedObject private var settings = AppSettings.shared
  @ObservedObject private var battery = AppState.shared.battery
  /// The two readings that matter most are shown large: the system font, default design, at a size that
  /// follows the large title style (the largest text style is only 26 pt).
  @ScaledMetric(relativeTo: .largeTitle) private var readoutSize: CGFloat = 42
  private let app = AppState.shared

  var body: some View {
    let wing = (IslandMetrics.width - notchSize.width) / 2
    VStack(spacing: 0) {
      HStack(spacing: 0) {
        Label { Text("PeakGlow") } icon: { Image(nsImage: AppGlyph.image) }
          .font(.caption.weight(.semibold))
          .lineLimit(1)
          .minimumScaleFactor(0.8)
          .padding(.leading, 12)
          .frame(width: wing, alignment: .leading)
        Spacer(minLength: 0)
        BubbleStatusLabel(app: app, power: power, dotColor: dotColor)
          .padding(.trailing, 12)
          .frame(width: wing, alignment: .trailing)
      }
      .frame(height: notchSize.height)
      .islandReveal(motion.expanded, delay: 0.10, reduceMotion: reduceMotion)

      // One column of spacing between the groups, so each group reads as one thing.
      VStack(alignment: .leading, spacing: 0) {
        // Two readings built from the same piece: a big number with its unit and one line under it.
        HStack(alignment: .top, spacing: 16) {
          ReadoutColumn(number: powerText, unit: "W", size: readoutSize, alignment: .leading,
                        animatesNumber: !reduceMotion, numberID: power.reading.watts) {
            Text(powerDescription)
          }
          .accessibilityElement(children: .ignore)
          .accessibilityLabel("System power")
          .accessibilityValue(power.reading.availability == .current ? "\(powerText) watts" : powerDescription)
          if let b = battery.snapshot {
            // The charge and the estimated time; nothing else about the battery's state.
            ReadoutColumn(number: "\(b.percent)", unit: "%", size: readoutSize, alignment: .trailing,
                          animatesNumber: false, numberID: Double(b.percent),
                          tint: b.isChargingNow ? .green : nil) {
              Text(b.panelCaption)
                .monospacedDigit()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Battery")
            .accessibilityValue([ "\(b.percent) percent", b.panelCaption ].joined(separator: ", "))
          }
        }
        .frame(height: 56)
        .padding(.top, 12)
        .islandReveal(motion.expanded, delay: 0.16, reduceMotion: reduceMotion)

        if let b = battery.snapshot {
          // The line keeps its room whether or not it has anything to say, so connecting a charger fades its
          // text in without moving anything else.
          let present = b.adapterText != nil || b.powerText != nil
          HStack {
            Text(b.adapterText ?? " ")
            Spacer(minLength: 8)
            Text(b.powerText ?? " ")
          }
          .font(.caption)
          .monospacedDigit()
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .padding(.top, 4)
          .opacity(present ? 1 : 0)
          .animation(reduceMotion ? nil : .easeOut(duration: 0.35), value: present)
          .accessibilityElement(children: .ignore)
          .accessibilityLabel("Power adapter and battery power")
          .accessibilityValue([ b.adapterText, b.powerText ].compactMap { $0 }.joined(separator: ", "))
          .islandReveal(motion.expanded, delay: 0.18, reduceMotion: reduceMotion)
        }

        PowerMeter(watts: meterWatts, medium: settings.mediumWatts, high: settings.highWatts,
                   maximum: max(settings.highWatts * 1.4, 1),
                   gradient: PowerRamp.gradient(medium: settings.mediumWatts, high: settings.highWatts))
          .frame(height: 28)
          .padding(.top, 10)
          .accessibilityHidden(true)
          .islandReveal(motion.expanded, delay: 0.20, reduceMotion: reduceMotion)
        GlowModeControl(app: app)
          .frame(height: 48)
          .padding(.top, 14)
          .islandReveal(motion.expanded, delay: 0.24, reduceMotion: reduceMotion, blurs: false)
        BubbleFooter(onClose: onClose)
          .frame(height: 28)
          .padding(.top, 10)
          .islandReveal(motion.expanded, delay: 0.28, reduceMotion: reduceMotion)
      }
      .padding(.horizontal, 20)
      .padding(.bottom, 14)
    }
    .frame(width: IslandMetrics.width, height: notchSize.height + IslandMetrics.contentHeight, alignment: .top)
    // Normally nearly invisible, so a click on the black shell is not passed to the window behind it.
    // Without the renderer the shell is drawn here, unanimated.
    .background {
      if motion.fallbackShell {
        UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: IslandMetrics.expandedCornerRadius,
                               bottomTrailingRadius: IslandMetrics.expandedCornerRadius, topTrailingRadius: 0,
                               style: .continuous)
          .fill(Color.black)
          .opacity(motion.expanded ? 1 : 0)
          .animation(.easeInOut(duration: 0.18), value: motion.expanded)
      } else {
        Color.black.opacity(0.01)
      }
    }
    // The island is black, so its content uses the dark appearance.
    .environment(\.colorScheme, .dark)
    // This utility surface is interactive even when the foreground app stays active.
    .environment(\.appearsActive, true)
  }

  private var powerText: String {
    power.reading.availability == .current ? String(format: "%.1f", power.reading.watts) : "—"
  }
  private var meterWatts: Double { power.reading.availability == .current ? power.reading.watts : 0 }
  private var powerDescription: String {
    switch power.reading.availability {
    case .waiting: return "Waiting for power data"
    case .current: return "System power"
    case .unavailable: return "Power data unavailable"
    }
  }
  /// The status dot takes the glow's color at the current power.
  private var dotColor: Color {
    power.reading.availability == .current
      ? PowerRamp.color(watts: power.reading.watts, medium: settings.mediumWatts, high: settings.highWatts)
      : Color.secondary
  }
}

extension View {
  /// Layers rise out of the notch in turn as the shell opens, and draw back up into it as it closes.
  /// Opening: a spring settles each layer from slightly small, blurred and high; the layers lower
  /// down start later, so the content follows the shell's own bounce. Closing: the lowest layers
  /// leave first, in under 0.12 s; the shell starts to contract a moment later, so the content has already gone when the shell passes it.
  /// Opacity, scale, blur and offset are animated by SwiftUI without re-evaluating the content.
  /// `blurs` is false for native AppKit controls, which keep to opacity and offset.
  /// With Reduce Motion the layers only fade.
  func islandReveal(_ expanded: Bool, delay: Double, reduceMotion: Bool, blurs: Bool = true) -> some View {
    let last = 0.28
    return self
      .opacity(expanded ? 1 : 0)
      .scaleEffect((expanded || reduceMotion) ? 1 : 0.94, anchor: .top)
      .offset(y: (expanded || reduceMotion) ? 0 : -8)
      .animation(
        reduceMotion ? .easeInOut(duration: 0.16)
          : (expanded ? .spring(response: 0.42, dampingFraction: 0.82).delay(delay)
                      : .easeIn(duration: 0.09).delay((last - delay) * 0.15)),
        value: expanded)
  }
}

/// What the glow is doing, in a few words, with a dot in the glow's current color.
private struct BubbleStatusLabel: View {
  @ObservedObject var app: AppState
  @ObservedObject var power: PowerReadingState
  let dotColor: Color

  private var status: String {
    switch app.preview {
    case .low: return "Glow off"
    case .medium: return "Mid preview"
    case .high: return "High preview"
    case .overheat: return "Hot preview"
    case .auto: break
    }
    if app.gamepadConnected { return "Glow paused" }
    if app.overheatAlarm { return "Temperature high" }
    if power.reading.availability != .current { return "No power data" }
    switch app.effectiveLevel {
    case .low: return "Low load"
    case .medium: return "Moderate load"
    case .high: return "High load"
    }
  }

  var body: some View {
    Label {
      Text(status).lineLimit(1).minimumScaleFactor(0.75)
    } icon: {
      Image(systemName: app.overheatAlarm ? "thermometer.high" : "circle.fill")
        .foregroundStyle(app.overheatAlarm ? Color.orange : dotColor)
    }
    .font(.caption)
    .foregroundStyle(app.overheatAlarm ? Color.orange : Color.secondary)
  }
}

/// The native macOS mode selector updates independently of the static panel shell.
/// Beside the title, one plain line says what the current choice does.
private struct GlowModeControl: View {
  @ObservedObject var app: AppState
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("Glow")
          .font(.caption)
          .foregroundStyle(.secondary)
        Spacer()
        Text(app.preview.isPreview ? "Previewing. Choose Auto to stop" : app.preview.explanation)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      NativeGlowSelector(selection: $app.preview)
        .frame(maxWidth: .infinity)
    }
  }
}

private struct BubbleFooter: View {
  var onClose: () -> Void
  var body: some View {
    HStack(spacing: 8) {
      Button {
        SettingsWindowController.shared.show()
        onClose()
      } label: {
        Label("Settings…", systemImage: "gearshape")
          .font(.callout)
      }
      .buttonStyle(.borderless)
      .accessibilityLabel("Open Settings")
      Spacer()
      Button { NSApp.terminate(nil) } label: {
        Label("Quit", systemImage: "power")
      }
      .labelStyle(.iconOnly)
      .buttonStyle(.glass)
      .buttonBorderShape(.circle)
      .controlSize(.small)
      .accessibilityLabel("Quit PeakGlow")
    }
  }
}

/// A system segmented control, not a drawn replacement. AppKit exposes equal segment
/// distribution to SwiftUI hosting, and macOS 27 adds the tabs role.
private struct NativeGlowSelector: NSViewRepresentable {
  @Binding var selection: PreviewLevel
  // The panel is for quick choices. The previews that tune colors live in Settings.
  private static let modes = PreviewLevel.quickChoices
  private static let labels = modes.map(\.label)
  private static let help = modes.map(\.explanation)

  func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }

  func makeNSView(context: Context) -> NSSegmentedControl {
    let control = NSSegmentedControl(
      labels: Self.labels, trackingMode: .selectOne,
      target: context.coordinator, action: #selector(Coordinator.select(_:)))
    // The tabs role is new in macOS 27; macOS 26 keeps the plain segmented control.
    if #available(macOS 27.0, *) { control.role = .tabs }
    control.segmentStyle = .automatic
    control.borderShape = .capsule
    control.segmentDistribution = .fillEqually
    control.controlSize = .regular
    control.setAccessibilityLabel("Glow mode")
    for index in Self.modes.indices {
      control.setToolTip(Self.help[index], forSegment: index)
    }
    // While a preview from Settings is on, neither segment is selected.
    control.selectedSegment = Self.modes.firstIndex(of: selection) ?? -1
    return control
  }

  func updateNSView(_ control: NSSegmentedControl, context: Context) {
    context.coordinator.selection = $selection
    let index = Self.modes.firstIndex(of: selection) ?? -1
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

/// The app's mark in the menu bar and in the island: a screen with the notch. Drawn as a template
/// image, so the system tints it for light and dark menu bars and for the island.
enum AppGlyph {
  static let image: NSImage = {
    let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
      NSColor.black.setStroke()
      NSColor.black.setFill()
      let screen = NSBezierPath(roundedRect: NSRect(x: 1.4, y: 2.6, width: 15.2, height: 11.8),
                                xRadius: 2.8, yRadius: 2.8)
      screen.lineWidth = 1.35
      screen.stroke()
      // The notch hangs from the screen's top edge.
      NSBezierPath(roundedRect: NSRect(x: 6.7, y: 2.3, width: 4.6, height: 3.9), xRadius: 1.6, yRadius: 1.6).fill()
      NSBezierPath(rect: NSRect(x: 6.7, y: 2.3, width: 4.6, height: 1.6)).fill()
      return true
    }
    image.isTemplate = true
    image.accessibilityDescription = "PeakGlow"
    return image
  }()
}


/// A reading in the controls panel: a big number with its unit, and one line of text under it. Both
/// readings use this, so they have the same size, spacing and baseline; only the alignment differs.
private struct ReadoutColumn<Caption: View>: View {
  let number: String
  let unit: String
  let size: CGFloat
  let alignment: HorizontalAlignment
  let animatesNumber: Bool
  let numberID: Double
  var tint: Color? = nil
  @ViewBuilder let caption: Caption

  var body: some View {
    VStack(alignment: alignment, spacing: 3) {
      HStack(alignment: .lastTextBaseline, spacing: 4) {
        Text(number)
          .font(.system(size: size, weight: .semibold))
          .monospacedDigit()
          .foregroundStyle(tint ?? .primary)
          .animation(.easeInOut(duration: 0.4), value: tint != nil)
          .contentTransition(.numericText())
          .animation(animatesNumber ? .easeOut(duration: 0.18) : nil, value: numberID)
        Text(unit)
          .font(.title3)
          .foregroundStyle(.secondary)
      }
      caption
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
    .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
  }
}
