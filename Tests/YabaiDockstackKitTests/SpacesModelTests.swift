import XCTest
@testable import YabaiDockstackKit

final class SpacesModelTests: XCTestCase {
    private let spaces = [
        SpaceInfo(index: 1, display: 1, isVisible: true),
        SpaceInfo(index: 2, display: 1, isVisible: false),
        SpaceInfo(index: 3, display: 2, isVisible: true),
    ]

    private func window(_ id: Int, space: Int, stack: Int) -> YabaiWindow {
        YabaiWindow(id: id, pid: id * 10, app: "App\(id)", title: "Window\(id)",
                    frame: YRect(x: 0, y: 0, w: 100, h: 100), display: 1,
                    space: space, stackIndex: stack, hasFocus: id == 1)
    }

    func testBuildGroupsDisplaysAndOrdersWindows() {
        let groups = SpacesModel.build(
            spaces: spaces,
            windows: [window(3, space: 1, stack: 2), window(2, space: 1, stack: 1)],
            labels: [1: "Main"])

        XCTAssertEqual(groups.map(\.id), [1, 2])
        XCTAssertEqual(groups[0].spaces.map(\.id), [1, 2])
        XCTAssertEqual(groups[0].spaces[0].label, "Main")
        XCTAssertEqual(groups[0].spaces[0].windows.map(\.id), [2, 3])
        XCTAssertTrue(groups[0].spaces[1].windows.isEmpty)
    }

    func testStickyWindowAppearsOnceAtReportedSpace() {
        var sticky = window(9, space: 2, stack: 0)
        sticky = YabaiWindow(id: sticky.id, pid: sticky.pid, app: sticky.app, title: sticky.title,
                             frame: sticky.frame, display: sticky.display, space: sticky.space,
                             stackIndex: sticky.stackIndex, hasFocus: sticky.hasFocus,
                             isSticky: true)
        let groups = SpacesModel.build(spaces: spaces, windows: [sticky])
        let occurrences = groups.flatMap(\.spaces).flatMap(\.windows).filter { $0.id == 9 }
        XCTAssertEqual(occurrences.count, 1)
        XCTAssertTrue(occurrences[0].isSticky)
    }

    func testSpaceTransferSelectsOnlySourceWindows() {
        let windows = [window(3, space: 1, stack: 2), window(2, space: 1, stack: 1),
                       window(4, space: 2, stack: 0)]
        XCTAssertEqual(SpacesModel.windowIDsToMove(from: 1, to: 3, windows: windows), [2, 3])
        XCTAssertEqual(SpacesModel.windowIDsToMove(from: 1, to: 1, windows: windows), [])
    }

    func testDisplayableWindowsExcludesStickyAndProbedHiddenWindows() {
        var sticky = window(5, space: 1, stack: 0)
        sticky = YabaiWindow(id: sticky.id, pid: sticky.pid, app: sticky.app, title: sticky.title,
                             frame: sticky.frame, display: sticky.display, space: sticky.space,
                             stackIndex: sticky.stackIndex, hasFocus: sticky.hasFocus, isSticky: true)
        let scratchpad = YabaiWindow(id: 6, pid: 60, app: "Scratch", title: "Scratch",
                                     frame: sticky.frame, display: 1, space: 1, stackIndex: 2,
                                     hasFocus: false, scratchpad: "Spotify")
        let result = SpacesModel.displayableWindows([window(1, space: 1, stack: 0), sticky,
                                                     window(2, space: 1, stack: 1), scratchpad],
                                                    hiddenIDs: [2])
        XCTAssertEqual(result.map(\.id), [1, 5])

        let settingsScratchpad = YabaiWindow(id: 7, pid: 70, app: "System Settings",
                                             title: "Settings", frame: sticky.frame, display: 1,
                                             space: 1, stackIndex: 3, hasFocus: false,
                                             scratchpad: "settings")
        XCTAssertTrue(SpacesModel.displayableWindows([settingsScratchpad]).contains { $0.id == 7 })
    }

    func testSameDisplayReorderUsesAdjacentMoves() {
        let operations = SpacesReorderPlanner.plan(
            source: spaces[0], sourceIndex: 0,
            destinationDisplay: 1, destinationIndex: 1, spaces: spaces)
        XCTAssertEqual(operations, [.moveNext])
    }

    func testCrossDisplayReorderMovesToTrailingEdgeThenBack() {
        let operations = SpacesReorderPlanner.plan(
            source: spaces[0], sourceIndex: 0,
            destinationDisplay: 2, destinationIndex: 0, spaces: spaces)
        XCTAssertEqual(operations, [.moveToDisplay(2), .movePrevious])
    }

    func testInvalidInsertionIsRejected() {
        XCTAssertNil(SpacesReorderPlanner.plan(
            source: spaces[0], sourceIndex: 0,
            destinationDisplay: 1, destinationIndex: 4, spaces: spaces))
    }

    func testLayoutHasStablePositiveDimensions() {
        let metrics = SpacesLayout.metrics(displayCount: 6, maxWidth: 1200, maxHeight: 700)
        XCTAssertGreaterThan(metrics.spaceWidth, 0)
        XCTAssertGreaterThan(metrics.spaceHeight, 0)
        XCTAssertGreaterThan(metrics.windowWidth, 0)
        XCTAssertGreaterThan(metrics.windowHeight, 0)
    }

    func testLayoutWrapsManySpacesIntoRows() {
        let metrics = SpacesLayout.metrics(displayCount: 12, maxWidth: 1100, maxHeight: 700)
        XCTAssertGreaterThan(metrics.columns, 1)
        XCTAssertLessThan(metrics.columns, 12)
        XCTAssertLessThanOrEqual(
            Int(ceil(Double(12) / Double(metrics.columns))) * 170,
            700)
    }

    func testWindowTilesUseAspectAwareThreeWindowSplit() {
        let tiles = SpacesLayout.windowTiles(aspects: [2.0, 2.2, 0.5], width: 400, height: 220)
        XCTAssertEqual(tiles.count, 3)
        XCTAssertGreaterThan(tiles[0].width, 0)
        XCTAssertEqual(tiles[0].minX, tiles[1].minX, accuracy: 0.001)
        XCTAssertNotEqual(tiles[1].minY, tiles[0].minY, accuracy: 0.001)
        XCTAssertLessThan(tiles[2].maxX, tiles[0].minX)
        XCTAssertLessThanOrEqual(tiles.map(\.maxX).max()!, 400)
        XCTAssertLessThanOrEqual(tiles.map(\.maxY).max()!, 220)
    }
}
