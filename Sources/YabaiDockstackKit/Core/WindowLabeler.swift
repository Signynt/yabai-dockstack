import Foundation

/// Derives a short, distinguishing keyword for a window from its title — e.g.
/// the project name of a VS Code window — so several windows of the same app
/// can be told apart at a glance (switcher, Dock preview, menu, window strip).
public enum WindowLabeler {
    private static let separators = [" — ", " – ", " - ", " | "]
    private static let dirtyMarkers: Set<Character> = ["●", "•", "*"]
    /// Long names some apps append to their titles, keyed by yabai's app name.
    private static let aliases: [String: [String]] = [
        "Code": ["Visual Studio Code"],
        "Cursor": ["Cursor"],
        "Google Chrome": ["Google Chrome"],
        "Windsurf": ["Windsurf"],
    ]
    private static let editors: Set<String> = ["Code", "Cursor", "Windsurf", "VSCodium"]
    private static let jetBrains = ["IntelliJ", "PyCharm", "WebStorm", "GoLand", "CLion",
                                    "Rider", "PhpStorm", "RubyMine", "Android Studio"]
    private static let terminals: Set<String> = ["Warp", "iTerm2", "Terminal", "Ghostty",
                                                 "kitty", "Alacritty", "WezTerm"]

    /// `siblingTitles`: titles of the *other* windows of the same app.
    public static func keyword(app: String, title: String, siblingTitles: [String]) -> String {
        let segs = segments(title, app: app)
        guard !segs.isEmpty else { return app }

        if editors.contains(app) { return segs[segs.count - 1] }
        if jetBrains.contains(where: { app.contains($0) }) { return segs[0] }
        if terminals.contains(app), let cwd = cwdLeaf(segs) { return cwd }

        if !siblingTitles.isEmpty {
            let others = siblingTitles.map { segments($0, app: app) }
            if let differing = segs.first(where: { s in !others.allSatisfy { $0.contains(s) } }) {
                return differing
            }
        }
        return segs[0]
    }

    /// Window id → keyword, using same-app windows as siblings.
    public static func keywords(_ windows: [YabaiWindow]) -> [Int: String] {
        let byApp = Dictionary(grouping: windows, by: { $0.app })
        var out: [Int: String] = [:]
        for w in windows {
            let siblings = (byApp[w.app] ?? []).filter { $0.id != w.id }.map { $0.title }
            out[w.id] = keyword(app: w.app, title: w.title, siblingTitles: siblings)
        }
        return out
    }

    /// Title split on common separators, dirty markers and app-name segments removed.
    private static func segments(_ title: String, app: String) -> [String] {
        var parts = [title]
        for sep in separators {
            parts = parts.flatMap { $0.components(separatedBy: sep) }
        }
        let names = Set(([app] + (aliases[app] ?? [])).map { $0.lowercased() })
        return parts.compactMap { raw -> String? in
            var s = raw.trimmingCharacters(in: .whitespaces)
            while let c = s.first, dirtyMarkers.contains(c) {
                s = String(s.dropFirst()).trimmingCharacters(in: .whitespaces)
            }
            return s.isEmpty || names.contains(s.lowercased()) ? nil : s
        }
    }

    /// Last path component of the first cwd-looking segment ("user@host: ~/a/b" → "b").
    private static func cwdLeaf(_ segs: [String]) -> String? {
        guard let seg = segs.first(where: { $0.contains("/") || $0.hasPrefix("~") }) else { return nil }
        var path = seg
        if let r = path.range(of: ": ", options: .backwards) { path = String(path[r.upperBound...]) }
        let leaf = (path as NSString).lastPathComponent
        return leaf.isEmpty ? nil : leaf
    }
}
