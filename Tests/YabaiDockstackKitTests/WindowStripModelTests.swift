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
        XCTAssertEqual(WindowStripModel.fit(fullWidths: [100, 100], compactWidth: 40, overflowWidth: 30, available: 250), .full)
        XCTAssertEqual(WindowStripModel.fit(fullWidths: [100, 100, 100], compactWidth: 40, overflowWidth: 30, available: 250), .compact)
        XCTAssertEqual(WindowStripModel.fit(fullWidths: Array(repeating: 100, count: 30), compactWidth: 40, overflowWidth: 30, available: 250), .overflow(visible: 5))
        XCTAssertEqual(WindowStripModel.fit(fullWidths: [100], compactWidth: 40, overflowWidth: 30, available: 10), .overflow(visible: 0))
    }

    func testDecodesNativeFullscreen() {
        let d = #"[{"index":3,"display":2,"is-visible":true,"is-native-fullscreen":true}]"#.data(using: .utf8)!
        XCTAssertEqual(SpaceInfo.decodeList(d).first?.isNativeFullscreen, true)
    }
}
