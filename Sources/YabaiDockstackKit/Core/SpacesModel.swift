import Foundation

/// A window rendered inside a space card.
public struct SpacesWindowItem: Equatable, Identifiable {
    public let id: Int
    public let pid: Int
    public let app: String
    public let title: String
    public let aspectRatio: Double
    public let hasFocus: Bool
    public let isSticky: Bool

    public init(window: YabaiWindow) {
        id = window.id
        pid = window.pid
        app = window.app
        title = window.title
        aspectRatio = window.frame.h > 0 ? max(window.frame.w / window.frame.h, 0.1) : 1
        hasFocus = window.hasFocus
        isSticky = window.isSticky
    }
}

/// A virtual desktop and the windows assigned to it.
public struct SpacesItem: Equatable, Identifiable {
    public let id: Int
    public let display: Int
    public let label: String?
    public let isVisible: Bool
    public let windows: [SpacesWindowItem]

    public init(space: SpaceInfo, label: String?, windows: [SpacesWindowItem]) {
        id = space.index
        display = space.display
        self.label = label
        isVisible = space.isVisible
        self.windows = windows
    }
}

/// One display section in the Spaces View.
public struct SpacesDisplayGroup: Equatable, Identifiable {
    public let id: Int
    public let spaces: [SpacesItem]

    public init(display: Int, spaces: [SpacesItem]) {
        id = display
        self.spaces = spaces
    }
}

public enum SpacesModel {
    /// Windows with a non-empty yabai scratchpad assignment are excluded.
    /// Sticky windows remain ordinary Spaces View content.
    public static func displayableWindows(_ windows: [YabaiWindow],
                                          hiddenIDs: Set<Int> = []) -> [YabaiWindow] {
        windows.filter {
            let scratchpad = $0.scratchpad?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let isSystemSettings = $0.app == "System Settings"
            return (scratchpad.isEmpty || isSystemSettings) && !hiddenIDs.contains($0.id)
        }
    }

    public static func windowIDsToMove(from source: Int, to target: Int,
                                       windows: [YabaiWindow]) -> [Int] {
        guard source != target else { return [] }
        return windows.filter { $0.space == source }
            .sorted { ($0.stackIndex, $0.id) < ($1.stackIndex, $1.id) }
            .map(\.id)
    }

    /// Builds display groups in arrangement-index order and spaces in yabai's
    /// mission-control index order. Window order follows stack index and id.
    public static func build(spaces: [SpaceInfo], windows: [YabaiWindow],
                             labels: [Int: String] = [:]) -> [SpacesDisplayGroup] {
        let windowsBySpace = Dictionary(grouping: windows, by: \ .space)
        let items = spaces.sorted { $0.index < $1.index }.map { space in
            let spaceWindows = (windowsBySpace[space.index] ?? []).sorted {
                ($0.stackIndex, $0.id) < ($1.stackIndex, $1.id)
            }
            return SpacesItem(
                space: space,
                label: labels[space.index],
                windows: spaceWindows.map(SpacesWindowItem.init(window:)))
        }
        return Dictionary(grouping: items, by: \ .display)
            .keys.sorted()
            .map { display in
                SpacesDisplayGroup(display: display,
                                   spaces: items.filter { $0.display == display })
            }
    }
}

/// Bounded geometry for the Spaces View's repeated cards.
public struct SpacesLayoutMetrics: Equatable {
    public let columns: Int
    public let spaceWidth: Double
    public let spaceHeight: Double
    public let windowWidth: Double
    public let windowHeight: Double

    public init(columns: Int = 1, spaceWidth: Double, spaceHeight: Double,
                windowWidth: Double, windowHeight: Double) {
        self.columns = columns
        self.spaceWidth = spaceWidth
        self.spaceHeight = spaceHeight
        self.windowWidth = windowWidth
        self.windowHeight = windowHeight
    }
}

public enum SpacesLayout {
    /// Packs previews with an aspect-aware binary layout instead of a fixed
    /// row/column grid. Similar windows stay together so, for example, two
    /// wide short windows can share one side while another window occupies the
    /// opposite side.
    public static func windowTiles(aspects: [Double], width: Double, height: Double,
                                   gap: Double = 5) -> [CGRect] {
        guard !aspects.isEmpty, width > 0, height > 0 else { return [] }
        var result = Array(repeating: CGRect.zero, count: aspects.count)
        let indices = aspects.indices.map { $0 }
        tile(indices: indices, in: CGRect(x: 0, y: 0, width: width, height: height),
             aspects: aspects, gap: gap, result: &result)
        return result
    }

