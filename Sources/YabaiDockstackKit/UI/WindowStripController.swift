import AppKit

/// One floating strip per display, directly under the menu bar (right-aligned):
/// every window on that display as icon + keyword + space chips, grouped by
/// space. Click a chip to jump to it; hover for the full title.
public final class WindowStripController {
    private let client: YabaiClient
    private let focuser: WindowFocuser
    private var enabled = false
    private var panels: [Int: NSPanel] = [:]
    private var rendered: [Int: WindowStripModel.Rendered] = [:]
    /// The "+N" chip was clicked (wired to opening the window menu).
    public var onOverflowClick: (() -> Void)?

    static let height: CGFloat = 24

    public init(client: YabaiClient, focuser: WindowFocuser) {
        self.client = client
        self.focuser = focuser
    }

    public func setEnabled(_ on: Bool) {
        enabled = on
        if !on {
            DispatchQueue.main.async { [weak self] in self?.removeAll() }
        }
    }

    /// Off-main (refresh queue): queries spaces, builds the model, renders on main.
    public func update(windows: [YabaiWindow]) {
        guard enabled else { return }
        let strips = WindowStripModel.build(windows: windows, spaces: client.querySpacesInfo(),
                                            spaceLabels: client.querySpaceLabels())
        let displays = client.queryDisplaysInfo()
        DispatchQueue.main.async { [weak self] in self?.render(strips, displays: displays) }
    }

    private func removeAll() {
        panels.values.forEach { $0.orderOut(nil) }
        panels.removeAll()
        rendered.removeAll()
    }

    private func render(_ strips: [WindowStripModel.DisplayStrip], displays: [DisplayInfo]) {
        guard enabled else { return }
        let screens = ScreenProvider.screens()
        var live = Set<Int>()
        for strip in strips where !strip.hidden {
            guard let frame = displays.first(where: { $0.index == strip.display })?.frame,
                  let screen = screens.first(where: { abs($0.yabaiFrame.x - frame.x) < 1 && abs($0.yabaiFrame.y - frame.y) < 1 }),
                  let ns = NSScreen.screens.first(where: { $0.frame == screen.cocoaFrame }) else { continue }
            live.insert(strip.display)
            if panels[strip.display] != nil,
               !WindowStripModel.needsRender(cached: rendered[strip.display], strip: strip, frame: ns.visibleFrame) {
                continue
            }
            rendered[strip.display] = WindowStripModel.Rendered(strip: strip, frame: ns.visibleFrame)
            let panel = panels[strip.display] ?? makePanel()
            panels[strip.display] = panel
            let content = StripView(strip: strip, maxWidth: ns.visibleFrame.width / 2,
                                    onClick: { [weak self] id in
                                        DispatchQueue.global(qos: .userInitiated).async {
                                            self?.focuser.focus(windowId: id)
                                        }
                                    },
                                    onOverflow: { [weak self] in self?.onOverflowClick?() })
            let vf = ns.visibleFrame
            panel.setFrame(NSRect(x: vf.maxX - content.frame.width - 8,
                                  y: vf.maxY - Self.height - 2,
                                  width: content.frame.width, height: Self.height), display: false)
            panel.contentView = content
            panel.orderFrontRegardless()
        }
        for (display, panel) in panels where !live.contains(display) {
            panel.orderOut(nil)
            panels.removeValue(forKey: display)
            rendered.removeValue(forKey: display)
        }
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.level = .floating
        p.isFloatingPanel = true
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        return p
    }
}

/// The strip's content: sections of chips separated by thin dividers.
private final class StripView: NSView {
    private static let pad: CGFloat = 4
    private static let dividerW: CGFloat = 9
    private static let overflowW: CGFloat = 30

    init(strip: WindowStripModel.DisplayStrip, maxWidth: CGFloat,
         onClick: @escaping (Int) -> Void, onOverflow: @escaping () -> Void) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.6).cgColor
        layer?.cornerRadius = 7

        let chips = strip.sections.flatMap(\.chips)
        let dividers = CGFloat(max(strip.sections.count - 1, 0)) * Self.dividerW
        let available = Double(maxWidth - dividers - Self.pad * 2)
        let density = WindowStripModel.fit(
            fullWidths: chips.map { Double(StripChip.width(for: $0, compact: false, sections: strip.sections)) },
            compactWidth: Double(StripChip.compactWidth(sections: strip.sections)),
            overflowWidth: Double(Self.overflowW), available: available)
        let compact = density != .full
        var budget: Int = {
            if case let .overflow(n) = density { return n }
            return chips.count
        }()

        var x = Self.pad
        let h = WindowStripController.height
        for (si, section) in strip.sections.enumerated() where budget > 0 {
            if si > 0 {
                let div = NSView(frame: NSRect(x: x + Self.dividerW / 2, y: 5, width: 1, height: h - 10))
                div.wantsLayer = true
                div.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.25).cgColor
                addSubview(div)
                x += Self.dividerW
            }
            let sectionStart = x
            for chip in section.chips where budget > 0 {
                let v = StripChip(chip: chip, section: section, compact: compact,
                                  sections: strip.sections, onClick: onClick)
                v.frame.origin = CGPoint(x: x, y: 2)
                addSubview(v)
                x += v.frame.width
                budget -= 1
            }
            if section.isVisible {
                let bg = NSView(frame: NSRect(x: sectionStart - 2, y: 2, width: x - sectionStart + 4, height: h - 4))
                bg.wantsLayer = true
                bg.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.1).cgColor
                bg.layer?.cornerRadius = 5
                addSubview(bg, positioned: .below, relativeTo: nil)
            }
        }
        if case let .overflow(n) = density {
            let more = OverflowChip(count: chips.count - n, onClick: onOverflow)
            more.frame = NSRect(x: x, y: 2, width: Self.overflowW, height: h - 4)
            addSubview(more)
            x += Self.overflowW
        }
        frame = NSRect(x: 0, y: 0, width: x + Self.pad, height: h)
    }
    required init?(coder: NSCoder) { fatalError() }
}

