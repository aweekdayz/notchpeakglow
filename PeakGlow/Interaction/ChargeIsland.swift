import AppKit
import SwiftUI

/// Plugging in the charger opens a small island out of the notch, the way a Dynamic Island shows
/// charging: it widens to either side of the notch with a battery on the left and the charge on
/// the right, then draws back in after a few seconds. The renderer draws the black shell and the
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

    /// Show the island. Returns false when it cannot be drawn, so the caller can use the ripple instead.
    @discardableResult
    func present(percent: Int, full: Bool) -> Bool {
        guard let glow, glow.canDrawIsland,
              let screen = NotchedScreenFinder.find(),
              let notch = NotchedScreenFinder.notchRect(of: screen) else { return false }
        generation &+= 1
        let current = generation

        // As wide as the controls panel and a little taller than the notch, rounded to a pill.
        let size = CGSize(width: IslandMetrics.width, height: notch.height + 8)
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
            // The content leaves first; the shell follows a moment later, as with the controls panel.
            self.motion.expanded = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                guard let self, self.generation == current else { return }
                self.glow?.setIsland(expanded: false, size: size, radius: size.height / 2)
            }
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

@MainActor final class ChargeIslandModel: ObservableObject {
    @Published var percent = 0
    @Published var full = false
    @Published var notchSize = CGSize(width: 180, height: 32)
    @Published var size = CGSize(width: IslandMetrics.width, height: 40)
}

private struct ChargeIslandView: View {
    @ObservedObject var motion: IslandMotion
    @ObservedObject var model: ChargeIslandModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The battery fills from empty to the charge as the island opens.
    @State private var shownLevel: Double = 0

    var body: some View {
        let wing = max(0, (model.size.width - model.notchSize.width) / 2)
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.green)
                    .scaleEffect(motion.expanded || reduceMotion ? 1 : 0.4)
                    .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.55).delay(0.28), value: motion.expanded)
                Image(systemName: "battery.100percent", variableValue: shownLevel)
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(.green)
            }
            .padding(.leading, 18)
            .frame(width: wing, alignment: .leading)
            .islandReveal(motion.expanded, delay: 0.14, reduceMotion: reduceMotion, blurs: false)
            Spacer(minLength: 0)
            Text(model.full ? "Full" : "\(model.percent)%")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .padding(.trailing, 18)
                .frame(width: wing, alignment: .trailing)
                .islandReveal(motion.expanded, delay: 0.20, reduceMotion: reduceMotion, blurs: false)
        }
        .frame(width: model.size.width, height: model.notchSize.height, alignment: .top)
        .frame(width: model.size.width, height: model.size.height, alignment: .top)
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.full ? "Fully charged" : "Charging, \(model.percent) percent")
        .onChange(of: motion.expanded) { _, expanded in
            if expanded {
                withAnimation(reduceMotion ? nil : .smooth(duration: 0.9).delay(0.25)) {
                    shownLevel = Double(model.percent) / 100
                }
            } else {
                shownLevel = 0
            }
        }
    }
}
