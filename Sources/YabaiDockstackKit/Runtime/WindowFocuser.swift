import AppKit

/// Focuses a window on click/commit. Apps like Gather or Surfshark close their
/// window to the tray / menu bar: yabai still lists it but can't focus it (no
/// AX reference). Reopening the app (as clicking its Dock icon would) brings
/// that same window back, so fall back to that when yabai's focus fails.
public final class WindowFocuser {
    private let client: YabaiClient
    private let reopen: (_ pid: Int) -> Void

    public init(client: YabaiClient, reopen: @escaping (_ pid: Int) -> Void = WindowFocuser.reopenApp) {
        self.client = client
        self.reopen = reopen
    }

    /// Synchronous (runs yabai); call off the main thread where latency matters.
    public func focus(windowId: Int) {
        if client.focus(windowId: windowId) { return }
        guard let pid = client.queryWindows().first(where: { $0.id == windowId })?.pid else { return }
        reopen(pid)
    }

    /// Sends the app a reopen + activate, like `open -b <bundle id>`.
    public static func reopenApp(pid: Int) {
        DispatchQueue.main.async {
            guard let url = NSRunningApplication(processIdentifier: pid_t(pid))?.bundleURL else { return }
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: config)
        }
    }
}
