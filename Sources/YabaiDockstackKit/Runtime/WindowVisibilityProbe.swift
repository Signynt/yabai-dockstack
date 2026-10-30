import Foundation
import CoreGraphics

/// Drops yabai ids that no longer have a real macOS window (ghost entries).
/// Minimized windows and hidden apps are kept: the switcher is how you get
/// them back.
public final class WindowVisibilityProbe {
    public init() {}

    /// Returns yabai ids still represented by a real macOS window. A nil result
    /// means the window-list query was unavailable, so callers should preserve
    /// the yabai data instead of hiding everything.
    public func liveWindowIDs(_ windows: [YabaiWindow]) -> Set<Int>? {
        guard let raw = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID)
                as? [[String: Any]] else { return nil }
        let ids = raw.compactMap { ($0[kCGWindowNumber as String] as? NSNumber)?.intValue }
        guard !ids.isEmpty else { return nil }
        let candidates = Set(ids)
        return Set(windows.map(\.id).filter { candidates.contains($0) })
    }
}
