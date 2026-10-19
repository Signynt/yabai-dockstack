import Foundation

/// Physical key turned into the Hyper Key (⌃⌥⌘ + optional ⇧).
public enum HyperSource: String, CaseIterable {
    case none, capsLock, rightCommand, rightOption, rightControl

    /// HID usage (page 7) for `hidutil` remapping.
    public var hidUsage: UInt64? {
        switch self {
        case .none: return nil
        case .capsLock: return 0x700000039
        case .rightCommand: return 0x7000000E7
        case .rightOption: return 0x7000000E6
        case .rightControl: return 0x7000000E4
        }
    }
}

/// What tapping the Hyper Key alone (no other key) does.
public enum HyperQuickPress: String, CaseIterable {
    case none, escape, toggleCapsLock  // toggleCapsLock only for `.capsLock`
}

/// `hidutil` UserKeyMapping handling: the source key is remapped to F18, which
/// the event tap then turns into the hyper modifiers. Only entries that map to
/// F18 are ours; anything else the user set up is preserved.
public enum HyperKeyMapping {
    public static let f18: UInt64 = 0x70000006D
    static let srcKey = "HIDKeyboardModifierMappingSrc"
    static let dstKey = "HIDKeyboardModifierMappingDst"

    /// Parses `hidutil property --get UserKeyMapping` output (OpenStep plist, or
    /// "(null)"). Nil when unreadable — callers must not mistake that for "no
    /// mappings" and overwrite the user's own.
    public static func parse(_ output: String) -> [[String: UInt64]]? {
        if output.trimmingCharacters(in: .whitespacesAndNewlines) == "(null)" { return [] }
        guard let data = output.data(using: .utf8),
              let list = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [[String: Any]]
        else { return nil }
        return list.compactMap { entry in
            guard let src = number(entry[srcKey]), let dst = number(entry[dstKey]) else { return nil }
            return [srcKey: src, dstKey: dst]
        }
    }

    /// `existing` minus our old entry, plus `source → F18` unless `.none`.
    public static func merged(existing: [[String: UInt64]], source: HyperSource) -> [[String: UInt64]] {
        var out = existing.filter { $0[dstKey] != f18 }
        if let usage = source.hidUsage { out.append([srcKey: usage, dstKey: f18]) }
        return out
    }

    /// Argument for `hidutil property --set`.
    public static func hidutilJSON(_ mappings: [[String: UInt64]]) -> String {
        let obj: [String: Any] = ["UserKeyMapping": mappings]
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    private static func number(_ v: Any?) -> UInt64? {
        if let n = v as? NSNumber { return n.uint64Value }
        if let s = v as? String { return UInt64(s) }
        return nil
    }
}

/// Event-tap state machine for the Hyper Key (seen as F18 after remapping).
/// The modifiers are really pressed on the first hyper down and released on
/// hyper up: only OR-ing flags onto key events at the HID level leaves the
/// system believing ⌃⌥⌘⇧ are still held afterwards (stuck modifiers).
public struct HyperKeyReducer: Equatable {
    public enum Event {
        case hyperDown, hyperUp, keyDown, keyUp
        /// Polling found the hyper key physically up while we think it's held
        /// (its keyUp was missed, e.g. Secure Input took over mid-press).
        case hyperFoundUp
    }
    public enum Action: Equatable {
        case pass, addHyperFlags, swallow
        /// Swallow the hyper key and post modifier key-downs.
        case pressModifiers
        /// Swallow the hyper key and post modifier key-ups.
        case releaseModifiers
        /// Release the modifiers, then perform the quick-press action.
        case quickPress
    }

    public private(set) var held = false
    /// Another key was pressed while held → releasing is not a quick press.
    public private(set) var used = false

    public init() {}

    public mutating func handle(_ e: Event) -> Action {
        switch e {
        case .hyperDown:
            guard !held else { return .swallow }  // autorepeat keeps `used`
            held = true; used = false
            return .pressModifiers
        case .hyperUp:
            guard held else { return .swallow }
            let quick = !used
            held = false; used = false
            return quick ? .quickPress : .releaseModifiers
        case .keyDown:
            guard held else { return .pass }
            used = true
            return .addHyperFlags
        case .keyUp:
            return held ? .addHyperFlags : .pass
        case .hyperFoundUp:
            guard held else { return .swallow }
            held = false; used = false
            return .releaseModifiers
        }
    }
}

/// Decisions that keep the Hyper Key from ever leaving its source key dead.
public enum HyperKeyPlan {
    public enum Health: Equatable { case start, stop, keep }

    /// Periodic check: start once Accessibility is granted; stop (restoring the
    /// key) if it was revoked while running.
    public static func health(configured: HyperSource, ax: Bool, running: Bool) -> Health {
        guard configured != .none else { return .keep }
        if running && !ax { return .stop }
        if !running && ax { return .start }
        return .keep
    }

    /// Remap the source key only while a tap is there to turn F18 into hyper.
    public static func mapping(configured: HyperSource, tapRunning: Bool) -> HyperSource {
        tapRunning ? configured : .none
    }
}