private final class StripChip: NSView {
    private static let font = NSFont.systemFont(ofSize: 11)
    private static let badgeFont = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .semibold)
    private static let icon: CGFloat = 16
    private let chip: WindowStripModel.Chip
    private let section: WindowStripModel.SpaceSection
    private let onClick: (Int) -> Void
    private var tooltip: NSPanel?

    static func badgeWidth(_ name: String) -> CGFloat {
        ceil((name as NSString).size(withAttributes: [.font: badgeFont]).width) + 8
    }
    static func compactWidth(sections: [WindowStripModel.SpaceSection]) -> CGFloat {
        let widest = sections.map { badgeWidth($0.name) }.max() ?? 0
        return 6 + icon + 3 + widest + 6
    }
    static func width(for chip: WindowStripModel.Chip, compact: Bool,
                      sections: [WindowStripModel.SpaceSection]) -> CGFloat {
        let name = sections.first { $0.space == chip.space }?.name ?? "\(chip.space)"
        let label = compact ? 0 : min(ceil((chip.keyword as NSString).size(withAttributes: [.font: font]).width), 140) + 4
        return 6 + icon + 3 + label + badgeWidth(name) + 6
    }

    init(chip: WindowStripModel.Chip, section: WindowStripModel.SpaceSection, compact: Bool,
         sections: [WindowStripModel.SpaceSection], onClick: @escaping (Int) -> Void) {
        self.chip = chip
        self.section = section
        self.onClick = onClick
        let w = Self.width(for: chip, compact: compact, sections: sections)
        let h = WindowStripController.height - 4
        super.init(frame: NSRect(x: 0, y: 0, width: w, height: h))
        wantsLayer = true
        layer?.cornerRadius = 5
        if chip.focused {
            layer?.borderWidth = 1.5
            layer?.borderColor = NSColor.controlAccentColor.cgColor
        }

        let iv = NSImageView(frame: NSRect(x: 6, y: (h - Self.icon) / 2, width: Self.icon, height: Self.icon))
        iv.image = NSRunningApplication(processIdentifier: pid_t(chip.pid))?.icon
            ?? NSWorkspace.shared.icon(for: .applicationBundle)
        addSubview(iv)
        var x = 6 + Self.icon + 3
        if !compact {
            let label = NSTextField(labelWithString: chip.keyword)
            label.font = Self.font
            label.textColor = .white
            label.lineBreakMode = .byTruncatingTail
            label.sizeToFit()
            let lw = min(label.frame.width, 140)
            label.frame = NSRect(x: x, y: (h - label.frame.height) / 2, width: lw, height: label.frame.height)
            addSubview(label)
            x += lw + 4
        }
        let badge = NSTextField(labelWithString: section.name)
        badge.font = Self.badgeFont
        badge.textColor = .white
        badge.alignment = .center
        badge.wantsLayer = true
        badge.drawsBackground = true
        badge.backgroundColor = NSColor.white.withAlphaComponent(0.18)
        badge.layer?.cornerRadius = 3
        badge.sizeToFit()
        badge.frame = NSRect(x: x, y: (h - 13) / 2, width: Self.badgeWidth(section.name), height: 13)
        addSubview(badge)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.15).cgColor
        showTooltip()
    }
    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = nil
        tooltip?.orderOut(nil)
        tooltip = nil
    }
    override func mouseDown(with event: NSEvent) {
        tooltip?.orderOut(nil)
        tooltip = nil
        onClick(chip.id)
    }

    /// Custom tooltip: system tooltips don't show for an inactive accessory app.
    private func showTooltip() {
        guard let win = window else { return }
        let title = chip.title.isEmpty ? chip.app : "\(chip.app) — \(chip.title)"
        let label = NSTextField(labelWithString: "\(title)\n\(section.name)")
        label.font = .systemFont(ofSize: 12)
        label.textColor = .white
        label.maximumNumberOfLines = 2
        label.sizeToFit()
        let pad: CGFloat = 6
        let size = NSSize(width: min(label.frame.width, 480) + pad * 2, height: label.frame.height + pad * 2)
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .floating
        p.backgroundColor = NSColor.black.withAlphaComponent(0.85)
        p.isOpaque = false
        p.hasShadow = true
        label.frame = NSRect(x: pad, y: pad, width: size.width - pad * 2, height: label.frame.height)
        p.contentView?.addSubview(label)
        let origin = win.convertPoint(toScreen: convert(NSPoint(x: 0, y: 0), to: nil))
        var x = origin.x
        if let screen = win.screen { x = min(x, screen.visibleFrame.maxX - size.width - 4) }
        p.setFrameOrigin(NSPoint(x: x, y: origin.y - size.height - 6))
        p.orderFrontRegardless()
        tooltip = p
    }
}

private final class OverflowChip: NSView {
    private let onClick: () -> Void
    init(count: Int, onClick: @escaping () -> Void) {
        self.onClick = onClick
        super.init(frame: .zero)
        let label = NSTextField(labelWithString: "+\(count)")
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .white
        label.alignment = .center
        label.frame = NSRect(x: 0, y: 3, width: 30, height: 14)
        addSubview(label)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func mouseDown(with event: NSEvent) { onClick() }
}
