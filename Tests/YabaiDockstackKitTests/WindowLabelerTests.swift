import XCTest
@testable import YabaiDockstackKit

final class WindowLabelerTests: XCTestCase {
    private func k(_ app: String, _ title: String, _ siblings: [String] = []) -> String {
        WindowLabeler.keyword(app: app, title: title, siblingTitles: siblings)
    }

    func testEditorsUseWorkspaceName() {
        XCTAssertEqual(k("Code", "Stack.swift — yabai-dockstack"), "yabai-dockstack")
        XCTAssertEqual(k("Code", "● Stack.swift — yabai-dockstack — Visual Studio Code"), "yabai-dockstack")
        XCTAssertEqual(k("Code", "deployer"), "deployer")
        XCTAssertEqual(k("Cursor", "main.go — api-server"), "api-server")
    }

    func testJetBrainsUsesProjectName() {
        XCTAssertEqual(k("IntelliJ IDEA", "shop-backend – OrderService.kt"), "shop-backend")
    }

    func testTerminalsUseCwdLastComponent() {
        XCTAssertEqual(k("Warp", "~/Project/yabai-dockstack"), "yabai-dockstack")
        XCTAssertEqual(k("iTerm2", "les@mac: ~/work/foo"), "foo")
        XCTAssertEqual(k("Warp", "~"), "~")
    }

    func testSiblingsPickDifferingSegment() {
        XCTAssertEqual(k("Notes", "Notes - Groceries", ["Notes - Work"]), "Groceries")
        XCTAssertEqual(k("Preview", "a.pdf | Page 1", ["b.pdf | Page 1"]), "a.pdf")
    }

    func testFallbacks() {
        XCTAssertEqual(k("Gather", ""), "Gather")
        XCTAssertEqual(k("Safari", "Safari"), "Safari")
        XCTAssertEqual(k("Safari", "蘋果新聞"), "蘋果新聞")
    }

    func testBatchKeywords() {
        let r = YRect(x: 0, y: 0, w: 1, h: 1)
        let ws = [YabaiWindow(id: 1, pid: 1, app: "Code", title: "a.swift — projA", frame: r, display: 1, space: 1, stackIndex: 0, hasFocus: false),
                  YabaiWindow(id: 2, pid: 1, app: "Code", title: "b.swift — projB", frame: r, display: 1, space: 2, stackIndex: 0, hasFocus: false)]
        XCTAssertEqual(WindowLabeler.keywords(ws), [1: "projA", 2: "projB"])
        XCTAssertEqual(SwitcherModel.build(windows: ws, mru: [], scope: .allWindows).map(\.keyword), ["projA", "projB"])
        XCTAssertEqual(SwitcherModel.build(windows: ws, mru: [], scope: .allWindows, query: "projB").first?.keyword, "projB")
        XCTAssertEqual(WindowMenuModel.build(ws).first?.spaces.flatMap { $0.windows.map(\.keyword) }, ["projA", "projB"])
    }
}
