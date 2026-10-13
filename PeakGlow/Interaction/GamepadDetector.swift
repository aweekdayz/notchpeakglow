import Foundation
import GameController

/// Pause automatic glow when a GameController device is connected.
/// Use controller connection and disconnection notifications only.
/// Do not perform active Bluetooth discovery.
/// Check already connected devices when starting.
final class GamepadDetector {
    var onGamepadChange: ((Bool) -> Void)?

    private(set) var hasGamepad = false

    func start() {
        NotificationCenter.default.addObserver(
            forName: .GCControllerDidConnect, object: nil, queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }
        NotificationCenter.default.addObserver(
            forName: .GCControllerDidDisconnect, object: nil, queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }
        refresh()   // Synchronize the current connection state at startup.
    }

    func refresh() {
        let connected = !GCController.controllers().isEmpty
        if connected != hasGamepad {
            hasGamepad = connected
            NSLog("PeakGlow: gamepad \(connected ? "connected -> automatic glow paused" : "disconnected -> automatic glow resumed")")
            onGamepadChange?(connected)
        }
    }
}
