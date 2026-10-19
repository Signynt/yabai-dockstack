import XCTest
@testable import YabaiDockstackKit

final class WindowFocuserTests: XCTestCase {
    /// A stand-in yabai: `--focus` exits with `focusExit`; `query` prints one window (id 7, pid 42).
    private func fakeYabai(focusExit: Int) throws -> String {
        let path = NSTemporaryDirectory() + "fake-yabai-\(UUID().uuidString)"
        let script = """
        #!/bin/sh
        case "$*" in
          *--focus*) exit \(focusExit) ;;
          *query*) echo '[{"id":7,"pid":42,"app":"Gather","frame":{"x":0,"y":0,"w":1,"h":1},"display":1,"space":1,"stack-index":0,"has-focus":false}]' ;;
        esac
        """
        try script.write(toFile: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        return path
    }

    func testFocusSuccessDoesNotReopen() throws {
        var reopened: [Int] = []
        let f = WindowFocuser(client: YabaiClient(yabaiPath: try fakeYabai(focusExit: 0)),
                              reopen: { reopened.append($0) })
        f.focus(windowId: 7)
        XCTAssertEqual(reopened, [])
    }

    func testFocusFailureReopensOwningApp() throws {
        var reopened: [Int] = []
        let f = WindowFocuser(client: YabaiClient(yabaiPath: try fakeYabai(focusExit: 1)),
                              reopen: { reopened.append($0) })
        f.focus(windowId: 7)
        XCTAssertEqual(reopened, [42])
    }

    func testFocusFailureUnknownWindowDoesNothing() throws {
        var reopened: [Int] = []
        let f = WindowFocuser(client: YabaiClient(yabaiPath: try fakeYabai(focusExit: 1)),
                              reopen: { reopened.append($0) })
        f.focus(windowId: 999)
        XCTAssertEqual(reopened, [])
    }
}
