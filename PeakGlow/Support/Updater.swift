import AppKit
import Sparkle

/// Automatic updates with Sparkle. The app checks about once a day (see `SUScheduledCheckInterval`),
/// and "Check for Updates…" asks at once. Updates come from the signed appcast named by
/// `SUFeedURL`; each download is verified against the EdDSA key in `SUPublicEDKey` and against the
/// app's Developer ID signature before it replaces the app. Beta builds are on a separate channel
/// and are never offered to people on the stable channel.
@MainActor final class UpdateController: NSObject, ObservableObject, NSMenuItemValidation {
    static let shared = UpdateController()

    private let controller: SPUStandardUpdaterController

    /// Mirrors Sparkle's own setting, so the Settings switch and Sparkle never disagree.
    @Published var automaticChecks: Bool {
        didSet {
            guard automaticChecks != controller.updater.automaticallyChecksForUpdates else { return }
            controller.updater.automaticallyChecksForUpdates = automaticChecks
        }
    }

    private override init() {
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        automaticChecks = controller.updater.automaticallyChecksForUpdates
        super.init()
    }

    /// Start Sparkle at launch (creating the controller starts it).
    func start() {}

    var canCheckForUpdates: Bool { controller.updater.canCheckForUpdates }

    /// "Check for Updates…" is dimmed while a check is already running.
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        item.action == #selector(checkForUpdates(_:)) ? controller.updater.canCheckForUpdates : true
    }

    @objc func checkForUpdates(_ sender: Any?) {
        // This is a background app: bring Sparkle's window to the front.
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(sender)
    }
}
