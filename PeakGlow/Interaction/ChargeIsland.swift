import AppKit
import SwiftUI

/// Plugging in the charger opens a small island out of the notch, the way a Dynamic Island shows
/// charging, with the word "Charging" on the left and the charge and a battery on the right, then draws
/// back in after a few seconds. The renderer draws the black shell and the
/// glow around it with the same spring as the controls panel; this window only holds the content,
/// ignores the pointer, and never takes focus.
@MainActor final class ChargeIslandController {
    private var panel: NSPanel?
    private let motion = IslandMotion()
    private let model = ChargeIslandModel()
    private weak var glow: GlowWindow?
    private var generation: UInt = 0
    private static let visibleSeconds: TimeInterval = 3.0

    init(glow: GlowWindow) { self.glow = glow }

    /// Build the window and its content ahead of time, hidden, so the first plug-in does not create the
    /// SwiftUI view in the middle of the animation.
    func prepare() {
        guard panel == nil else { return }
        _ = makePanel(size: CGSize(width: 340, height: 32))
    }

    /// Show the island. Returns false when it cannot be drawn, so the caller can use the ripple instead.
    @discardableResult
    func present(percent: Int, full: Bool) -> Bool {
        guard let glow, glow.canDrawIsland,
              let screen = NotchedScreenFinder.find(),
              let notch = NotchedScreenFinder.notchRect(of: screen) else { return false }
        generation &+= 1
        let current = generation

        // Exactly as tall as the notch and a little wider than it on each side, so it reads as the
        // notch itself widening, with the content centered on the notch's own height.
        let size = CGSize(width: notch.width + 2 * ChargeIslandMetrics.wing, height: notch.height)
        let frame = CGRect(x: notch.midX - size.width / 2, y: screen.frame.maxY - size.height,
                           width: size.width, height: size.height)
        model.percent = percent
        model.full = full
        model.notchSize = notch.size
        model.size = size
        let p = panel ?? makePanel(size: size)
        if p.frame != frame { p.setFrame(frame, display: false) }
        motion.expanded = false
        p.orderFrontRegardless()
        announce(percent: percent, full: full)

        // Let SwiftUI lay out once while the island is still in the notch, then open it.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.generation == current else { return }
            self.motion.expanded = true
            self.glow?.setIsland(expanded: true, size: size, radius: size.height / 2)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.visibleSeconds) { [weak self] in
            guard let self, self.generation == current else { return }
            // The content slides in with the shell, so both start to close together.
            self.motion.expanded = false
            self.glow?.setIsland(expanded: false, size: size, radius: size.height / 2)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
                guard let self, self.generation == current else { return }
                self.panel?.orderOut(nil)
            }
        }
        return true
    }

    /// Put the island away at once, for example because the controls are opening in its place.
    func cancel() {
        guard panel?.isVisible == true else { return }
        generation &+= 1
        motion.expanded = false
        glow?.cancelIsland()
        panel?.orderOut(nil)
    }

    /// The island is brief and visual, so VoiceOver is told what it says.
    private func announce(percent: Int, full: Bool) {
        let text = full ? "Fully charged" : "Charging, \(percent) percent"
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }

    private func makePanel(size: CGSize) -> NSPanel {
        let p = NSPanel(contentRect: CGRect(origin: .zero, size: size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.sharingType = AppSettings.overlaySharingType
        p.ignoresMouseEvents = true
        p.isFloatingPanel = true
        p.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 2)
        p.collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .stationary, .ignoresCycle]
        p.hidesOnDeactivate = false
        p.isMovable = false
        let hosting = NSHostingView(rootView: ChargeIslandView(motion: motion, model: model))
        hosting.appearance = NSAppearance(named: .darkAqua)
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        hosting.sizingOptions = []
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.autoresizingMask = [.width, .height]
        p.contentView = hosting
        panel = p
        return p
    }
}

enum ChargeIslandMetrics {
    /// How far the island reaches out beside the notch on each side.
    static let wing: CGFloat = 110
}

@MainActor final class ChargeIslandModel: ObservableObject {
    @Published var percent = 0
    @Published var full = false
    @Published var notchSize = CGSize(width: 180, height: 32)
    @Published var size = CGSize(width: 180 + 2 * ChargeIslandMetrics.wing, height: 32)
}

struct ChargeIslandView: View {
    @ObservedObject var motion: IslandMotion
    @ObservedObject var model: ChargeIslandModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The shell widens from the notch with a spring; the two items ride its edges. They start beside the
    /// notch, where the shell is still narrow, and slide outward with it, fading in as it opens and out
    /// as it closes. The springs match the renderer's, so the items and the shell move together.
    private var opening: Animation { .spring(response: 0.46, dampingFraction: 0.74) }
    private var closing: Animation { .spring(response: 0.34, dampingFraction: 0.9) }

    var body: some View {
        let wing = max(0, (model.size.width - model.notchSize.width) / 2)
        let travel = reduceMotion ? 0 : wing * 0.85
        let shown = motion.expanded
        HStack(spacing: 0) {
            Text(model.full ? "Charged" : "Charging")
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.leading, 18)
                .frame(width: wing, alignment: .leading)
                .offset(x: shown ? 0 : travel)
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                Text("\(model.percent)%")
                    .font(.headline)
                    .monospacedDigit()
                    .foregroundStyle(.green)
                    .lineLimit(1)
                    .fixedSize()
                Image(systemName: "battery.100percent.bolt")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.green)
                    .font(.title2)
            }
            .padding(.trailing, 14)
            .frame(width: wing, alignment: .trailing)
            .offset(x: shown ? 0 : -travel)
        }
        .opacity(shown ? 1 : 0)
        .animation(reduceMotion ? .easeInOut(duration: 0.16) : (shown ? opening : closing), value: shown)
        .animation(shown ? .easeOut(duration: 0.18).delay(0.10) : .easeIn(duration: 0.12), value: shown)
        .frame(width: model.size.width, height: model.size.height)
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.full ? "Fully charged, \(model.percent) percent" : "Charging, \(model.percent) percent")
    }
}
