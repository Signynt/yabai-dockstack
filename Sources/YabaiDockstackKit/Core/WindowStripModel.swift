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
    public static func build(windows: [YabaiWindow], spaces: [SpaceInfo],
                             spaceLabels: [Int: String]) -> [DisplayStrip] {
        let keywords = WindowLabeler.keywords(windows)
        let spaceByIndex = Dictionary(spaces.map { ($0.index, $0) }, uniquingKeysWith: { a, _ in a })
        let byDisplay = Dictionary(grouping: windows, by: { $0.display })
        return byDisplay.keys.sorted().map { display in
            let bySpace = Dictionary(grouping: byDisplay[display] ?? [], by: { $0.space })
            let sections = bySpace.keys.sorted().map { space -> SpaceSection in
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
