import Foundation
import CoreGraphics

/// One space's block in the search switcher.
public struct SwitcherSection: Equatable {
    public let space: Int
    public let display: Int
    public let name: String
    public let items: [SwitcherItem]
}

/// Geometry of a sectioned switcher: a header row per section, then its cells.
public struct SectionLayout: Equatable {
    public let headers: [CGRect]
    /// Cell frames in flattened (section by section) item order.
    public let cells: [CGRect]
    public let size: CGSize
}

/// The search switcher groups windows by space so they can be dragged between
/// spaces; every space is listed (empty ones are drop targets too).
public enum SwitcherSections {
    /// Sections in (display, space index) order; items keep their incoming
    /// (MRU) order. Names are the yabai label or "Space N", prefixed with the
    /// display when there's more than one.
    public static func build(items: [SwitcherItem], spaces: [SpaceInfo],
                             labels: [Int: String]) -> [SwitcherSection] {
        let multiDisplay = Set(spaces.map(\.display)).count > 1
        return spaces.sorted { ($0.display, $0.index) < ($1.display, $1.index) }.map { sp in
            let label = labels[sp.index] ?? ""
            let base = label.isEmpty ? "Space \(sp.index)" : label
            return SwitcherSection(space: sp.index, display: sp.display,
                                   name: multiDisplay ? "D\(sp.display) · \(base)" : base,
                                   items: items.filter { $0.space == sp.index })
        }
    }

    public static func layout(counts: [Int], columns: Int, cell: CGSize, gap: Double,
                              headerHeight: Double, emptyHeight: Double) -> SectionLayout {
        let cols = max(columns, 1)
        let g = CGFloat(gap)
        let width = CGFloat(cols) * cell.width + CGFloat(cols - 1) * g
        var headers: [CGRect] = [], cells: [CGRect] = []
        var y: CGFloat = 0
        for (si, n) in counts.enumerated() {
            if si > 0 { y += g }
            headers.append(CGRect(x: 0, y: y, width: width, height: CGFloat(headerHeight)))
            y += CGFloat(headerHeight)
            if n == 0 { y += CGFloat(emptyHeight); continue }
            for i in 0..<n {
                cells.append(CGRect(x: CGFloat(i % cols) * (cell.width + g),
                                    y: y + CGFloat(i / cols) * (cell.height + g),
                                    width: cell.width, height: cell.height))
            }
            let rows = (n + cols - 1) / cols
            y += CGFloat(rows) * cell.height + CGFloat(rows - 1) * g
        }
        return SectionLayout(headers: headers, cells: cells, size: CGSize(width: width, height: y))
    }

    /// ↑/↓: the cell nearest in x on the closest visual row above / below.
    public static func verticalNeighbor(of index: Int, up: Bool, cells: [CGRect]) -> Int? {
        guard cells.indices.contains(index) else { return nil }
        let from = cells[index]
        let rowYs = Set(cells.map(\.minY)).filter { up ? $0 < from.minY : $0 > from.minY }
        guard let rowY = up ? rowYs.max() : rowYs.min() else { return nil }
        return cells.indices.filter { cells[$0].minY == rowY }
            .min { abs(cells[$0].midX - from.midX) < abs(cells[$1].midX - from.midX) }
    }

    /// The section whose band (its header top → the next header top) holds `point`.
    public static func section(at point: CGPoint, layout: SectionLayout) -> Int? {
        guard point.y >= 0, point.y < layout.size.height else { return nil }
        return layout.headers.indices.last { layout.headers[$0].minY <= point.y }
    }
}
