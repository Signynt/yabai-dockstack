import XCTest
@testable import YabaiDockstackKit

final class DragToSpaceTests: XCTestCase {
    func testSAProbe() {
        XCTAssertFalse(SAProbe.available(csrutilOutput: "System Integrity Protection status: enabled."))
        XCTAssertTrue(SAProbe.available(csrutilOutput: "System Integrity Protection status: disabled."))
        XCTAssertTrue(SAProbe.available(csrutilOutput: "System Integrity Protection status: enabled (Custom Configuration).\n\nConfiguration:\n"))
        XCTAssertFalse(SAProbe.available(csrutilOutput: nil))
        XCTAssertFalse(SAProbe.available(csrutilOutput: ""))
    }

    func testMoveRouting() {
        XCTAssertEqual(MoveRouting.decide(windowSpace: 3, target: 3, saAvailable: true), .noop)
        XCTAssertEqual(MoveRouting.decide(windowSpace: 2, target: 5, saAvailable: true), .script)
        XCTAssertEqual(MoveRouting.decide(windowSpace: 2, target: 5, saAvailable: false), .sipFree)
    }

    func testBindingUpdate() {
        let hk = Hotkey(mods: [.ctrl, .shift, .alt, .cmd], key: "tab")
        let set = ShortcutBindings.setting([], action: "open-window-switcher", hotkey: hk)
        XCTAssertEqual(set, [ShortcutBinding(actionID: "open-window-switcher", enabled: true, hotkey: hk)])
        let cleared = ShortcutBindings.setting(set, action: "open-window-switcher", hotkey: nil)
        XCTAssertEqual(cleared.first?.enabled, false)
        let other = ShortcutBinding(actionID: "open-window-menu", enabled: true, hotkey: hk)
        XCTAssertEqual(ShortcutBindings.setting([other], action: "open-window-switcher", hotkey: hk).count, 2)
    }

    func testUnfocusableWindowIsNotWalked() throws {
        let path = NSTemporaryDirectory() + "fake-yabai-\(UUID().uuidString)"
        try "#!/bin/sh\ncase \"$*\" in *--focus*) exit 1 ;; esac\n".write(toFile: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        let sim = RecordingSimulator()
        let mover = SpaceMover(client: YabaiClient(yabaiPath: path), simulator: sim, probe: NoProbe())
        XCTAssertEqual(mover.moveWindow(id: 7, toSpace: 3), .focusFailed)
        XCTAssertEqual(sim.walks, 0)
    }
}

final class RecordingSimulator: SpaceSimulating {
    var walks = 0
    func dragWalk(grabPoints: [CGPoint], direction: ArrowDirection, count: Int,
                  liftCheck: (() -> Bool)?) -> DragWalkOutcome {
        walks += 1
        return .walked(observedAll: true)
    }
}

struct NoProbe: GrabPointProbing {
    func role(at point: CGPoint) -> String? { nil }
}
