import XCTest
@testable import YabaiDockstackKit

final class HyperKeyTests: XCTestCase {
    private let userMapping: [String: UInt64] = ["HIDKeyboardModifierMappingSrc": 30064771299,
                                                 "HIDKeyboardModifierMappingDst": 30064771300]
    private let ours: [String: UInt64] = ["HIDKeyboardModifierMappingSrc": 0x700000039,
                                          "HIDKeyboardModifierMappingDst": HyperKeyMapping.f18]

    func testParseHidutilOutput() {
        XCTAssertEqual(HyperKeyMapping.parse("(null)"), [])
        let text = "(\n    {\n    HIDKeyboardModifierMappingDst = 30064771300;\n    HIDKeyboardModifierMappingSrc = 30064771299;\n}\n)"
        XCTAssertEqual(HyperKeyMapping.parse(text), [userMapping])
    }

    func testMergeKeepsUserMappings() {
        XCTAssertEqual(HyperKeyMapping.merged(existing: [userMapping], source: .capsLock), [userMapping, ours])
        XCTAssertEqual(HyperKeyMapping.merged(existing: [userMapping, ours], source: .none), [userMapping])
        XCTAssertEqual(HyperKeyMapping.merged(existing: [ours], source: .rightCommand).count, 1)
        XCTAssertTrue(HyperKeyMapping.hidutilJSON([ours]).contains("\"UserKeyMapping\""))
    }

    func testReducerChordVersusQuickPress() {
        // Modifiers are really pressed on the first hyper down and released on
        // hyper up, so the system's modifier state never gets stuck.
        var r = HyperKeyReducer()
        XCTAssertEqual(r.handle(.hyperDown), .pressModifiers)
        XCTAssertEqual(r.handle(.hyperDown), .swallow)        // autorepeat
        XCTAssertEqual(r.handle(.keyDown), .addHyperFlags)
        XCTAssertEqual(r.handle(.hyperDown), .swallow)        // autorepeat after chord keeps used
        XCTAssertEqual(r.handle(.keyUp), .addHyperFlags)
        XCTAssertEqual(r.handle(.hyperUp), .releaseModifiers) // chord → no quick press
        XCTAssertEqual(r.handle(.hyperDown), .pressModifiers)
        XCTAssertEqual(r.handle(.hyperUp), .quickPress)       // tap alone: release, then act
        XCTAssertEqual(r.handle(.keyDown), .pass)             // not held
        XCTAssertEqual(r.handle(.hyperUp), .swallow)          // stray up while not held
    }

    func testHotkeyHyperAndMeh() {
        XCTAssertEqual(Hotkey.parse("hyper - h")?.mods, [.ctrl, .shift, .alt, .cmd])
        XCTAssertEqual(Hotkey.parse("meh - h")?.mods, [.ctrl, .shift, .alt])
        Hotkey.showHyperSymbol = true
        XCTAssertEqual(Hotkey(mods: [.ctrl, .shift, .alt, .cmd], key: "h").displayString, "✦H")
        Hotkey.showHyperSymbol = false
        XCTAssertEqual(Hotkey(mods: [.ctrl, .shift, .alt, .cmd], key: "h").displayString, "⌃⇧⌥⌘H")
    }

    func testConfigDefaults() {
        let c = AppConfig.load(from: #"{"style":"flag"}"#.data(using: .utf8))
        XCTAssertEqual(c.hyperKey, "none")
        XCTAssertEqual(c.hyperQuickPress, "none")
        XCTAssertTrue(c.hyperIncludeShift)
        XCTAssertFalse(c.hyperShowSymbol)
    }
}
