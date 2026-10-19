import Foundation

/// One `yabai -m window <a> --swap <b>` call.
public struct SwapStep: Equatable {
    public let a: Int
    public let b: Int
    public init(a: Int, b: Int) { self.a = a; self.b = b }
}

/// Turns a drag-to-reorder gesture on a stack indicator into yabai swaps.
public enum StackReorderPlanner {
    /// Adjacent swaps that move `ids[from]` to final index `to` (list-insert
    /// semantics). Empty when nothing moves or an index is out of range.
    public static func swaps(ids: [Int], from: Int, to: Int) -> [SwapStep] {
        guard ids.indices.contains(from), ids.indices.contains(to), from != to else { return [] }
        let moving = ids[from]
        let step = to > from ? 1 : -1
        return stride(from: from + step, through: to, by: step).map { SwapStep(a: moving, b: ids[$0]) }
    }

    /// Cell index under a point `offsetFromTop` points below the indicator's top.
    public static func dropIndex(offsetFromTop: Double, cell: Double, count: Int) -> Int {
        guard count > 0, cell > 0 else { return 0 }
        return min(max(Int(offsetFromTop / cell), 0), count - 1)
    }
}
