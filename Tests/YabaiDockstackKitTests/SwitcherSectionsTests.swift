import XCTest
import CoreGraphics
@testable import YabaiDockstackKit

final class SwitcherSectionsTests: XCTestCase {
    private func item(_ id: Int, space: Int, display: Int = 1) -> SwitcherItem {
        SwitcherItem(id: id, pid: id, app: "A", title: "t\(id)", space: space, display: display, hasFocus: false)
    }
    private let spaces = [SpaceInfo(index: 1, display: 1, isVisible: true),
                          SpaceInfo(index: 2, display: 1, isVisible: false),
                          SpaceInfo(index: 3, display: 2, isVisible: true)]

    func testBuildIncludesEmptySpacesInDisplayOrder() {
        let s = SwitcherSections.build(items: [item(9, space: 3, display: 2), item(5, space: 1), item(4, space: 1)],
                                       spaces: spaces, labels: [3: "web"])
        XCTAssertEqual(s.map(\.space), [1, 2, 3])
        XCTAssertEqual(s.map(\.name), ["D1 · Space 1", "D1 · Space 2", "D2 · web"])
        XCTAssertEqual(s[0].items.map(\.id), [5, 4])  // incoming (MRU) order kept
        XCTAssertTrue(s[1].items.isEmpty)
    }

    func testSingleDisplayNamesHaveNoPrefix() {
        let one = [SpaceInfo(index: 1, display: 1, isVisible: true), SpaceInfo(index: 2, display: 1, isVisible: false)]
        XCTAssertEqual(SwitcherSections.build(items: [], spaces: one, labels: [:]).map(\.name), ["Space 1", "Space 2"])
    }

    func testLayout() {
        let l = SwitcherSections.layout(counts: [3, 0, 1], columns: 2, cell: CGSize(width: 100, height: 50),
                                        gap: 10, headerHeight: 20, emptyHeight: 30)
        XCTAssertEqual(l.headers.map(\.minY), [0, 140, 200])
        XCTAssertEqual(l.cells, [CGRect(x: 0, y: 20, width: 100, height: 50),
                                 CGRect(x: 110, y: 20, width: 100, height: 50),
                                 CGRect(x: 0, y: 80, width: 100, height: 50),
                                 CGRect(x: 0, y: 220, width: 100, height: 50)])
        XCTAssertEqual(l.size, CGSize(width: 210, height: 270))
    }

    func testVerticalNeighborAndSectionHit() {
        let l = SwitcherSections.layout(counts: [3, 0, 1], columns: 2, cell: CGSize(width: 100, height: 50),
                                        gap: 10, headerHeight: 20, emptyHeight: 30)
        XCTAssertEqual(SwitcherSections.verticalNeighbor(of: 2, up: true, cells: l.cells), 0)
        XCTAssertEqual(SwitcherSections.verticalNeighbor(of: 2, up: false, cells: l.cells), 3)
        XCTAssertNil(SwitcherSections.verticalNeighbor(of: 3, up: false, cells: l.cells))
        XCTAssertEqual(SwitcherSections.verticalNeighbor(of: 1, up: false, cells: l.cells), 2)
        XCTAssertEqual(SwitcherSections.section(at: CGPoint(x: 50, y: 160), layout: l), 1)  // empty section body
        XCTAssertEqual(SwitcherSections.section(at: CGPoint(x: 50, y: 100), layout: l), 0)
        XCTAssertEqual(SwitcherSections.section(at: CGPoint(x: 50, y: 260), layout: l), 2)
        XCTAssertNil(SwitcherSections.section(at: CGPoint(x: 50, y: -5), layout: l))
        XCTAssertNil(SwitcherSections.section(at: CGPoint(x: 50, y: 400), layout: l))
    }
}
