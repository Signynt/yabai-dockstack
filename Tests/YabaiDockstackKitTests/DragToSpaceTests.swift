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
}
