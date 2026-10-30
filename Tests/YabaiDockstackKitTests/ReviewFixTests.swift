import XCTest
import CoreGraphics
@testable import YabaiDockstackKit

final class ReviewFixTests: XCTestCase {
    func testHyperHealthStopsWhenAccessibilityRevokedOrTapMissing() {
        XCTAssertEqual(HyperKeyPlan.health(configured: .capsLock, ax: true, running: false), .start)
        XCTAssertEqual(HyperKeyPlan.health(configured: .capsLock, ax: false, running: true), .stop)
        XCTAssertEqual(HyperKeyPlan.health(configured: .capsLock, ax: true, running: true), .keep)
        XCTAssertEqual(HyperKeyPlan.health(configured: .none, ax: true, running: false), .keep)
        // The source key is only remapped once the tap is actually running.
        XCTAssertEqual(HyperKeyPlan.mapping(configured: .capsLock, tapRunning: false), HyperSource.none)
        XCTAssertEqual(HyperKeyPlan.mapping(configured: .capsLock, tapRunning: true), .capsLock)
    }

    func testUnparseableHidutilOutputIsNotTreatedAsEmpty() {
        XCTAssertNil(HyperKeyMapping.parse("hidutil: error"))
        XCTAssertEqual(HyperKeyMapping.parse("(null)"), [])
        XCTAssertEqual(HyperKeyMapping.parse("(\n)"), [])
    }

    func testMissedHyperUpReleasesModifiers() {
        var r = HyperKeyReducer()
        _ = r.handle(.hyperDown)
        _ = r.handle(.keyDown)
        XCTAssertEqual(r.handle(.hyperFoundUp), .releaseModifiers)
        XCTAssertEqual(r.handle(.hyperUp), .swallow)
        _ = r.handle(.hyperDown)
        XCTAssertEqual(r.handle(.hyperFoundUp), .releaseModifiers)  // never a quick press
        XCTAssertEqual(r.handle(.hyperFoundUp), .swallow)
    }

    func testHoverDoesNotReopenAfterMenuCloses() {
        var h = HoverOpenLogic()
        XCTAssertTrue(h.pointer(inside: true))           // arm timer
        h.menuClosed(pointerInside: true)                 // clicked open, clicked closed
        XCTAssertFalse(h.timerFired(pointerInside: true)) // stale timer must not reopen
        XCTAssertFalse(h.pointer(inside: true))           // still suppressed
        _ = h.pointer(inside: false)
        XCTAssertTrue(h.pointer(inside: true))
        XCTAssertTrue(h.timerFired(pointerInside: true))
        XCTAssertTrue(h.pointer(inside: false) == false)
        XCTAssertFalse(h.timerFired(pointerInside: false))
    }

    func testStripRerendersWhenScreenFrameChanges() {
        let s = WindowStripModel.DisplayStrip(display: 1, hidden: false, sections: [])
        let f = CGRect(x: 0, y: 0, width: 100, height: 100)
        XCTAssertTrue(WindowStripModel.needsRender(cached: nil, strip: s, frame: f))
        XCTAssertFalse(WindowStripModel.needsRender(cached: .init(strip: s, frame: f), strip: s, frame: f))
        XCTAssertTrue(WindowStripModel.needsRender(cached: .init(strip: s, frame: f), strip: s,
                                                   frame: f.offsetBy(dx: 10, dy: 0)))
    }

    func testStatusIconMirroredOntoOtherScreens() {
        // Button lives on the active display's menu bar; other menu bars show it
        // at the same distance from their right/top edges.
        let icon = CGRect(x: 2422, y: 2171, width: 36, height: 24)
        let active = CGRect(x: 978, y: 1117, width: 1920, height: 1080)
        let left = CGRect(x: -942, y: 1117, width: 1920, height: 1080)
        let laptop = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        XCTAssertEqual(HoverOpenLogic.mirrored(icon, from: active, to: left), CGRect(x: 502, y: 2157, width: 36, height: 40))
        XCTAssertEqual(HoverOpenLogic.mirrored(icon, from: active, to: laptop), CGRect(x: 1252, y: 1077, width: 36, height: 40))
        XCTAssertEqual(HoverOpenLogic.mirrored(icon, from: active, to: active), CGRect(x: 2422, y: 2157, width: 36, height: 40))
    }
}
