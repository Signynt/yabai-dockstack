import AppKit
import CoreGraphics

/// Outcome of a simulated drag walk.
public enum DragWalkOutcome: Equatable {
    /// The window was lifted and the walk ran; `observedAll` is false when some
    /// space transition wasn't observed within the timeout.
    case walked(observedAll: Bool)
    /// No grab attempt lifted the window; the walk was not performed, so the
    /// active space never flicked away and back.
    case neverLifted
}

/// Simulates the native "drag a window's titlebar and press ctrl+arrow" gesture
/// so windows can travel between spaces with SIP fully enabled. Requires the
/// Accessibility permission the app already holds.
public protocol SpaceSimulating {
    /// Tries each grab point in order until one lifts the window. `liftCheck`
    /// reports whether the pressed window is actually following the drag (e.g.
    /// its frame drifted with the jiggle); pass nil to skip verification and
    /// walk blindly after the first point.
    func dragWalk(grabPoints: [CGPoint], direction: ArrowDirection, count: Int,
                  liftCheck: (() -> Bool)?) -> DragWalkOutcome
}

public final class SpaceSimulator: SpaceSimulating {
    /// Per-step ceiling on waiting for the space-switch animation.
    private let stepTimeout: TimeInterval = 0.8
    /// Settle time after each observed switch (animation tail).
    private let settle: TimeInterval = 0.3

    public init() {}

    public func dragWalk(grabPoints: [CGPoint], direction: ArrowDirection, count: Int,
                         liftCheck: (() -> Bool)?) -> DragWalkOutcome {
        let keyCode: CGKeyCode = direction == .left ? 123 : 124
        let source = makeSource()

        func post(_ e: CGEvent?) { e?.post(tap: .cghidEventTap); usleep(25_000) }

        var held: CGPoint?
        for point in grabPoints {
            // Park the cursor on the grab point before pressing — WindowServer
            // tracks the cursor, and a press far from it doesn't start a drag.
            post(CGEvent(mouseEventSource: source, mouseType: .mouseMoved,
                         mouseCursorPosition: point, mouseButton: .left))
            usleep(120_000)
            guard let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown,
                                     mouseCursorPosition: point, mouseButton: .left) else { continue }
            down.post(tap: .cghidEventTap)
            // Real dragged events past the drag threshold actually lift the window;
            // a tiny jiggle reads as a click and the window stays behind.
            var last = point
            for i in 1...5 {
                last = CGPoint(x: point.x + Double(i) * 2, y: point.y + Double(i))
                post(CGEvent(mouseEventSource: source, mouseType: .leftMouseDragged,
                             mouseCursorPosition: last, mouseButton: .left))
            }
            usleep(150_000)
            if liftCheck?() ?? true {
                held = last
                break
            }
            // Grab missed. Release back at the origin so the net drag is zero
            // (a drop elsewhere could trigger yabai's drop action), then retry.
            post(CGEvent(mouseEventSource: source, mouseType: .leftMouseDragged,
                         mouseCursorPosition: point, mouseButton: .left))
            CGEvent(mouseEventSource: source, mouseType: .leftMouseUp,
                    mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
            usleep(120_000)
        }
        guard let dragPoint = held else { return .neverLifted }

        defer {
            CGEvent(mouseEventSource: source, mouseType: .leftMouseUp,
                    mouseCursorPosition: dragPoint, mouseButton: .left)?.post(tap: .cghidEventTap)
        }
        var allObserved = true
        for _ in 0..<count {
            let waiter = SpaceChangeWaiter()
            postCtrlKey(keyCode)
            if !waiter.wait(timeout: stepTimeout) { allObserved = false }
            Thread.sleep(forTimeInterval: settle)
        }
        return .walked(observedAll: allObserved)
    }

    /// HID-state source that also suppresses hardware *mouse* events for a short
    /// window after each synthetic post — a stray trackpad touch mid-sequence
    /// otherwise breaks the drag before the window is lifted. Keyboard events
    /// stay permitted so real modifier releases keep reaching the system.
    private func makeSource() -> CGEventSource? {
        let source = CGEventSource(stateID: .hidSystemState)
        source?.localEventsSuppressionInterval = 0.35
        source?.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalKeyboardEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval)
        return source
    }

    /// Posts ctrl+arrow the way the hardware does: a flagsChanged for the
    /// control press, the arrow key carrying the Fn/NumericPad bits physical
    /// arrow keys always have (the symbolic hotkey won't match without them),
    /// then the control release.
    private func postCtrlKey(_ keyCode: CGKeyCode) {
        let source = makeSource()
        if let e = CGEvent(keyboardEventSource: source, virtualKey: 59, keyDown: true) {
            e.type = .flagsChanged
            e.flags = .maskControl
            e.post(tap: .cghidEventTap)
        }
        usleep(30_000)
        for keyDown in [true, false] {
            guard let e = CGEvent(keyboardEventSource: source, virtualKey: keyCode,
                                  keyDown: keyDown) else { continue }
            e.flags = [.maskControl, .maskSecondaryFn, .maskNumericPad]
            e.post(tap: .cghidEventTap)
            usleep(30_000)
        }
        if let e = CGEvent(keyboardEventSource: source, virtualKey: 59, keyDown: false) {
            e.type = .flagsChanged
            e.flags = []
            e.post(tap: .cghidEventTap)
        }
    }
}

/// Blocks a background thread until macOS reports an active-space change.
/// The notification arrives on the main run loop, which stays free because
/// SpaceMover runs on its own serial queue.
final class SpaceChangeWaiter {
    private let semaphore = DispatchSemaphore(value: 0)
    private var token: NSObjectProtocol?

    init() {
        token = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil, queue: nil) { [semaphore] _ in semaphore.signal() }
    }

    /// Returns true if the space change was observed within `timeout`.
    func wait(timeout: TimeInterval) -> Bool {
        let observed = semaphore.wait(timeout: .now() + timeout) == .success
        if let token { NSWorkspace.shared.notificationCenter.removeObserver(token) }
        self.token = nil
        return observed
    }
}
