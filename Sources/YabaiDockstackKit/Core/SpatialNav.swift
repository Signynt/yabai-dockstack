import CoreGraphics

/// ↑/↓ over freely placed tiles (they aren't on a grid).
public enum SpatialNav {
    /// The rect whose center lies strictly above / below `rects[index]`'s,
    /// scored |Δy| + 2·|Δx| between centers; ties go to the lower index.
    public static func neighbor(of index: Int, up: Bool, rects: [CGRect]) -> Int? {
        guard rects.indices.contains(index) else { return nil }
        let from = rects[index]
        var best: (i: Int, score: CGFloat)?
        for (i, r) in rects.enumerated() where i != index {
            guard up ? r.midY < from.midY : r.midY > from.midY else { continue }
            let score = abs(r.midY - from.midY) + 2 * abs(r.midX - from.midX)
            if best == nil || score < best!.score { best = (i, score) }
        }
        return best?.i
    }
}
