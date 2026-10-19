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
    /// A chip was dragged onto another space's section: (window id, space).
    public var onDropToSpace: ((Int, Int) -> Void)?
    /// A chip drag is in progress: refreshes wait (replacing the views would
    /// kill the drag) and re-render when it ends.
    private var dragging = false
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
                                            spaceLabels: client.querySpaceLabels(), includeEmpty: true)
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
        guard !dragging else { return }
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
            // Size from the view's own fitted size: as a contentView its frame
            // follows the panel, so reading it back would just echo the panel.
            let anchor = { [weak panel, weak content] in
                guard let panel, let content else { return }
                let size = content.fittedSize
                panel.setFrame(NSRect(x: vf.maxX - size.width - 8, y: vf.maxY - size.height - 2,
                                      width: size.width, height: size.height), display: true)
            }
            content.onWidthChange = anchor
            content.onDragActive = { [weak self] active in
                guard let self else { return }
                self.dragging = active
                if !active, let last = self.last {
                    self.rendered.removeAll()  // force a redraw with whatever arrived meanwhile
                    self.render(last.strips, displays: last.displays)
                }
            }
            content.onDrop = { [weak self] id, space in self?.onDropToSpace?(id, space) }
            anchor()
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
/// Empty spaces take no room until a chip is dragged; then they open up as
/// named drop slots.
private final class StripView: NSView {
    private struct Entry {
        let section: WindowStripModel.SpaceSection
        let chips: [StripChip]
        let emptyLabel: NSTextField?
        let divider: NSView
        let highlight: NSView
    }
    private var entries: [Entry] = []
    private var overflow: OverflowChip?
    private var ranges: [(space: Int, minX: Double, maxX: Double)] = []
    private var expanded = false
    private let k: CGFloat
    /// Width × height the content needs (the panel is sized from this).
    private(set) var fittedSize: CGSize = .zero

    var onWidthChange: (() -> Void)?
    var onDragActive: ((Bool) -> Void)?
    var onDrop: ((Int, Int) -> Void)?

    init(strip: WindowStripModel.DisplayStrip, scale k: CGFloat, maxWidth: CGFloat,
         onClick: @escaping (Int) -> Void, onOverflow: @escaping () -> Void) {
        self.k = k
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.6).cgColor
        layer?.cornerRadius = 7 * k

        let filled = strip.sections.filter { !$0.chips.isEmpty }
        let chips = filled.flatMap(\.chips)
        let dividers = CGFloat(max(filled.count - 1, 0)) * 9 * k
        let density = WindowStripModel.fit(
            fullWidths: chips.map { Double(StripChip.width(for: $0, style: .full, scale: k)) },
            compactWidths: chips.map { Double(StripChip.width(for: $0, style: .compact, scale: k)) },
            iconWidth: Double(StripChip.width(for: nil, style: .iconOnly, scale: k)),
            overflowWidth: Double(30 * k), available: Double(maxWidth - dividers - 8 * k))
        let style: StripChip.Style
        var budget = chips.count
        switch density {
        case .full: style = .full
        case .compact: style = .compact
        case .iconOnly: style = .iconOnly
        case let .overflow(n): style = .iconOnly; budget = n
        }

