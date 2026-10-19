import Foundation

public struct ShortcutBinding: Equatable {
    public var actionID: String
    public var enabled: Bool
    public var hotkey: Hotkey?
    public init(actionID: String, enabled: Bool, hotkey: Hotkey?) {
        self.actionID = actionID; self.enabled = enabled; self.hotkey = hotkey
    }
}

public enum ShortcutConflicts {
    public static func find(_ bindings: [ShortcutBinding]) -> [Hotkey: [String]] {
        var byKey: [Hotkey: [String]] = [:]
        for b in bindings where b.enabled {
            guard let hk = b.hotkey else { continue }
            byKey[hk, default: []].append(b.actionID)
        }
        return byKey.filter { $0.value.count > 1 }
    }
}

public enum ShortcutBindings {
    /// `bindings` with `action` bound to `hotkey` (created if missing); a nil
    /// hotkey disables the action's binding.
    public static func setting(_ bindings: [ShortcutBinding], action: String,
                               hotkey: Hotkey?) -> [ShortcutBinding] {
        var out = bindings
        let updated = ShortcutBinding(actionID: action, enabled: hotkey != nil, hotkey: hotkey)
        if let i = out.firstIndex(where: { $0.actionID == action }) { out[i] = updated }
        else if hotkey != nil { out.append(updated) }
        return out
    }
}
