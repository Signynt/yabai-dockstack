import XCTest
@testable import YabaiDockstackKit

final class StackReorderPlannerTests: XCTestCase {
    func testMoveDownIsAdjacentSwaps() {
        XCTAssertEqual(StackReorderPlanner.swaps(ids: [1, 2, 3, 4], from: 0, to: 2),
                       [SwapStep(a: 1, b: 2), SwapStep(a: 1, b: 3)])
    }

    func testMoveUpIsAdjacentSwaps() {
        XCTAssertEqual(StackReorderPlanner.swaps(ids: [1, 2, 3, 4], from: 3, to: 1),
                       [SwapStep(a: 4, b: 3), SwapStep(a: 4, b: 2)])
    }

    func testNoOpAndOutOfRange() {
        XCTAssertEqual(StackReorderPlanner.swaps(ids: [1, 2, 3], from: 1, to: 1), [])
        XCTAssertEqual(StackReorderPlanner.swaps(ids: [1, 2, 3], from: 5, to: 0), [])
        XCTAssertEqual(StackReorderPlanner.swaps(ids: [1, 2, 3], from: 0, to: 3), [])
    }

    func testDropIndexClamps() {
        XCTAssertEqual(StackReorderPlanner.dropIndex(offsetFromTop: 70, cell: 32, count: 3), 2)
        XCTAssertEqual(StackReorderPlanner.dropIndex(offsetFromTop: -5, cell: 32, count: 3), 0)
        XCTAssertEqual(StackReorderPlanner.dropIndex(offsetFromTop: 500, cell: 32, count: 3), 2)
    }

    func testConfigDefaultOn() {
        XCTAssertTrue(AppConfig.load(from: #"{"style":"flag"}"#.data(using: .utf8)).indicatorDragReorder)
    }
}