        for section in strip.sections {
            let highlight = NSView()
            highlight.wantsLayer = true
            highlight.layer?.cornerRadius = 5 * k
            addSubview(highlight)
            let divider = NSView()
            divider.wantsLayer = true
            divider.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.3).cgColor
            addSubview(divider)
            var views: [StripChip] = []
            for chip in section.chips where budget > 0 {
                let v = StripChip(chip: chip, section: section, style: style, scale: k, onClick: onClick)
                v.onDrag = { [weak self] id, phase, ev in self?.handleDrag(id, from: section.space, phase, ev) }
                addSubview(v)
                views.append(v)
                budget -= 1
            }
            var label: NSTextField?
            if section.chips.isEmpty {
                let l = NSTextField(labelWithString: section.name)
                l.font = .systemFont(ofSize: 10 * k, weight: .medium)
                l.textColor = NSColor.white.withAlphaComponent(0.7)
                l.sizeToFit()
                addSubview(l)
                label = l
            }
            entries.append(Entry(section: section, chips: views, emptyLabel: label,
                                 divider: divider, highlight: highlight))
        }
        if case let .overflow(n) = density {
            let more = OverflowChip(count: chips.count - n, scale: k, onClick: onOverflow)
            addSubview(more)
            overflow = more
        }
        relayout()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func relayout() {
        let h = WindowStripController.baseHeight * k
        let pad = 4 * k, dividerW = 9 * k
        var x = pad
        var shown = 0
        ranges = []
        for e in entries {
            let isEmpty = e.section.chips.isEmpty
            let visible = !isEmpty ? !e.chips.isEmpty : expanded
            e.divider.isHidden = !(visible && shown > 0)
            e.emptyLabel?.isHidden = !visible
            e.highlight.isHidden = !visible
            guard visible else { continue }
            if shown > 0 {
                e.divider.frame = NSRect(x: x + dividerW / 2, y: h * 0.22, width: 1, height: h * 0.56)
                x += dividerW
            }
            shown += 1
            let start = x
            for c in e.chips {
                c.frame.origin = CGPoint(x: x, y: 2 * k)
                x += c.frame.width
            }
            if let l = e.emptyLabel {
                l.frame.origin = CGPoint(x: x + 6 * k, y: (h - l.frame.height) / 2)
                x += l.frame.width + 12 * k
            }
            e.highlight.frame = NSRect(x: start - 2 * k, y: 2 * k, width: x - start + 4 * k, height: h - 4 * k)
            e.highlight.layer?.backgroundColor = e.section.isVisible && !expanded
                ? NSColor.white.withAlphaComponent(0.1).cgColor : nil
            ranges.append((space: e.section.space, minX: Double(start), maxX: Double(x)))
        }
        if let more = overflow {
            more.frame = NSRect(x: x, y: 2 * k, width: 30 * k, height: h - 4 * k)
            x += 30 * k
        }
        fittedSize = CGSize(width: x + pad, height: h)
        frame = NSRect(origin: .zero, size: fittedSize)
    }

    private func handleDrag(_ windowId: Int, from space: Int, _ phase: StripChip.DragPhase, _ event: NSEvent) {
        switch phase {
        case .began:
            expanded = true
            onDragActive?(true)
            relayout()
            onWidthChange?()
        case .moved:
            let x = Double(convert(event.locationInWindow, from: nil).x)
            let target = WindowStripModel.dropSpace(x: x, sections: ranges)
            for e in entries {
                e.highlight.layer?.backgroundColor = e.section.space == target && target != space
                    ? NSColor.controlAccentColor.withAlphaComponent(0.45).cgColor : nil
            }
        case .ended:
            let x = Double(convert(event.locationInWindow, from: nil).x)
            let target = WindowStripModel.dropSpace(x: x, sections: ranges)
            expanded = false
            relayout()
            onWidthChange?()
            if let target, target != space { onDrop?(windowId, target) }
            onDragActive?(false)
        }
    }
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
    enum DragPhase { case began, moved, ended }
    var onDrag: ((_ windowId: Int, _ phase: DragPhase, _ event: NSEvent) -> Void)?
    private var pressPoint: NSPoint?
    private var dragging = false

    override func mouseDown(with event: NSEvent) {
        StripTooltip.hide(owner: self)
        pressPoint = event.locationInWindow
        dragging = false
    }
    override func mouseDragged(with event: NSEvent) {
        guard let start = pressPoint else { return }
        let p = event.locationInWindow
        if !dragging {
            guard abs(p.x - start.x) + abs(p.y - start.y) > 4 else { return }
            dragging = true
            alphaValue = 0.4
            onDrag?(chip.id, .began, event)
        }
        onDrag?(chip.id, .moved, event)
    }
    override func mouseUp(with event: NSEvent) {
        guard pressPoint != nil else { return }
        pressPoint = nil
        if dragging {
            dragging = false
            alphaValue = 1
            onDrag?(chip.id, .ended, event)
        } else {
            onClick(chip.id)
        }
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
