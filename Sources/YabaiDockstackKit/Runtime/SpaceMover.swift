import Foundation

/// Executes SIP-free window-to-space moves: parses socket commands, plans via
/// SpaceTravelPlanner, and performs the steps (AX display hop + simulated drag).
/// The scripts only route here when the scripting addition is unavailable.
public final class SpaceMover {
    private let client: YabaiClient
    private let simulator: SpaceSimulating
    private let probe: GrabPointProbing
    private let queue = DispatchQueue(label: "yabai-dockstack.space-mover")

    public init(client: YabaiClient, simulator: SpaceSimulating = SpaceSimulator(),
                probe: GrabPointProbing = AXGrabPointProbe()) {
        self.client = client
        self.simulator = simulator
        self.probe = probe
    }

    /// A grab counts as lifted when the jiggle visibly moved the window: the
    /// jiggle travels (10, 5), so ≥4 pt of drift separates a real lift from
    /// query noise while tolerating partial frames.
    public static func liftDetected(before: YRect, after: YRect) -> Bool {
        abs(after.x - before.x) + abs(after.y - before.y) >= 4
    }

    /// Wire form: "move-space prev" | "move-space next" | "move-space 4".
    /// Unknown commands are ignored. Returns immediately; work runs serially
    /// off the main thread (the walk blocks for ~0.3 s per step).
    public func handle(command: String) {
        let parts = command.split(separator: " ").map(String.init)
        guard parts.count == 2, parts[0] == "move-space",
              let target = SpaceTarget.parse(parts[1]) else { return }
        queue.async { [self] in moveFocusedWindow(to: target) }
    }

    private func moveFocusedWindow(to target: SpaceTarget) {
        guard let window = client.queryFocusedWindow() else {
            NSLog("yabai-dockstack: move-space aborted, no focused window")
            return
        }
        guard let plan = SpaceTravelPlanner.plan(
            target: target, windowSpace: window.space, windowDisplay: window.display,
            spaces: client.querySpacesInfo(), displays: client.queryDisplaysInfo()) else {
            NSLog("yabai-dockstack: move-space aborted, planner returned nil")
            return
        }

        // A tiled window can't be repositioned across displays ("cannot move a
        // managed window"), so float it for the journey and re-tile on arrival.
        let hopsDisplays = plan.steps.contains {
            if case .moveToDisplay = $0 { return true } else { return false }
        }
        let floatForTrip = hopsDisplays && !window.isFloating
        if floatForTrip {
            client.toggleFloat(windowId: window.id)
            Thread.sleep(forTimeInterval: 0.1)
        }
        defer {
            if floatForTrip { client.toggleFloat(windowId: window.id) }
            client.focus(windowId: window.id)
            client.balance(space: plan.sourceSpace)
            client.balance(space: plan.targetSpace)
        }

        for step in plan.steps {
            switch step {
            case .moveToDisplay(_, let x, let y):
                client.moveWindow(id: window.id, absX: x, absY: y)
                client.focus(windowId: window.id)  // activates the target display
                Thread.sleep(forTimeInterval: 0.15)
            case .arrowWalk(let direction, let count):
                // Re-query: the frame moved if a display hop happened.
                guard let fresh = client.queryFocusedWindow(), fresh.id == window.id else {
                    NSLog("yabai-dockstack: move-space aborted, focused window changed before arrow walk")
                    return
                }
                // Pick drag points along the top strip, AX-probing each spot to
                // skip controls that would activate (search fields, buttons)
                // instead of lifting the window.
                let baseline = fresh.frame
                let grabPoints = GrabPointPlanner.choose(frame: baseline,
                                                         roleAt: { [probe] in probe.role(at: $0) })
                let outcome = simulator.dragWalk(
                    grabPoints: grabPoints, direction: direction, count: count,
                    liftCheck: { [client] in
                        guard let now = client.queryFocusedWindow(), now.id == fresh.id else { return false }
                        return SpaceMover.liftDetected(before: baseline, after: now.frame)
                    })
                switch outcome {
                case .neverLifted:
                    NSLog("yabai-dockstack: move-space aborted, no grab attempt lifted the window")
                    return
                case .walked(let observedAll):
                    if !observedAll {
                        NSLog("yabai-dockstack: move-space walk not fully observed")
                    }
                }
            }
        }
    }
}
