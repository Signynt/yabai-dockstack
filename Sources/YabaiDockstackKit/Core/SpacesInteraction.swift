import CoreGraphics

/// What clicking an empty part of a space card does.
public enum CardClick: Equatable {
    case focusSpace(Int)
    case focusWindow(Int)
    case nothing
}

/// Drop / swap / click rules of the Spaces-style search switcher.
public enum SpacesInteraction {
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
}
