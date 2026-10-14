/// Keeps only windows that live on a *currently visible* space.
///
/// A yabai stack shows only its active member on top, so the occluded members
/// report `is-visible == false`. We therefore can't filter windows by their own
/// visibility — instead we find the set of spaces that contain at least one
/// visible window (i.e. the spaces currently shown on each display) and keep all
/// windows on those spaces. This drops stacks that live on other spaces (so they
/// don't bleed across spaces) and avoids drawing over native-fullscreen spaces.
///
/// Sticky windows are ignored when deciding visibility: they are visible on every
/// space yet yabai reports one (often hidden) `space` for them, which would mark
/// that hidden space as visible and draw its stacks over the current one.
public enum VisibleSpaceFilter {
    public static func apply(_ windows: [YabaiWindow]) -> [YabaiWindow] {
        let visibleSpaces = Set(windows.filter { $0.isVisible && !$0.isSticky }.map { $0.space })
        guard !visibleSpaces.isEmpty else { return windows }  // safety: don't hide everything
        return windows.filter { visibleSpaces.contains($0.space) }
    }
}
