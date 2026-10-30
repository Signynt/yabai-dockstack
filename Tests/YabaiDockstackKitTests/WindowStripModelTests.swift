import XCTest
@testable import YabaiDockstackKit

final class WindowStripModelTests: XCTestCase {
    private let r = YRect(x: 0, y: 0, w: 1, h: 1)
    private var windows: [YabaiWindow] {
        [YabaiWindow(id: 1, pid: 1, app: "Code", title: "a.swift — projA", frame: r, display: 1, space: 1, stackIndex: 0, hasFocus: true),
         YabaiWindow(id: 2, pid: 1, app: "Code", title: "b.swift — projB", frame: r, display: 1, space: 2, stackIndex: 0, hasFocus: false),
         YabaiWindow(id: 3, pid: 2, app: "Safari", title: "news", frame: r, display: 2, space: 3, stackIndex: 0, hasFocus: false)]
    }
    private let spaces = [SpaceInfo(index: 1, display: 1, isVisible: true),
                          SpaceInfo(index: 2, display: 1, isVisible: false),
                          SpaceInfo(index: 3, display: 2, isVisible: true, isNativeFullscreen: true)]

    func testBuildGroupsPerDisplayAndSpace() {
        let strips = WindowStripModel.build(windows: windows, spaces: spaces, spaceLabels: [2: "web"])
        XCTAssertEqual(strips.map(\.display), [1, 2])
        XCTAssertEqual(strips[0].sections.map(\.name), ["1", "web"])
        XCTAssertEqual(strips[0].sections[0].isVisible, true)
        XCTAssertEqual(strips[0].sections[0].chips.first?.focused, true)
        XCTAssertEqual(strips[0].sections[0].chips.first?.keyword, "projA")
        XCTAssertFalse(strips[0].hidden)
        XCTAssertTrue(strips[1].hidden)
    }

    func testFit() {
        func fit(_ n: Int, full: Double, compact: Double, available: Double) -> WindowStripModel.Density {
            WindowStripModel.fit(fullWidths: Array(repeating: full, count: n),
                                 compactWidths: Array(repeating: compact, count: n),
                                 iconWidth: 30, overflowWidth: 30, available: available)
        }
        XCTAssertEqual(fit(2, full: 100, compact: 50, available: 250), .full)
        XCTAssertEqual(fit(3, full: 100, compact: 60, available: 250), .compact)
        XCTAssertEqual(fit(6, full: 100, compact: 60, available: 250), .iconOnly)
        XCTAssertEqual(fit(30, full: 100, compact: 60, available: 250), .overflow(visible: 7))
        XCTAssertEqual(fit(1, full: 100, compact: 60, available: 10), .overflow(visible: 0))
    }

    func testScaleChangeRerenders() {
        let s = WindowStripModel.DisplayStrip(display: 1, hidden: false, sections: [])
        let f = CGRect(x: 0, y: 0, width: 100, height: 100)
        XCTAssertTrue(WindowStripModel.needsRender(cached: .init(strip: s, frame: f, scale: 1), strip: s, frame: f, scale: 0.8))
        XCTAssertFalse(WindowStripModel.needsRender(cached: .init(strip: s, frame: f, scale: 0.8), strip: s, frame: f, scale: 0.8))
        XCTAssertEqual(AppConfig.load(from: #"{"style":"flag"}"#.data(using: .utf8)).windowStripScale, 0.8)
    }

    func testDecodesNativeFullscreen() {
        let d = #"[{"index":3,"display":2,"is-visible":true,"is-native-fullscreen":true}]"#.data(using: .utf8)!
        XCTAssertEqual(SpaceInfo.decodeList(d).first?.isNativeFullscreen, true)
    }

    func testIncludeEmptyAndDropSpace() {
        let strips = WindowStripModel.build(windows: windows, spaces: spaces + [SpaceInfo(index: 4, display: 1, isVisible: false)],
                                            spaceLabels: [:], includeEmpty: true)
        XCTAssertEqual(strips[0].sections.map(\.space), [1, 2, 4])
        XCTAssertTrue(strips[0].sections[2].chips.isEmpty)
        let ranges = [(space: 1, minX: 0.0, maxX: 100.0), (space: 2, minX: 110.0, maxX: 200.0)]
        XCTAssertEqual(WindowStripModel.dropSpace(x: 150, sections: ranges), 2)
        XCTAssertEqual(WindowStripModel.dropSpace(x: 104, sections: ranges), 1)   // gap → nearest
        XCTAssertNil(WindowStripModel.dropSpace(x: 400, sections: ranges))
        XCTAssertNil(WindowStripModel.dropSpace(x: -30, sections: ranges))
    }

    func testDropOutsideStripHeightCancels() {
        let ranges = [(space: 1, minX: 0.0, maxX: 100.0), (space: 2, minX: 110.0, maxX: 200.0)]
        XCTAssertEqual(WindowStripModel.dropSpace(x: 150, y: 10, height: 20, sections: ranges), 2)
        XCTAssertNil(WindowStripModel.dropSpace(x: 150, y: -200, height: 20, sections: ranges))
        XCTAssertNil(WindowStripModel.dropSpace(x: 150, y: 60, height: 20, sections: ranges))
    }

    func testStripSkipsFullscreenEmptySpaces() {
        let sp = spaces + [SpaceInfo(index: 4, display: 1, isVisible: false, isNativeFullscreen: true)]
        let strips = WindowStripModel.build(windows: windows, spaces: sp, spaceLabels: [:], includeEmpty: true)
        XCTAssertFalse(strips[0].sections.map(\.space).contains(4))
    }

    func testStripShownForAnyDisplayWithSpaces() {
        let empty = WindowStripModel.SpaceSection(space: 3, name: "3", isVisible: true, chips: [])
        XCTAssertTrue(WindowStripModel.shows(.init(display: 2, hidden: false, sections: [empty])))
        XCTAssertFalse(WindowStripModel.shows(.init(display: 2, hidden: true, sections: [empty])))
        XCTAssertFalse(WindowStripModel.shows(.init(display: 2, hidden: false, sections: [])))
    }

    func testDropSpaceAcrossDisplays() {
        let left = WindowStripModel.DropRegion(frame: CGRect(x: 0, y: 1000, width: 200, height: 20),
                                               sections: [(space: 1, minX: 0, maxX: 100), (space: 2, minX: 110, maxX: 200)])
        let right = WindowStripModel.DropRegion(frame: CGRect(x: 1800, y: 900, width: 200, height: 20),
                                                sections: [(space: 5, minX: 0, maxX: 90), (space: 6, minX: 100, maxX: 200)])
        XCTAssertEqual(WindowStripModel.dropSpace(screenX: 150, screenY: 1010, regions: [left, right]), 2)
        XCTAssertEqual(WindowStripModel.dropSpace(screenX: 1950, screenY: 910, regions: [left, right]), 6)
        XCTAssertNil(WindowStripModel.dropSpace(screenX: 1000, screenY: 910, regions: [left, right]))
        XCTAssertNil(WindowStripModel.dropSpace(screenX: 1950, screenY: 500, regions: [left, right]))
    }
}
