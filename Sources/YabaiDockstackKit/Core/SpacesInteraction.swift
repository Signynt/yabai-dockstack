import CoreGraphics

/// What clicking an empty part of a space card does.
public enum CardClick: Equatable {
    case focusSpace(Int)
    case focusWindow(Int)
    case nothing
}

/// Drop / swap / click rules of the Spaces-style search switcher.
public enum SpacesInteraction {
    /// Hover selects only once the pointer has moved off where it rested when
    /// the panel opened, so a resting pointer can't replace the MRU pick.
    public static func hoverPasses(gate: CGPoint?, pointer: CGPoint, slack: CGFloat = 4) -> Bool {
        guard let gate else { return true }
        return abs(pointer.x - gate.x) > slack || abs(pointer.y - gate.y) > slack
    }

    /// What Enter / ⌘W / ⌘Q act on: the highlighted window; nothing once the
    /// pointer has left every tile and the highlight is gone.
    public static func actionIndex(selection: Int, count: Int, highlighted: Bool) -> Int? {
        highlighted && selection >= 0 && selection < count ? selection : nil
    }

    /// The space card under `point`. Nil in a gap, on a fullscreen card, or
    /// outside `visible` (the scrolled-into-view part of the cards).
    public static func dropTarget(at point: CGPoint,
                                  cards: [(space: Int, rect: CGRect, isFullscreen: Bool)],
                                  visible: CGRect?) -> Int? {
        if let visible, !visible.contains(point) { return nil }
        guard let card = cards.first(where: { $0.rect.contains(point) }), !card.isFullscreen else { return nil }
        return card.space
    }

    /// Swapping two spaces' windows needs the scripting addition; without it
    /// a space drag silently does nothing.
    public static func swapAllowed(source: Int, target: Int, saAvailable: Bool, fullscreen: Set<Int>) -> Bool {
        saAvailable && source != target && !fullscreen.contains(source) && !fullscreen.contains(target)
    }

    /// Without the SA a space can't be focused directly: go via its most
    /// recent window, or do nothing for an empty space.
    public static func cardClick(space: Int, saAvailable: Bool, recentWindowInSpace: Int?) -> CardClick {
        if saAvailable { return .focusSpace(space) }
        return recentWindowInSpace.map(CardClick.focusWindow) ?? .nothing
    }

    /// The space's most recently focused window; the MRU only knows windows
    /// focused since launch, so fall back to the card's first window.
    public static func recentWindow(inSpace space: Int, mru: [Int], tilesInSpace: [Int]) -> Int? {
        let ids = Set(tilesInSpace)
        return mru.first { ids.contains($0) } ?? tilesInSpace.first
    }

    /// A window can't be dragged out of or into a native-fullscreen space.
    public static func moveAllowed(from source: Int, to target: Int, fullscreen: Set<Int>) -> Bool {
        source != target && !fullscreen.contains(source) && !fullscreen.contains(target)
    }

    /// The project capsule needs room; on tiny tiles (many windows in one
    /// space) it's left off — the tooltip still names the window.
    public static func pillFits(_ tile: CGSize) -> Bool {
        tile.width >= 44 && tile.height >= 34
    }
}
