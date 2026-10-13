import AppKit

enum NotchedScreenFinder {
    /// Locate a built-in display with valid notch geometry, regardless of main display.
    static func find() -> NSScreen? {
        NSScreen.screens.first { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                  CGDisplayIsBuiltin(CGDirectDisplayID(number.uint32Value)) != 0 else { return false }
            return notchRect(of: screen) != nil
        }
    }

    /// Notch bounds in global AppKit coordinates, with the origin at bottom left.
    static func notchRect(of screen: NSScreen) -> CGRect? {
        guard let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea else { return nil }
        guard right.minX > left.maxX, left.height > 0 else { return nil }
        return CGRect(
            x: left.maxX,
            y: left.minY,
            width: right.minX - left.maxX,
            height: left.height)
    }

    /// Horizontal notch center in global coordinates.
    static func notchCenterX(of screen: NSScreen) -> CGFloat? {
        notchRect(of: screen)?.midX
    }
}
