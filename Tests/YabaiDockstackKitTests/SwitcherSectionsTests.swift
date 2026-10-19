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

    private func layout(maxWidth: Double) -> SectionLayout {
        SwitcherSections.layout(counts: [3, 0, 1], columns: 2, cell: CGSize(width: 100, height: 50),
                                gap: 10, headerHeight: 20, emptyHeight: 30, maxWidth: maxWidth)
    }

    func testFlowLayoutOneRow() {
        let l = layout(maxWidth: 1000)
        XCTAssertEqual(l.sections, [CGRect(x: 0, y: 0, width: 210, height: 130),
                                    CGRect(x: 230, y: 0, width: 100, height: 50),
                                    CGRect(x: 350, y: 0, width: 100, height: 70)])
        XCTAssertEqual(l.cells, [CGRect(x: 0, y: 20, width: 100, height: 50),
                                 CGRect(x: 110, y: 20, width: 100, height: 50),
                                 CGRect(x: 0, y: 80, width: 100, height: 50),
                                 CGRect(x: 350, y: 20, width: 100, height: 50)])
        XCTAssertEqual(l.size, CGSize(width: 450, height: 130))
    }

    func testFlowLayoutWraps() {
        let l = layout(maxWidth: 300)
        XCTAssertEqual(l.sections.map(\.origin), [CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 150), CGPoint(x: 120, y: 150)])
        XCTAssertEqual(l.size, CGSize(width: 220, height: 220))
    }

    func testVerticalNeighborAndSectionHit() {
        let l = layout(maxWidth: 300)
        XCTAssertEqual(SwitcherSections.verticalNeighbor(of: 2, up: true, cells: l.cells), 0)
        XCTAssertEqual(SwitcherSections.verticalNeighbor(of: 2, up: false, cells: l.cells), 3)
        XCTAssertNil(SwitcherSections.verticalNeighbor(of: 3, up: false, cells: l.cells))
        XCTAssertEqual(SwitcherSections.section(at: CGPoint(x: 50, y: 160), layout: l), 1)  // empty section
        XCTAssertEqual(SwitcherSections.section(at: CGPoint(x: 130, y: 180), layout: l), 2)
        XCTAssertEqual(SwitcherSections.section(at: CGPoint(x: 50, y: 100), layout: l), 0)
        XCTAssertNil(SwitcherSections.section(at: CGPoint(x: 250, y: 160), layout: l))      // gap
        XCTAssertNil(SwitcherSections.section(at: CGPoint(x: 50, y: 400), layout: l))
    }

    func testFullscreenSpacesAreNotDropTargets() {
        let sp = [SpaceInfo(index: 1, display: 1, isVisible: true),
                  SpaceInfo(index: 2, display: 1, isVisible: false, isNativeFullscreen: true)]
        XCTAssertEqual(SwitcherSections.build(items: [], spaces: sp, labels: [:]).map(\.space), [1])
    }

    func testHiddenScrolledCardsAreNotDropTargets() {
        let l = layout(maxWidth: 1000)
        let visible = CGRect(x: 0, y: 0, width: 450, height: 60)
        XCTAssertEqual(SwitcherSections.section(at: CGPoint(x: 50, y: 40), layout: l, visible: visible), 0)
        XCTAssertNil(SwitcherSections.section(at: CGPoint(x: 50, y: 100), layout: l, visible: visible))
    }
}
