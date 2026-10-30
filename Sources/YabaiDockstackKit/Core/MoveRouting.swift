import Foundation

/// Whether yabai's scripting addition can work, judged like the bundled scripts:
/// only a fully-enabled SIP ("…status: enabled.") rules it out; partial
/// configurations don't. If csrutil failed, assume no SA (the SIP-free path
/// always works, the yabai path silently no-ops without the SA).
public enum SAProbe {
    public static func available(csrutilOutput: String?) -> Bool {
        guard let out = csrutilOutput, !out.isEmpty else { return false }
        return !out.split(separator: "\n").contains { $0.hasSuffix("status: enabled.") }
    }

    /// Runs `csrutil status`.
    public static func current() -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/csrutil")
        p.arguments = ["status"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return false }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return available(csrutilOutput: p.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : nil)
    }
}

public enum MoveRoute: Equatable {
    case noop
    /// The bundled moveWindowToSpace.sh (yabai + scripting addition).
    case script
    /// Focus the window, then SpaceMover's simulated drag walk.
    case sipFree
}

public enum MoveRouting {
    public static func decide(windowSpace: Int, target: Int, saAvailable: Bool) -> MoveRoute {
        if windowSpace == target { return .noop }
        return saAvailable ? .script : .sipFree
    }
}
