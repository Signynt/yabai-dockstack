import XCTest
@testable import YabaiDockstackKit

final class StackBuilderTests: XCTestCase {
    private func win(_ id: Int, _ app: String, _ idx: Int, _ frame: YRect, focus: Bool = false) -> YabaiWindow {
        YabaiWindow(id: id, pid: id, app: app, title: app, frame: frame, display: 1, space: 1, stackIndex: idx, hasFocus: focus)
    }

    func testGroupsStackedWindowsAndIgnoresUnstacked() {
        let f = YRect(x: 0, y: 25, w: 800, h: 900)
        let other = YRect(x: 800, y: 25, w: 800, h: 900)
        let wins = [
            win(2, "Code", 2, f),
            win(1, "Code", 1, f, focus: true),
            win(3, "Safari", 0, other),   // unstacked -> ignored
        ]
        let stacks = StackBuilder.build(wins)
        XCTAssertEqual(stacks.count, 1)
        let s = stacks[0]
        XCTAssertEqual(s.windows.map { $0.id }, [1, 2])  // sorted by stackIndex
        XCTAssertTrue(s.isFocused)
        XCTAssertEqual(s.frame, f)
    }

    func testSameFrameButStackIndexZeroIsNotAStack() {
        let f = YRect(x: 0, y: 25, w: 800, h: 900)
        let wins = [win(1, "A", 0, f), win(2, "B", 0, f)]
        XCTAssertEqual(StackBuilder.build(wins).count, 0)
    }

    func testSameFrameStacksOnDifferentSpacesGetDistinctKeys() {
        let f = YRect(x: 0, y: 25, w: 800, h: 900)
        func w(_ id: Int, _ space: Int, _ idx: Int) -> YabaiWindow {
            YabaiWindow(id: id, pid: id, app: "A", title: "A", frame: f, display: 1, space: space, stackIndex: idx, hasFocus: false)
        }
        let a = StackBuilder.build([w(1, 1, 1), w(2, 1, 2)])
        let b = StackBuilder.build([w(3, 2, 1), w(4, 2, 2)])
        XCTAssertNotEqual(a.first?.key, b.first?.key)
    }
}
