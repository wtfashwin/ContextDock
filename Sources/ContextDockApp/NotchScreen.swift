import AppKit
import ContextDockKit

extension NSScreen {
    /// Exact cutout rect in screen coordinates, or nil on notch-less displays.
    var notchFrame: NSRect? {
        guard let l = auxiliaryTopLeftArea, let r = auxiliaryTopRightArea,
              safeAreaInsets.top > 0 else { return nil }
        let w = frame.width - l.width - r.width
        guard w > 0 else { return nil }
        return NSRect(x: frame.midX - w / 2, y: frame.maxY - safeAreaInsets.top,
                      width: w, height: safeAreaInsets.top)
    }

    var menubarHeight: CGFloat { frame.maxY - visibleFrame.maxY }

    var notchGeometry: NotchGeometry {
        NotchGeometry(
            screenWidth: frame.width,
            auxLeftWidth: auxiliaryTopLeftArea?.width,
            auxRightWidth: auxiliaryTopRightArea?.width,
            safeTop: safeAreaInsets.top,
            menuBarHeight: menubarHeight > 0 ? menubarHeight : 26
        )
    }

    /// Prefer the built-in notched display; else mouse screen; else main.
    /// Nil-safe: returns nil when the window server reports no screens
    /// (pre-login / display reconfigure) instead of trapping on screens[0].
    static var island: NSScreen? {
        if let notch = NSScreen.screens.first(where: { $0.notchFrame != nil }) { return notch }
        let mouse = NSEvent.mouseLocation
        if let hit = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) { return hit }
        return NSScreen.main ?? NSScreen.screens.first
    }
}
