import Foundation

/// Moves a window to a space on drop (switcher / window strip), then follows it:
/// with the scripting addition via the bundled moveWindowToSpace.sh (focuses and
/// re-tiles), otherwise SpaceMover's focus-and-walk.
public final class WindowSpaceMover {
    private let client: YabaiClient
    private let spaceMover: SpaceMover
    private let scriptsDir: String
    private let saAvailable: () -> Bool
    private let queue = DispatchQueue(label: "yabai-dockstack.window-space-mover")

    public init(client: YabaiClient, spaceMover: SpaceMover, scriptsDir: String,
                saAvailable: @escaping () -> Bool = SAProbe.current) {
        self.client = client
        self.spaceMover = spaceMover
        self.scriptsDir = scriptsDir
        self.saAvailable = saAvailable
    }

    public func move(windowId: Int, toSpace space: Int) {
        queue.async { [self] in
            // Re-validate: the window may have closed since the drag began.
            guard let window = client.queryWindows().first(where: { $0.id == windowId }) else { return }
            switch MoveRouting.decide(windowSpace: window.space, target: space, saAvailable: saAvailable()) {
            case .noop:
                return
            case .script:
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/bin/sh")
                p.arguments = [(scriptsDir as NSString).appendingPathComponent("moveWindowToSpace.sh"),
                               String(windowId), String(space)]
                p.standardOutput = FileHandle.nullDevice
                p.standardError = FileHandle.nullDevice
                do { try p.run(); p.waitUntilExit() } catch {
                    NSLog("yabai-dockstack: moveWindowToSpace.sh failed: \(error)")
                }
            case .sipFree:
                let outcome = spaceMover.moveWindow(id: windowId, toSpace: space)
                if outcome != .moved { NSLog("yabai-dockstack: drag-to-space \(outcome)") }
            }
        }
    }
}
