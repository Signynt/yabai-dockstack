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

    /// Fake yabai that logs its arguments; `--focus` exits `focusExit`.
    private func loggingYabai(focusExit: Int) throws -> (path: String, log: String) {
        let dir = NSTemporaryDirectory() + "fy-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let log = dir + "/log", path = dir + "/yabai"
        let script = """
        #!/bin/sh
        echo "$*" >> \(log)
        case "$*" in
          *"--windows --window"*) echo '{"id":7,"pid":1,"app":"A","frame":{"x":0,"y":0,"w":1,"h":1},"display":1,"space":2,"stack-index":0,"has-focus":true}' ;;
          *query*--windows*) echo '[{"id":7,"pid":1,"app":"A","frame":{"x":0,"y":0,"w":1,"h":1},"display":1,"space":2,"stack-index":0,"has-focus":false}]' ;;
          *--focus*) exit \(focusExit) ;;
        esac
        """
        try script.write(toFile: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        return (path, log)
    }

    func testScriptingAdditionPathMovesByIdWithTheAppsYabai() throws {
        let (path, log) = try loggingYabai(focusExit: 0)
        let client = YabaiClient(yabaiPath: path)
        WindowSpaceMover(client: client, spaceMover: SpaceMover(client: client), saAvailable: { true })
            .moveNow(windowId: 7, toSpace: 3)
        let calls = try String(contentsOfFile: log, encoding: .utf8)
        XCTAssertTrue(calls.contains("-m window 7 --space 3"), calls)
    }

    func testScriptingAdditionPathAbortsWhenFocusFails() throws {
        let (path, log) = try loggingYabai(focusExit: 1)
        let client = YabaiClient(yabaiPath: path)
        WindowSpaceMover(client: client, spaceMover: SpaceMover(client: client), saAvailable: { true })
            .moveNow(windowId: 7, toSpace: 3)
        let calls = try String(contentsOfFile: log, encoding: .utf8)
        XCTAssertFalse(calls.contains("--space"), calls)  // never sends the focused window away
    }

    func testScriptingAdditionNoFollowMoveDoesNotFocus() throws {
        let (path, log) = try loggingYabai(focusExit: 0)
        let client = YabaiClient(yabaiPath: path)
        WindowSpaceMover(client: client, spaceMover: SpaceMover(client: client), saAvailable: { true })
            .moveNow(windowId: 7, toSpace: 3, follow: false)
        let calls = try String(contentsOfFile: log, encoding: .utf8)
        XCTAssertTrue(calls.contains("-m window 7 --space 3"), calls)
        XCTAssertFalse(calls.contains("--focus"), calls)
    }

    /// Fake yabai with windows 21, 22 on space 2 and 31 on space 3.
    private func swapYabai() throws -> (path: String, log: String) {
        let dir = NSTemporaryDirectory() + "fy-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let log = dir + "/log", path = dir + "/yabai"
        func w(_ id: Int, _ space: Int) -> String {
            #"{"id":\#(id),"pid":1,"app":"A","frame":{"x":0,"y":0,"w":1,"h":1},"display":1,"space":\#(space),"stack-index":0,"has-focus":false}"#
        }
        let script = """
        #!/bin/sh
        echo "$*" >> \(log)
        case "$*" in
          *query*--windows*) echo '[\(w(21, 2)),\(w(22, 2)),\(w(31, 3))]' ;;
          *query*--spaces*) echo '[{"index":2,"display":1},{"index":3,"display":1}]' ;;
        esac
        """
        try script.write(toFile: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        return (path, log)
    }

    func testSpaceSwapMovesBothSidesWithScriptingAddition() throws {
        let (path, log) = try swapYabai()
        let client = YabaiClient(yabaiPath: path)
        WindowSpaceMover(client: client, spaceMover: SpaceMover(client: client), saAvailable: { true })
            .swapNow(2, 3)
        let calls = try String(contentsOfFile: log, encoding: .utf8)
        for expected in ["window 21 --space 3", "window 22 --space 3", "window 31 --space 2"] {
            XCTAssertTrue(calls.contains(expected), calls)
        }
    }

    func testSpaceSwapIsInertWithoutScriptingAddition() throws {
        let (path, log) = try swapYabai()
        let client = YabaiClient(yabaiPath: path)
        WindowSpaceMover(client: client, spaceMover: SpaceMover(client: client), saAvailable: { false })
            .swapNow(2, 3)
        let calls = (try? String(contentsOfFile: log, encoding: .utf8)) ?? ""
        XCTAssertNil(calls.range(of: #"--space \d"#, options: .regularExpression), calls)
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
