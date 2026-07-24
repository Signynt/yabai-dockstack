import XCTest
@testable import YabaiDockstackKit

final class SpaceMoverLiftTests: XCTestCase {
    func testLiftDetectedRequiresDrift() {
        let before = YRect(x: 100, y: 50, w: 800, h: 600)
        XCTAssertFalse(SpaceMover.liftDetected(before: before, after: before))
        XCTAssertFalse(SpaceMover.liftDetected(
            before: before, after: YRect(x: 101, y: 51, w: 800, h: 600)))
        XCTAssertTrue(SpaceMover.liftDetected(
            before: before, after: YRect(x: 110, y: 55, w: 800, h: 600)))
        // drift in either axis alone is enough
        XCTAssertTrue(SpaceMover.liftDetected(
            before: before, after: YRect(x: 100, y: 55, w: 800, h: 600)))
    }
}

final class GrabPointPlannerTests: XCTestCase {
    let frame = YRect(x: 100, y: 50, w: 1200, h: 800)

    func testCandidatesStayInTopStripAwayFromCorners() {
        let points = GrabPointPlanner.candidates(frame: frame)
        XCTAssertGreaterThanOrEqual(points.count, 3)
        for p in points {
            XCTAssertEqual(p.y, 58, "8pt below the top edge")
            XCTAssertGreaterThanOrEqual(p.x, 240, "clear of traffic lights (left inset)")
            XCTAssertLessThanOrEqual(p.x, 1210, "clear of right-aligned toolbar buttons")
        }
    }

    func testCandidatesPreferOffCenterAndEndWithCenter() {
        let points = GrabPointPlanner.candidates(frame: frame)
        let center = frame.x + frame.w / 2
        XCTAssertNotEqual(points.first!.x, center, "center (search-bar hot spot) is not tried first")
        XCTAssertEqual(points.last!.x, center, "center remains the last resort")
    }

    func testNarrowWindowFallsBackToCenter() {
        let narrow = YRect(x: 0, y: 0, w: 180, h: 400)
        let points = GrabPointPlanner.candidates(frame: narrow)
        XCTAssertEqual(points.count, 1)
        XCTAssertEqual(points[0].x, 90)
    }

    func testChooseFiltersUnsafeRoles() {
        let center = frame.x + frame.w / 2
        let points = GrabPointPlanner.choose(frame: frame) { p in
            abs(p.x - center) < 1 ? "AXTextField" : "AXStaticText"
        }
        XCTAssertFalse(points.contains { abs($0.x - center) < 1 },
                       "search field at center is skipped")
        XCTAssertFalse(points.isEmpty)
    }

    func testChooseFallsBackWhenEverythingProbesUnsafe() {
        let points = GrabPointPlanner.choose(frame: frame) { _ in "AXButton" }
        XCTAssertEqual(points, GrabPointPlanner.candidates(frame: frame),
                       "all-unsafe probe falls back to the unfiltered list")
    }

    func testUnknownRoleIsTreatedAsSafe() {
        XCTAssertTrue(GrabPointPlanner.isSafe(role: nil))
        XCTAssertTrue(GrabPointPlanner.isSafe(role: "AXStaticText"))
        XCTAssertFalse(GrabPointPlanner.isSafe(role: "AXSearchField"))
        XCTAssertFalse(GrabPointPlanner.isSafe(role: "AXRadioButton"))
    }
}
