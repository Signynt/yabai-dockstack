import Foundation

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
        case full
        case compact
        /// Compact chips for the first `visible` windows, then a "+N" chip.
        case overflow(visible: Int)
    }

    /// Picks how to draw chips in `available` points: full (icon + keyword),
    /// compact (icon + space badge), or compact with a trailing "+N" chip.
    public static func fit(fullWidths: [Double], compactWidth: Double,
                           overflowWidth: Double, available: Double) -> Density {
        if fullWidths.reduce(0, +) <= available { return .full }
        if Double(fullWidths.count) * compactWidth <= available { return .compact }
        let room = available - overflowWidth
        let n = compactWidth > 0 && room > 0 ? Int(room / compactWidth) : 0
        return .overflow(visible: min(n, fullWidths.count))
    }
}
