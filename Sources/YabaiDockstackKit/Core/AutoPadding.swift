import Foundation

/// yabai's outer paddings that the app sizes for its own overlays.
public struct Paddings: Equatable {
    public var left: Int
    public var right: Int
    public var top: Int
    public init(left: Int, right: Int, top: Int) { self.left = left; self.right = right; self.top = top }
}

/// "Auto-adjust yabai padding": room for the stack indicators (drawn on the
/// screen-edge side of a stack) and, when shown, the window strip. The
/// result is exact — smaller indicators mean smaller padding.
public enum AutoPadding {
    public static func target(original: Paddings, cellSize: Double,
                              stripEnabled: Bool, stripScale: Double) -> Paddings {
        let side = Int(cellSize.rounded(.up)) + 2
        // The strip sits 2 pt under the menu bar; leave 4 pt below it.
        let top = stripEnabled ? Int((24 * stripScale).rounded(.up)) + 6 : original.top
        return Paddings(left: side, right: side, top: top)
    }

    /// `yabai -m config <key>` output → its integer value.
    public static func parse(_ output: String?) -> Int? {
        guard let s = output?.trimmingCharacters(in: .whitespacesAndNewlines), let v = Double(s) else { return nil }
        return Int(v)
    }
}

/// Restart: relaunch after we've exited (the bundle via `open -n`, or a bare
/// binary directly when not running from an .app).
public enum Relauncher {
    public static func arguments(bundlePath: String, executablePath: String) -> [String] {
        bundlePath.hasSuffix(".app")
            ? ["-c", "sleep 0.5; /usr/bin/open -n '\(bundlePath)'"]
            : ["-c", "sleep 0.5; '\(executablePath)' >/dev/null 2>&1 &"]
    }

    /// Spawns the relaunch shell; the caller then terminates.
    public static func schedule() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = arguments(bundlePath: Bundle.main.bundlePath,
                                executablePath: Bundle.main.executablePath ?? CommandLine.arguments[0])
        try? p.run()
    }
}
