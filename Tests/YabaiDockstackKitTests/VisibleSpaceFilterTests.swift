import XCTest
@testable import YabaiDockstackKit

final class VisibleSpaceFilterTests: XCTestCase {
    private func win(_ id: Int, space: Int, visible: Bool) -> YabaiWindow {
        YabaiWindow(id: id, pid: id, app: "A", title: "t",
                    frame: YRect(x: 0, y: 0, w: 1, h: 1),
                    display: 1, space: space, stackIndex: 1, hasFocus: false,
                    isVisible: visible)
    }

    func testKeepsAllWindowsOnVisibleSpacesIncludingOccludedStackMembers() {
        // space 11 is visible (one member visible, others occluded false);
        // space 5 is not visible at all.
        let wins = [
            win(1, space: 11, visible: true),   // active stack member
            win(2, space: 11, visible: false),  // occluded stack member
            win(3, space: 5, visible: false),   // window on a hidden space
        ]
        let kept = VisibleSpaceFilter.apply(wins).map { $0.id }
        XCTAssertEqual(Set(kept), [1, 2])  // both space-11 windows kept, space-5 dropped
    }

    func testReturnsAllWhenNothingVisible() {
        let wins = [win(1, space: 5, visible: false)]
        XCTAssertEqual(VisibleSpaceFilter.apply(wins).count, 1)  // safety fallback
    }

    func testStickyWindowDoesNotMarkItsHiddenSpaceVisible() {
        // A sticky window shows on every space but yabai reports it on space 2
        // (hidden) with is-visible == true; space 1 is the one actually shown.
        let sticky = YabaiWindow(id: 9, pid: 9, app: "S", title: "t",
                                 frame: YRect(x: 0, y: 0, w: 1, h: 1),
                                 display: 1, space: 2, stackIndex: 0, hasFocus: false,
                                 isVisible: true, isFloating: true, isSticky: true)
        let wins = [win(1, space: 1, visible: true), win(2, space: 2, visible: false), sticky]
        XCTAssertEqual(Set(VisibleSpaceFilter.apply(wins).map { $0.id }), [1])
    }
}
