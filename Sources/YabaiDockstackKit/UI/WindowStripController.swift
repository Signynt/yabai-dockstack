import AppKit

/// One floating strip per display, directly under the menu bar (right-aligned):
/// every window on that display as icon + keyword chips, spaces separated by a
/// divider. Click a chip to jump to it; hover for the full title and space.
public final class WindowStripController {
    private let client: YabaiClient
    private let focuser: WindowFocuser
    private var enabled = false
    private var panels: [Int: NSPanel] = [:]
    private var rendered: [Int: WindowStripModel.Rendered] = [:]
    /// The "+N" chip was clicked (wired to opening the window menu).
    public var onOverflowClick: (() -> Void)?
    /// Size multiplier (Settings → window strip size); 1 = 24 pt tall.
    private var scale: CGFloat = 0.8
    private var last: (strips: [WindowStripModel.DisplayStrip], displays: [DisplayInfo])?

    static let baseHeight: CGFloat = 24

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

    /// Main thread. Redraws right away with the last data.
    public func setScale(_ s: Double) {
        let new = CGFloat(min(max(s, 0.5), 1.5))
        guard new != scale else { return }
        scale = new
        if let last { render(last.strips, displays: last.displays) }
    }

    private func removeAll() {
        StripTooltip.hide()
        panels.values.forEach { $0.orderOut(nil) }
        panels.removeAll()
        rendered.removeAll()
    }

    private func render(_ strips: [WindowStripModel.DisplayStrip], displays: [DisplayInfo]) {
        guard enabled else { return }
        last = (strips, displays)
        let screens = ScreenProvider.screens()
        var live = Set<Int>()
        for strip in strips where !strip.hidden {
            guard let frame = displays.first(where: { $0.index == strip.display })?.frame,
                  let screen = screens.first(where: { abs($0.yabaiFrame.x - frame.x) < 1 && abs($0.yabaiFrame.y - frame.y) < 1 }),
                  let ns = NSScreen.screens.first(where: { $0.frame == screen.cocoaFrame }) else { continue }
            live.insert(strip.display)
            if panels[strip.display] != nil,
               !WindowStripModel.needsRender(cached: rendered[strip.display], strip: strip,
                                             frame: ns.visibleFrame, scale: Double(scale)) {
                continue
            }
            rendered[strip.display] = WindowStripModel.Rendered(strip: strip, frame: ns.visibleFrame,
                                                                scale: Double(scale))
            let panel = panels[strip.display] ?? makePanel()
            panels[strip.display] = panel
            let content = StripView(strip: strip, scale: scale, maxWidth: ns.visibleFrame.width / 2,
                                    onClick: { [weak self] id in
                                        DispatchQueue.global(qos: .userInitiated).async {
                                            self?.focuser.focus(windowId: id)
                                        }
                                    },
                                    onOverflow: { [weak self] in self?.onOverflowClick?() })
            let vf = ns.visibleFrame
            let h = content.frame.height
            panel.setFrame(NSRect(x: vf.maxX - content.frame.width - 8, y: vf.maxY - h - 2,
                                  width: content.frame.width, height: h), display: false)
            panel.contentView = content
            panel.orderFrontRegardless()
        }
        for (display, panel) in panels where !live.contains(display) {
            panel.contentView = nil  // detaches chips → their tooltip is dropped
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

/// The strip's content: chips separated by a thin divider between spaces.
private final class StripView: NSView {
    init(strip: WindowStripModel.DisplayStrip, scale k: CGFloat, maxWidth: CGFloat,
         onClick: @escaping (Int) -> Void, onOverflow: @escaping () -> Void) {
        super.init(frame: .zero)
        let h = WindowStripController.baseHeight * k
        let pad = 4 * k, dividerW = 9 * k, overflowW = 30 * k
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.6).cgColor
        layer?.cornerRadius = 7 * k

        let chips = strip.sections.flatMap(\.chips)
        let dividers = CGFloat(max(strip.sections.count - 1, 0)) * dividerW
        let available = Double(maxWidth - dividers - pad * 2)
        let density = WindowStripModel.fit(
            fullWidths: chips.map { Double(StripChip.width(for: $0, style: .full, scale: k)) },
            compactWidths: chips.map { Double(StripChip.width(for: $0, style: .compact, scale: k)) },
            iconWidth: Double(StripChip.width(for: nil, style: .iconOnly, scale: k)),
            overflowWidth: Double(overflowW), available: available)
        let style: StripChip.Style
        var budget = chips.count
        switch density {
        case .full: style = .full
        case .compact: style = .compact
        case .iconOnly: style = .iconOnly
        case let .overflow(n): style = .iconOnly; budget = n
        }

        var x = pad
        for (si, section) in strip.sections.enumerated() where budget > 0 {
            if si > 0 {
                let div = NSView(frame: NSRect(x: x + dividerW / 2, y: h * 0.22, width: 1, height: h * 0.56))
                div.wantsLayer = true
                div.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.3).cgColor
                addSubview(div)
                x += dividerW
            }
            let sectionStart = x
            for chip in section.chips where budget > 0 {
                let v = StripChip(chip: chip, section: section, style: style, scale: k, onClick: onClick)
                v.frame.origin = CGPoint(x: x, y: 2 * k)
                addSubview(v)
                x += v.frame.width
                budget -= 1
            }
            if section.isVisible {
                let bg = NSView(frame: NSRect(x: sectionStart - 2 * k, y: 2 * k,
                                              width: x - sectionStart + 4 * k, height: h - 4 * k))
                bg.wantsLayer = true
                bg.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.1).cgColor
                bg.layer?.cornerRadius = 5 * k
                addSubview(bg, positioned: .below, relativeTo: nil)
            }
        }
        if case let .overflow(n) = density {
            let more = OverflowChip(count: chips.count - n, scale: k, onClick: onOverflow)
            more.frame = NSRect(x: x, y: 2 * k, width: overflowW, height: h - 4 * k)
            addSubview(more)
            x += overflowW
        }
        frame = NSRect(x: 0, y: 0, width: x + pad, height: h)
    }
    required init?(coder: NSCoder) { fatalError() }
}

