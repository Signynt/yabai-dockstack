import Foundation
import CoreGraphics

/// One space's block in the search switcher.
public struct SwitcherSection: Equatable {
    public let space: Int
    public let display: Int
    public let name: String
    public let items: [SwitcherItem]
    /// Shown on its display right now.
    public let isVisible: Bool
    /// The space the user is on.
    public let hasFocus: Bool
}

/// Geometry of a sectioned switcher: one card per space (header + cells),
/// cards flowing left to right and wrapping into rows.
public struct SectionLayout: Equatable {
    /// Each space card's full rect.
    public let sections: [CGRect]
    /// Each card's header strip.
    public let headers: [CGRect]
    /// Cell frames in flattened (section by section) item order.
    public let cells: [CGRect]
    /// One band per display (multi-display only), enclosing its cards.
    public let displays: [CGRect]
    public let size: CGSize
}

/// The search switcher groups windows by space so they can be dragged between
/// spaces; every space is listed (empty ones are drop targets too).
public enum SwitcherSections {
    /// Sections in (display, space index) order; items keep their incoming
    /// (MRU) order. Names are the yabai label or "Space N" (the display is
    /// named by its band in the layout).
    public static func build(items: [SwitcherItem], spaces: [SpaceInfo],
                             labels: [Int: String]) -> [SwitcherSection] {
        // Native-fullscreen spaces can't take other windows.
        spaces.filter { !$0.isNativeFullscreen }.sorted { ($0.display, $0.index) < ($1.display, $1.index) }.map { sp in
            let label = labels[sp.index] ?? ""
            return SwitcherSection(space: sp.index, display: sp.display,
                                   name: label.isEmpty ? "Space \(sp.index)" : label,
                                   items: items.filter { $0.space == sp.index },
                                   isVisible: sp.isVisible, hasFocus: sp.hasFocus)
        }
    }

    /// Cards are `min(count, columns)` cells wide (one cell when empty); they
    /// sit `2 × gap` apart and wrap to a new row past `maxWidth`.
    /// `displays` (one per count): each display starts a new band — a
    /// `displayHeader` title row, cards inset by `displayPad`; empty = no bands.
    public static func layout(counts: [Int], columns: Int, cell: CGSize, gap: Double,
                              headerHeight: Double, emptyHeight: Double, maxWidth: Double,
                              displays: [Int] = [], displayHeader: Double = 0,
                              displayPad: Double = 0) -> SectionLayout {
        let cols = max(columns, 1)
        let g = CGFloat(gap), sep = CGFloat(gap) * 2
        let hh = CGFloat(headerHeight)
        let banded = !displays.isEmpty && displays.count == counts.count
        let pad = banded ? CGFloat(displayPad) : 0, dh = banded ? CGFloat(displayHeader) : 0
        var sections: [CGRect] = [], headers: [CGRect] = [], cells: [CGRect] = []
        var bands: [(top: CGFloat, bottom: CGFloat)] = []
        var bandTop: CGFloat = 0
        var x: CGFloat = pad, y: CGFloat = dh, rowH: CGFloat = 0, width: CGFloat = 0
        for (si, n) in counts.enumerated() {
            let across = max(min(n, cols), 1)
            let w = CGFloat(across) * cell.width + CGFloat(across - 1) * g
            let rows = (n + cols - 1) / cols
            let bodyH = n == 0 ? CGFloat(emptyHeight) : CGFloat(rows) * cell.height + CGFloat(rows - 1) * g
            let h = hh + bodyH
            if banded && si > 0 && displays[si] != displays[si - 1] {
                bands.append((bandTop, y + rowH + pad))
                bandTop = y + rowH + pad + sep
                x = pad; y = bandTop + dh; rowH = 0
            } else if x > pad && x + w > CGFloat(maxWidth) - pad {
                x = pad; y += rowH + sep; rowH = 0
            }
            let card = CGRect(x: x, y: y, width: w, height: h)
            sections.append(card)
            headers.append(CGRect(x: x, y: y, width: w, height: hh))
            for i in 0..<n {
                cells.append(CGRect(x: x + CGFloat(i % cols) * (cell.width + g),
                                    y: y + hh + CGFloat(i / cols) * (cell.height + g),
                                    width: cell.width, height: cell.height))
            }
            width = max(width, card.maxX)
            rowH = max(rowH, h)
            x += w + sep
        }
        guard banded else {
            return SectionLayout(sections: sections, headers: headers, cells: cells, displays: [],
                                 size: CGSize(width: width, height: y + rowH))
        }
        bands.append((bandTop, y + rowH + pad))
        let fullW = width + pad
        return SectionLayout(sections: sections, headers: headers, cells: cells,
                             displays: bands.map { CGRect(x: 0, y: $0.top, width: fullW, height: $0.bottom - $0.top) },
                             size: CGSize(width: fullW, height: y + rowH + pad))
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

    /// The space card under `point`, if any. `visible`: the scrolled-into-view
    /// part of the cards — a drop outside it doesn't land on a hidden card.
    public static func section(at point: CGPoint, layout: SectionLayout, visible: CGRect? = nil) -> Int? {
        if let visible, !visible.contains(point) { return nil }
        return layout.sections.firstIndex { $0.contains(point) }
    }
}
