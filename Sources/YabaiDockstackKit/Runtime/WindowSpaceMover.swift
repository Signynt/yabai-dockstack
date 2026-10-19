import Foundation

/// Moves a window to a space on drop (switcher / window strip): with the
/// scripting addition via yabai directly (following it there or not),
/// otherwise SpaceMover's focus-and-walk, which always ends on the target.
/// Also swaps two spaces' windows (SA only). Runs on SpaceMover's queue so
/// moves never overlap.
public final class WindowSpaceMover {
    private let client: YabaiClient
    private let spaceMover: SpaceMover
    private let saAvailable: () -> Bool

    public init(client: YabaiClient, spaceMover: SpaceMover,
                saAvailable: @escaping () -> Bool = SAProbe.current) {
        self.client = client
        self.spaceMover = spaceMover
        self.saAvailable = saAvailable
    }

    /// `completion` runs on main once the move is done.
    public func move(windowId: Int, toSpace space: Int, follow: Bool = true,
                     completion: (() -> Void)? = nil) {
        spaceMover.enqueue { [self] in
            moveNow(windowId: windowId, toSpace: space, follow: follow)
            if let completion { DispatchQueue.main.async(execute: completion) }
        }
    }

    /// Synchronous; blocks for the SIP-free walk. `follow` only matters with
    /// the SA: false leaves focus (and the current space) alone.
    public func moveNow(windowId: Int, toSpace space: Int, follow: Bool = true) {
        // Re-validate: the window may have closed since the drag began.
        guard let window = client.queryWindows().first(where: { $0.id == windowId }) else { return }
        switch MoveRouting.decide(windowSpace: window.space, target: space, saAvailable: saAvailable()) {
        case .noop:
            return
        case .script where !follow:
            client.moveToSpace(windowId: windowId, space: space)
            client.balance(space: window.space)
            client.balance(space: space)
        case .script:
            // Uses the app's own yabai path (a launchd-started app has no
            // Homebrew on PATH) and the window id, never "the focused window":
            // if it can't be focused, nothing is sent away.
            guard client.focus(windowId: windowId) else {
                NSLog("yabai-dockstack: drag-to-space aborted, window \(windowId) can't be focused")
                return
            }
            client.moveToSpace(windowId: windowId, space: space)
            client.focus(windowId: windowId)
            client.balance(space: window.space)
            client.balance(space: space)
        case .sipFree:
            let outcome = spaceMover.moveWindow(id: windowId, toSpace: space)
            if outcome != .moved { NSLog("yabai-dockstack: drag-to-space \(outcome)") }
        }
    }

    /// Swaps all windows of spaces `a` and `b` (scripting addition only;
    /// otherwise nothing happens). `completion` runs on main afterwards.
    public func swapSpaces(_ a: Int, _ b: Int, completion: (() -> Void)? = nil) {
        spaceMover.enqueue { [self] in
            swapNow(a, b)
            if let completion { DispatchQueue.main.async(execute: completion) }
        }
    }

    /// Synchronous. Both lists are taken before anything moves.
    public func swapNow(_ a: Int, _ b: Int) {
        let fullscreen = Set(client.querySpacesInfo().filter(\.isNativeFullscreen).map(\.index))
        guard SpacesInteraction.swapAllowed(source: a, target: b, saAvailable: saAvailable(),
                                            fullscreen: fullscreen) else { return }
        let windows = SpacesModel.displayableWindows(client.queryWindows())
        let fromA = SpacesModel.windowIDsToMove(from: a, to: b, windows: windows)
        let fromB = SpacesModel.windowIDsToMove(from: b, to: a, windows: windows)
        for id in fromA { client.moveToSpace(windowId: id, space: b) }
        for id in fromB { client.moveToSpace(windowId: id, space: a) }
        client.balance(space: a)
        client.balance(space: b)
    }
}
