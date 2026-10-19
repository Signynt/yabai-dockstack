import AppKit

public final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let menu = NSMenu()

    public var onQuit: (() -> Void)?
    public var onOpenSettings: (() -> Void)?
    public var onReregisterSignals: (() -> Void)?
    public var onSelectWindow: ((Int) -> Void)?
    public var statusProvider: (() -> String)?
    public var windowListProvider: (() -> [WindowMenuModel.DisplayGroup])?
    /// Non-nil → show a prominent warning item (e.g. permissions missing).
    public var permissionWarning: (() -> String?)?
    /// True → show a prominent "yabai not found — set up…" item.
    public var yabaiMissing: (() -> Bool)?
    public var onOpenYabaiSetup: (() -> Void)?
    /// Open the menu when the pointer rests on the status icon (no click).
    public var openOnHover = false {
        didSet { if openOnHover != oldValue { updateHoverMonitors() } }
    }
    private var hoverTimer: Timer?
    private var hoverMonitors: [Any] = []
    private var hover = HoverOpenLogic()

    public override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        if let path = Bundle.main.url(forResource: "menubar", withExtension: "png"),
           let img = NSImage(contentsOf: path) {
            img.size = NSSize(width: 18, height: 18)
            statusItem.button?.image = img
        } else {
            statusItem.button?.title = "▦"
        }
        menu.delegate = self
        statusItem.menu = menu
        rebuild()
    }

    // MARK: - Hover to open
    //
    // A tracking area on the status button never fires (it's added while the
    // button is still zero-height, and NSStatusBarButton doesn't refresh it), so
    // watch mouse moves instead — global for other apps' windows, local for ours.

    private func updateHoverMonitors() {
        hoverMonitors.forEach(NSEvent.removeMonitor)
        hoverMonitors = []
        hoverTimer?.invalidate()
        hoverTimer = nil
        _ = hover.pointer(inside: false)
        guard openOnHover else { return }
        if let g = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved, handler: { [weak self] _ in
            self?.checkPointer()
        }) { hoverMonitors.append(g) }
        if let l = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved, handler: { [weak self] e in
            self?.checkPointer(); return e
        }) { hoverMonitors.append(l) }
    }

    private var buttonScreenRect: NSRect? {
        guard let button = statusItem.button, let win = button.window else { return nil }
        return win.convertToScreen(button.convert(button.bounds, to: nil))
    }

    /// Where the icon is drawn on the screen under the pointer. The real button
    /// only lives on the active display's menu bar; other menu bars draw a copy
    /// at the same distance from their right edge. `onButtonScreen` is false for
    /// such a copy.
    private func hoverTarget() -> (rect: NSRect, screen: NSScreen, onButtonScreen: Bool)? {
        let mouse = NSEvent.mouseLocation
        guard let icon = buttonScreenRect,
              let buttonScreen = statusItem.button?.window?.screen,
              let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) else { return nil }
        let rect = HoverOpenLogic.mirrored(icon, from: buttonScreen.frame, to: screen.frame)
        return (rect, screen, screen == buttonScreen)
    }

    private var pointerOnIcon: Bool {
        hoverTarget()?.rect.contains(NSEvent.mouseLocation) ?? false
    }

    private func checkPointer() {
        let inside = pointerOnIcon
        guard inside != hover.inside else { return }
        if !inside { hoverTimer?.invalidate(); hoverTimer = nil }
        guard hover.pointer(inside: inside) else { return }
        hoverTimer?.invalidate()
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { [weak self] _ in
            guard let self, self.hover.timerFired(pointerInside: self.pointerOnIcon),
                  let target = self.hoverTarget() else { return }
            if target.onButtonScreen {
                self.openMenu()
            } else {
                // Clicking the copy would first switch the active display; pop
                // the same menu right under the copy instead.
                let f = target.screen.frame, vf = target.screen.visibleFrame
                let menuBarBottom = vf.maxY < f.maxY ? vf.maxY : f.maxY - NSStatusBar.system.thickness
                self.menu.popUp(positioning: nil, at: NSPoint(x: target.rect.minX, y: menuBarBottom), in: nil)
            }
        }
    }

    public func menuDidClose(_ menu: NSMenu) {
        hoverTimer?.invalidate()
        hoverTimer = nil
        hover.menuClosed(pointerInside: pointerOnIcon)
    }

    // Rebuild dynamic contents whenever the menu is about to open.
    public func menuNeedsUpdate(_ menu: NSMenu) { rebuild() }

    /// Opens the status-item menu as if the icon were clicked (hotkey path).
    /// Main thread only.
    public func openMenu() {
        statusItem.button?.performClick(nil)
    }

    private func appIcon(pid: Int) -> NSImage {
        let img = NSRunningApplication(processIdentifier: pid_t(pid))?.icon
            ?? NSWorkspace.shared.icon(for: .applicationBundle)
        img.size = NSSize(width: 16, height: 16)
        return img
    }

    private func truncate(_ s: String, _ max: Int = 60) -> String {
        s.count <= max ? s : String(s.prefix(max - 1)) + "…"
    }

    private func disabledHeader(_ title: String, indent: Int) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.indentationLevel = indent
        return item
    }

    private func rebuild() {
        menu.removeAllItems()

        let status = NSMenuItem(title: statusProvider?() ?? "yabai: …", action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)

        if yabaiMissing?() == true {
            let title = L10n.t("ui.menu.yabaiMissing")
            let item = NSMenuItem(title: title,
                                  action: #selector(yabaiSetupAction), keyEquivalent: "")
            item.target = self
            item.attributedTitle = NSAttributedString(
                string: title,
                attributes: [.foregroundColor: NSColor.systemRed, .font: NSFont.menuFont(ofSize: 0)])
            menu.addItem(item)
        }

        if let warning = permissionWarning?() {
            let warn = NSMenuItem(title: warning, action: #selector(settingsAction), keyEquivalent: "")
            warn.target = self
            warn.attributedTitle = NSAttributedString(string: warning, attributes: [
                .foregroundColor: NSColor.systemOrange,
                .font: NSFont.menuFont(ofSize: 0),
            ])
            menu.addItem(warn)
        }

        menu.addItem(.separator())

        let groups = windowListProvider?() ?? []
        if groups.isEmpty {
            menu.addItem(disabledHeader(L10n.t("ui.menu.noWindows"), indent: 0))
        } else {
            let windowCount = groups.reduce(0) { $0 + $1.spaces.reduce(0) { $0 + $1.windows.count } }
            var quickKeys = MenuQuickKeys.keys(count: windowCount).makeIterator()
            for (di, display) in groups.enumerated() {
                menu.addItem(disabledHeader(String(format: L10n.t("ui.menu.displayN"), display.display), indent: 0))
                for space in display.spaces {
                    menu.addItem(disabledHeader(space.name, indent: 1))
                    for win in space.windows {
                        let label = win.keyword != win.app
                            ? "\(win.keyword) — \(win.app)"
                            : (win.title.isEmpty ? win.app : "\(win.app) — \(win.title)")
                        let item = NSMenuItem(title: truncate(label),
                                              action: #selector(selectWindow(_:)), keyEquivalent: "")
                        item.toolTip = win.title.isEmpty ? nil : win.title
                        item.target = self
                        item.indentationLevel = 2
                        item.representedObject = win.id
                        item.image = appIcon(pid: win.pid)
                        item.state = win.focused ? .on : .off
                        if let key = quickKeys.next() {
                            item.keyEquivalent = key
                            item.keyEquivalentModifierMask = []
                        }
                        menu.addItem(item)
                    }
                }
                if di < groups.count - 1 { menu.addItem(.separator()) }
            }
        }

        menu.addItem(.separator())

        let settings = NSMenuItem(title: L10n.t("ui.menu.settings"), action: #selector(settingsAction), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let reregister = NSMenuItem(title: L10n.t("ui.menu.reregister"),
                                    action: #selector(reregisterAction), keyEquivalent: "")
        reregister.target = self
        menu.addItem(reregister)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: L10n.t("ui.menu.quit"), action: #selector(quitAction), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    @objc private func selectWindow(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? Int { onSelectWindow?(id) }
    }
    @objc private func settingsAction() { onOpenSettings?() }
    @objc private func yabaiSetupAction() { onOpenYabaiSetup?() }
    @objc private func reregisterAction() { onReregisterSignals?() }
    @objc private func quitAction() { onQuit?() }
}
