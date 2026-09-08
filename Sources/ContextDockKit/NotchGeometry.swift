import Foundation

// MARK: - Notch geometry (pure, testable, never hardcoded)
//
// Measured on real hardware (NotchBay, DynamicNotchKit):
//   16" Pro: 220x38pt · 14" Pro: 185x32pt · this dev machine: 179x32pt
// Point size scales with display scaling; physical size doesn't.
// Source of truth is always NSScreen (safeAreaInsets.top + auxiliary areas).
// This struct holds the math so the AppKit layer stays a thin reader.

public struct NotchGeometry: Hashable, Sendable {
    public var screenWidth: CGFloat
    public var auxLeftWidth: CGFloat?
    public var auxRightWidth: CGFloat?
    public var safeTop: CGFloat
    public var menuBarHeight: CGFloat

    public init(screenWidth: CGFloat, auxLeftWidth: CGFloat?, auxRightWidth: CGFloat?, safeTop: CGFloat, menuBarHeight: CGFloat) {
        self.screenWidth = screenWidth
        self.auxLeftWidth = auxLeftWidth
        self.auxRightWidth = auxRightWidth
        self.safeTop = safeTop
        self.menuBarHeight = menuBarHeight
    }

    public var hasNotch: Bool { auxLeftWidth != nil && auxRightWidth != nil && safeTop > 0 }

    /// Exact cutout width, or nil on notch-less screens.
    public var notchWidth: CGFloat? {
        guard let l = auxLeftWidth, let r = auxRightWidth, hasNotch else { return nil }
        return max(0, screenWidth - l - r)
    }

    public var notchHeight: CGFloat { hasNotch ? safeTop : menuBarHeight }

    /// Collapsed island = exactly the cutout. Pure black blends with hardware.
    public var collapsedWidth: CGFloat { notchWidth ?? 300 }

    /// Expansion wings: symmetric left/right growth from notch center.
    /// Compact (1 agent / hover): +240. Full (feed): +460, capped to 720.
    public func expandedWidth(full: Bool) -> CGFloat {
        let base = notchWidth ?? 300
        return min(base + (full ? 460 : 240), 720)
    }

    /// Hardware corner truth: ~4pt top, ~8pt bottom flare. Menu bar overdraws ~5pt.
    public static let topRadius: CGFloat = 4
    public static let bottomRadius: CGFloat = 10

    /// Last-resort geometry when the window server reports no screens.
    /// Deliberately notch-less: a 300pt pill, never a fabricated cutout.
    public static let fallback = NotchGeometry(
        screenWidth: 1470, auxLeftWidth: nil, auxRightWidth: nil,
        safeTop: 0, menuBarHeight: 26
    )
}

// MARK: - Island design tokens (single location per brief §2)
//
// Proposed ContextDock values. Deliberate deviation: expanded width grows
// symmetrically from the measured notch (notchW + wings) instead of a fixed
// 480pt, so the wings read as the notch itself stretching.

public enum IslandTokens {
    public static let expandedRadius: CGFloat = 22
    public static let compactWingEach: CGFloat = 72
    public static let rowMinHeight: CGFloat = 56
    public static let padding: CGFloat = 14
    public static let titleSize: CGFloat = 13
    public static let detailSize: CGFloat = 11
    public static let expandedFullHeight: CGFloat = 520
    public static let expandedPeekHeight: CGFloat = 300
    public static let morphSeconds: Double = 0.36
    public static let morphDamping: Double = 0.9
    public static let hoverOpenNs: UInt64 = 120_000_000
    public static let hoverCloseNs: UInt64 = 250_000_000
}
