import Foundation
import CoreGraphics

/// Per-display window strip shown under the menu bar: every window on a
/// display, grouped by space, labelled with its `WindowLabeler` keyword.
public enum WindowStripModel {
    public struct Chip: Equatable {
        public let id: Int
        public let pid: Int
        public let app: String
        public let keyword: String
        public let title: String
        public let space: Int
        public let focused: Bool
    }
    public struct SpaceSection: Equatable {
        public let space: Int
        /// The space's yabai label, else its number.
        public let name: String
        public let isVisible: Bool
        public let chips: [Chip]
    }
    public struct DisplayStrip: Equatable {
        public let display: Int
        /// The display's visible space is a native-fullscreen space.
        public let hidden: Bool
        public let sections: [SpaceSection]
        public init(display: Int, hidden: Bool, sections: [SpaceSection]) {
            self.display = display; self.hidden = hidden; self.sections = sections
        }
    }

    /// What a display's panel was last drawn from.
    public struct Rendered: Equatable {
        public let strip: DisplayStrip
        public let frame: CGRect
        public let scale: Double
        public init(strip: DisplayStrip, frame: CGRect, scale: Double = 1) {
            self.strip = strip; self.frame = frame; self.scale = scale
        }
    }

    /// Redraw when the content, the screen's frame (resolution, arrangement,
    /// menu bar) or the strip size changed.
    public static func needsRender(cached: Rendered?, strip: DisplayStrip, frame: CGRect,
                                   scale: Double = 1) -> Bool {
        cached != Rendered(strip: strip, frame: frame, scale: scale)
    }

    /// Displays ascending; per display only spaces that have windows, ascending;
    /// chips ordered by (stackIndex, id).
    /// `includeEmpty`: also list spaces with no windows (drop targets while dragging).
    public static func build(windows: [YabaiWindow], spaces: [SpaceInfo],
                             spaceLabels: [Int: String], includeEmpty: Bool = false) -> [DisplayStrip] {
        let keywords = WindowLabeler.keywords(windows)
        let spaceByIndex = Dictionary(spaces.map { ($0.index, $0) }, uniquingKeysWith: { a, _ in a })
        let byDisplay = Dictionary(grouping: windows, by: { $0.display })
        var displays = Set(byDisplay.keys)
        if includeEmpty { displays.formUnion(spaces.map(\.display)) }
        return displays.sorted().map { display in
            let bySpace = Dictionary(grouping: byDisplay[display] ?? [], by: { $0.space })
            var spaceIDs = Set(bySpace.keys)
            if includeEmpty {
                spaceIDs.formUnion(spaces.filter { $0.display == display && !$0.isNativeFullscreen }.map(\.index))
            }
            let sections = spaceIDs.sorted().map { space -> SpaceSection in
                let chips = (bySpace[space] ?? [])
                    .sorted { ($0.stackIndex, $0.id) < ($1.stackIndex, $1.id) }
                    .map { Chip(id: $0.id, pid: $0.pid, app: $0.app, keyword: keywords[$0.id] ?? $0.app,
                                title: $0.title, space: $0.space, focused: $0.hasFocus) }
                let label = spaceLabels[space] ?? ""
                return SpaceSection(space: space, name: label.isEmpty ? "\(space)" : label,
                                    isVisible: spaceByIndex[space]?.isVisible ?? false, chips: chips)
            }
            let hidden = spaces.contains { $0.display == display && $0.isVisible && $0.isNativeFullscreen }
            return DisplayStrip(display: display, hidden: hidden, sections: sections)
        }
    }

    /// The space a chip dropped at `x` lands in: the section under it, the
    /// nearest one when it falls in a divider gap, nil outside the strip.
    public static func dropSpace(x: Double, sections: [(space: Int, minX: Double, maxX: Double)]) -> Int? {
        guard let first = sections.map(\.minX).min(), let last = sections.map(\.maxX).max(),
              x >= first, x <= last else { return nil }
        if let hit = sections.first(where: { x >= $0.minX && x <= $0.maxX }) { return hit.space }
        return sections.min { min(abs(x - $0.minX), abs(x - $0.maxX)) < min(abs(x - $1.minX), abs(x - $1.maxX)) }?.space
    }

    /// As above, but a drop well above / below the strip (y outside its height
    /// plus some slack) is a cancel, not a move.
    public static func dropSpace(x: Double, y: Double, height: Double,
                                 sections: [(space: Int, minX: Double, maxX: Double)]) -> Int? {
        let slack = 12.0
        guard y >= -slack, y <= height + slack else { return nil }
        return dropSpace(x: x, sections: sections)
    }

    public enum Density: Equatable {
        /// Icon + full keyword.
        case full
        /// Icon + shortened keyword.
        case compact
        /// Icons only.
        case iconOnly
        /// Icons for the first `visible` windows, then a "+N" chip.
        case overflow(visible: Int)
    }

    /// Picks the richest chip style that fits `available` points.
    public static func fit(fullWidths: [Double], compactWidths: [Double], iconWidth: Double,
                           overflowWidth: Double, available: Double) -> Density {
        if fullWidths.reduce(0, +) <= available { return .full }
        if compactWidths.reduce(0, +) <= available { return .compact }
        if Double(fullWidths.count) * iconWidth <= available { return .iconOnly }
        let room = available - overflowWidth
        let n = iconWidth > 0 && room > 0 ? Int(room / iconWidth) : 0
        return .overflow(visible: min(n, fullWidths.count))
    }
}