private final class StripChip: NSView {
    enum Style { case full, compact, iconOnly }
    private static let fullMax: CGFloat = 140
    private static let compactMax: CGFloat = 56
    private let chip: WindowStripModel.Chip
    private let section: WindowStripModel.SpaceSection
    private let onClick: (Int) -> Void

    private static func font(_ k: CGFloat) -> NSFont { .systemFont(ofSize: 11 * k) }

    static func width(for chip: WindowStripModel.Chip?, style: Style, scale k: CGFloat) -> CGFloat {
        let base = 5 * k + 16 * k + 5 * k
        guard style != .iconOnly, let chip else { return base }
        let cap = (style == .full ? fullMax : compactMax) * k
        return base + min(labelWidth(chip.keyword, k), cap) + 2 * k
    }

    /// Measured the way the label renders (NSString sizing misses the field's inset).
    private static func labelWidth(_ text: String, _ k: CGFloat) -> CGFloat {
        let f = NSTextField(labelWithString: text)
        f.font = font(k)
        return ceil(f.fittingSize.width)
    }

    init(chip: WindowStripModel.Chip, section: WindowStripModel.SpaceSection, style: Style,
         scale k: CGFloat, onClick: @escaping (Int) -> Void) {
        self.chip = chip
        self.section = section
        self.onClick = onClick
        let h = (WindowStripController.baseHeight - 4) * k
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width(for: chip, style: style, scale: k), height: h))
        wantsLayer = true
        layer?.cornerRadius = 5 * k
        if chip.focused {
            layer?.borderWidth = 1.5
            layer?.borderColor = NSColor.controlAccentColor.cgColor
        }
        let icon = 16 * k
        let iv = NSImageView(frame: NSRect(x: 5 * k, y: (h - icon) / 2, width: icon, height: icon))
        iv.image = NSRunningApplication(processIdentifier: pid_t(chip.pid))?.icon
            ?? NSWorkspace.shared.icon(for: .applicationBundle)
        iv.imageScaling = .scaleProportionallyUpOrDown
        addSubview(iv)
        guard style != .iconOnly else { return }
        let label = NSTextField(labelWithString: chip.keyword)
        label.font = Self.font(k)
        label.textColor = .white
        label.lineBreakMode = .byTruncatingTail
        label.sizeToFit()
        let x = 5 * k + icon + 4 * k
        label.frame = NSRect(x: x, y: (h - label.frame.height) / 2,
                             width: frame.width - x - 1 * k, height: label.frame.height)
        addSubview(label)
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
        let title = chip.title.isEmpty ? chip.app : "\(chip.app) — \(chip.title)"
        StripTooltip.show("\(title)\nSpace \(section.name)", below: self)
    }
    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = nil
        StripTooltip.hide(owner: self)
    }
    override func mouseDown(with event: NSEvent) {
        StripTooltip.hide(owner: self)
        onClick(chip.id)
    }
    /// A refresh replaces the chips under a resting pointer: no mouseExited
    /// will ever come, so drop the tooltip when the chip leaves its window.
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil { StripTooltip.hide(owner: self) }
    }
}

/// The strip's single tooltip (system tooltips don't show for an inactive
/// accessory app). One shared panel, so a missed mouseExited can't stack up
/// tooltips that never go away.
enum StripTooltip {
    private static var panel: NSPanel?
    private static weak var owner: NSView?

    static func show(_ text: String, below view: NSView) {
        hide()
        guard let win = view.window else { return }
        let label = NSTextField(labelWithString: text)
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
        p.ignoresMouseEvents = true
        label.frame = NSRect(x: pad, y: pad, width: size.width - pad * 2, height: label.frame.height)
        p.contentView?.addSubview(label)
        let origin = win.convertPoint(toScreen: view.convert(NSPoint(x: 0, y: 0), to: nil))
        var x = origin.x
        if let screen = win.screen { x = min(x, screen.visibleFrame.maxX - size.width - 4) }
        p.setFrameOrigin(NSPoint(x: x, y: origin.y - size.height - 6))
        p.orderFrontRegardless()
        panel = p
        owner = view
    }

    /// `owner`: only hide if that view is the one showing it (nil = always).
    static func hide(owner who: NSView? = nil) {
        if let who, owner !== who { return }
        panel?.orderOut(nil)
        panel = nil
        owner = nil
    }
}

private final class OverflowChip: NSView {
    private let onClick: () -> Void
    init(count: Int, scale k: CGFloat, onClick: @escaping () -> Void) {
        self.onClick = onClick
        super.init(frame: .zero)
        let label = NSTextField(labelWithString: "+\(count)")
        label.font = .systemFont(ofSize: 11 * k, weight: .semibold)
        label.textColor = .white
        label.alignment = .center
        label.sizeToFit()
        label.frame = NSRect(x: 0, y: ((WindowStripController.baseHeight - 4) * k - label.frame.height) / 2,
                             width: 30 * k, height: label.frame.height)
        addSubview(label)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func mouseDown(with event: NSEvent) { onClick() }
}
