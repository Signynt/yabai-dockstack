import Foundation

/// Moves a window to a space on drop (switcher / window strip), then follows it:
/// with the scripting addition via yabai directly, otherwise SpaceMover's
/// focus-and-walk. Runs on SpaceMover's queue so moves never overlap.
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

    public func move(windowId: Int, toSpace space: Int) {
        spaceMover.enqueue { [self] in moveNow(windowId: windowId, toSpace: space) }
    }

    /// Synchronous; blocks for the SIP-free walk.
    public func moveNow(windowId: Int, toSpace space: Int) {
        // Re-validate: the window may have closed since the drag began.
        guard let window = client.queryWindows().first(where: { $0.id == windowId }) else { return }
        switch MoveRouting.decide(windowSpace: window.space, target: space, saAvailable: saAvailable()) {
        case .noop:
            return
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
}