    private static func tile(indices: [Int], in rect: CGRect, aspects: [Double],
                             gap: Double, result: inout [CGRect]) {
        guard let first = indices.first else { return }
        if indices.count == 1 {
            result[first] = rect
            return
        }

        if indices.count == 3 {
            let pair = bestPair(in: indices, aspects: aspects)
            let singleton = indices.first { !pair.contains($0) }!
            let pairRect: CGRect
            let singletonRect: CGRect
            if rect.width >= rect.height {
                let split = rect.width * 0.62
                singletonRect = CGRect(x: rect.minX, y: rect.minY,
                                       width: split - gap / 2, height: rect.height)
                pairRect = CGRect(x: rect.minX + split + gap / 2, y: rect.minY,
                                  width: rect.width - split - gap / 2, height: rect.height)
            } else {
                let split = rect.height * 0.62
                singletonRect = CGRect(x: rect.minX, y: rect.minY,
                                       width: rect.width, height: split - gap / 2)
                pairRect = CGRect(x: rect.minX, y: rect.minY + split + gap / 2,
                                  width: rect.width, height: rect.height - split - gap / 2)
            }
            result[singleton] = singletonRect
            tile(indices: pair, in: pairRect, aspects: aspects, gap: gap, result: &result)
            return
        }

        let sorted = indices.sorted { aspects[$0] > aspects[$1] }
        let leftCount = max(1, sorted.count / 2)
        let left = Array(sorted.prefix(leftCount))
        let right = Array(sorted.dropFirst(leftCount))
        let leftArea = Double(left.count) / Double(indices.count)
        if rect.width >= rect.height {
            let split = rect.width * leftArea
            tile(indices: left,
                 in: CGRect(x: rect.minX, y: rect.minY,
                            width: split - gap / 2, height: rect.height),
                 aspects: aspects, gap: gap, result: &result)
            tile(indices: right,
                 in: CGRect(x: rect.minX + split + gap / 2, y: rect.minY,
                            width: rect.width - split - gap / 2, height: rect.height),
                 aspects: aspects, gap: gap, result: &result)
        } else {
            let split = rect.height * leftArea
            tile(indices: left,
                 in: CGRect(x: rect.minX, y: rect.minY,
                            width: rect.width, height: split - gap / 2),
                 aspects: aspects, gap: gap, result: &result)
            tile(indices: right,
                 in: CGRect(x: rect.minX, y: rect.minY + split + gap / 2,
                            width: rect.width, height: rect.height - split - gap / 2),
                 aspects: aspects, gap: gap, result: &result)
        }
    }

    private static func bestPair(in indices: [Int], aspects: [Double]) -> [Int] {
        var best = Array(indices.prefix(2))
        var score = Double.infinity
        for i in 0..<indices.count {
            for j in (i + 1)..<indices.count {
                let a = max(aspects[indices[i]], 0.1)
                let b = max(aspects[indices[j]], 0.1)
                let candidate = abs(log(a / b))
                if candidate < score {
                    score = candidate
                    best = [indices[i], indices[j]]
                }
            }
        }
        return best
    }

    public static func metrics(displayCount: Int, maxWidth: Double, maxHeight: Double,
                               baseSpaceWidth: Double = 300,
                               minSpaceWidth: Double = 180,
                               gap: Double = 12) -> SpacesLayoutMetrics {
        let count = max(displayCount, 1)
        var width = baseSpaceWidth
        while width > minSpaceWidth {
            let columns = max(1, min(count, Int((maxWidth + gap) / (width + gap))))
            let rows = Double((count + columns - 1) / columns)
            let height = rows * 170 + max(0, rows - 1) * gap
            if height <= maxHeight { break }
            width -= 12
        }
        let boundedWidth = max(width, minSpaceWidth)
        let columns = min(count, max(1, Int((maxWidth + gap) / (boundedWidth + gap))))
        let actualWidth = (maxWidth - Double(max(columns - 1, 0)) * gap) / Double(columns)
        return SpacesLayoutMetrics(
            columns: columns,
            spaceWidth: min(boundedWidth, actualWidth),
            spaceHeight: 170,
            windowWidth: max(72, min(140, (min(boundedWidth, actualWidth) - 24) / 2)),
            windowHeight: 82)
    }
}
