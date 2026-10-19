import AppKit
import CoreGraphics

public enum SwitcherAppearance: String {
    case thumbnails, icons, titles
}

/// A switcher item plus the imagery the panel needs to draw it.
public struct SwitcherDisplayItem {
    public let item: SwitcherItem
    public let thumbnail: CGImage?
    public let icon: NSImage

    public init(item: SwitcherItem, thumbnail: CGImage?, icon: NSImage) {
        self.item = item; self.thumbnail = thumbnail; self.icon = icon
    }
}

/// Centered switcher overlay. Non-activating; in sticky mode it becomes key
/// (Spotlight-style) so it can take Tab/arrows/typing without activating the
/// frontmost app. In hold mode it never takes key — the event tap feeds it.
public final class SwitcherPanel {
    public var onHover: ((Int) -> Void)?
    public var onClick: ((Int) -> Void)?
    public var onCloseItem: ((Int) -> Void)?
    /// Sticky-mode keys; return true when consumed.
    public var onKeyEvent: ((NSEvent) -> Bool)?
    /// Sticky-mode panel lost key status (clicked elsewhere) — dismiss.
    public var onResignKey: (() -> Void)?

    /// Columns of the current grid — the controller uses this for ↑/↓ movement.
    public private(set) var columns = 1
    /// Sectioned (sticky) layout: cell frames for ↑/↓, nil in flat mode.
    public private(set) var cellFrames: [CGRect]?
    /// A cell was dragged onto another space's card: (window id, space).
    public var onDropToSpace: ((Int, Int) -> Void)?
    /// A drag ended without a drop (re-render now if one was deferred).
    public var onDragEnded: (() -> Void)?
    public var isDragging: Bool { dragWindowId != nil }
    private var itemIDs: [Int] = []
    private var dragWindowId: Int?

    private var sectionLayout: SectionLayout?
    private var sectionSpaces: [Int] = []
    private var sectionHeaders: [NSTextField] = []
    private var sectionHeaderColors: [NSColor] = []
    private weak var sectionBody: NSView?
    private var dragGhost: NSImageView?
    private var dragSource: Int?

    private var panel: SwitcherKeyPanel?
    private var cells: [SwitcherCellView] = []

    public init() {}

    public var isVisible: Bool { panel?.isVisible ?? false }

    public func show(items: [SwitcherDisplayItem], appearance: SwitcherAppearance,
                     selection: Int, query: String, keyboardFocus: Bool,
                     sections: [SwitcherSection]? = nil) {
        let p = panel ?? makePanel()
        panel = p

        let screen = NSScreen.main ?? NSScreen.screens.first
        let vf = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let maxW = vf.width * 0.82
        let maxH = vf.height * 0.72

        let pad: CGFloat = 16
        let gap: CGFloat = 10
        let headerH: CGFloat = query.isEmpty ? 0 : 32

        cells = []
        itemIDs = items.map { $0.item.id }
        cellFrames = nil
        sectionLayout = nil
        sectionHeaders = []
        sectionHeaderColors = []
        endDrag()
        let content: NSView
        var contentSize: CGSize

        if let sections, !sections.isEmpty {
            (content, contentSize) = buildSectioned(items: items, sections: sections, appearance: appearance,
                                                    selection: selection, maxW: maxW - pad * 2,
                                                    maxH: maxH - pad * 2 - headerH, headerH: headerH, gap: gap)
        } else if items.isEmpty {
            columns = 1
            let label = NSTextField(labelWithString: L10n.t("ui.switcher.noWindows"))
            label.font = .systemFont(ofSize: 14)
            label.textColor = .secondaryLabelColor
            label.sizeToFit()
            let holder = FlippedView(frame: CGRect(x: 0, y: 0,
                                                   width: max(label.frame.width + pad * 4, 260),
                                                   height: 56 + headerH))
            label.frame.origin = CGPoint(x: (holder.frame.width - label.frame.width) / 2,
                                         y: headerH + (56 - label.frame.height) / 2)
            holder.addSubview(label)
            content = holder
            contentSize = holder.frame.size
        } else {
            switch appearance {
            case .thumbnails, .icons:
                let base: (w: Double, minW: Double, label: Double) = appearance == .thumbnails
                    ? (240, 128, 24) : (136, 104, 44)
                let grid = SwitcherLayout.grid(count: items.count,
                                               maxWidth: maxW - pad * 2,
                                               maxHeight: maxH - pad * 2 - headerH,
                                               baseCellWidth: base.w, minCellWidth: base.minW,
                                               labelHeight: base.label, gap: gap)
                columns = grid.columns
                let cellW = CGFloat(grid.cellWidth), cellH = CGFloat(grid.cellHeight)
                let w = CGFloat(min(items.count, grid.columns)) * (cellW + gap) - gap
                let bodyH = CGFloat(grid.rows) * (cellH + gap) - gap
                let body = FlippedView(frame: CGRect(x: 0, y: 0, width: w, height: bodyH))
                for (i, di) in items.enumerated() {
                    let col = i % grid.columns, row = i / grid.columns
                    let f = CGRect(x: CGFloat(col) * (cellW + gap),
                                   y: CGFloat(row) * (cellH + gap),
                                   width: cellW, height: cellH)
                    let cell = SwitcherCellView(frame: f, index: i, item: di,
                                                mode: appearance,
                                                onHover: { [weak self] in self?.onHover?($0) },
                                                onClick: { [weak self] in self?.onClick?($0) },
                                                onClose: { [weak self] in self?.onCloseItem?($0) })
                    cell.isSelected = i == selection
                    cells.append(cell)
                    body.addSubview(cell)
                }
                // Rows can still overflow when cells already bottomed out at
                // the minimum size — scroll instead of rendering offscreen.
                let visibleH = min(bodyH, maxH - pad * 2 - headerH)
                let holder = FlippedView(frame: CGRect(x: 0, y: 0, width: w,
                                                       height: visibleH + headerH))
                if bodyH > visibleH {
                    let scroll = NSScrollView(frame: CGRect(x: 0, y: headerH,
                                                            width: w, height: visibleH))
                    scroll.hasVerticalScroller = true
                    scroll.drawsBackground = false
                    scroll.documentView = body
                    holder.addSubview(scroll)
                } else {
                    body.frame.origin.y = headerH
                    holder.addSubview(body)
                }
                content = holder
                contentSize = holder.frame.size
            case .titles:
                columns = 1
                let rowH: CGFloat = 32
                let listW = min(CGFloat(640), maxW - pad * 2)
                let listH = CGFloat(items.count) * rowH
                let list = FlippedView(frame: CGRect(x: 0, y: 0, width: listW, height: listH))
                for (i, di) in items.enumerated() {
                    let f = CGRect(x: 0, y: CGFloat(i) * rowH, width: listW, height: rowH - 2)
                    let cell = SwitcherCellView(frame: f, index: i, item: di,
                                                mode: appearance,
                                                onHover: { [weak self] in self?.onHover?($0) },
                                                onClick: { [weak self] in self?.onClick?($0) },
                                                onClose: { [weak self] in self?.onCloseItem?($0) })
                    cell.isSelected = i == selection
                    cells.append(cell)
                    list.addSubview(cell)
                }
                let visibleH = min(listH, maxH - pad * 2 - headerH)
                let holder = FlippedView(frame: CGRect(x: 0, y: 0, width: listW,
                                                       height: visibleH + headerH))
                if listH > visibleH {
                    let scroll = NSScrollView(frame: CGRect(x: 0, y: headerH,
                                                            width: listW, height: visibleH))
                    scroll.hasVerticalScroller = true
                    scroll.drawsBackground = false
                    scroll.documentView = list
                    holder.addSubview(scroll)
                } else {
                    list.frame.origin.y = headerH
                    holder.addSubview(list)
                }
                content = holder
                contentSize = holder.frame.size
            }
        }

        if headerH > 0 {
            let q = NSTextField(labelWithString: "🔍 \(query)")
            q.font = .systemFont(ofSize: 14, weight: .medium)
            q.textColor = .labelColor
            q.lineBreakMode = .byTruncatingHead
            q.frame = CGRect(x: 2, y: 4, width: contentSize.width - 4, height: 20)
            content.addSubview(q)
        }

        let effect = NSVisualEffectView(frame: CGRect(x: 0, y: 0,
                                                      width: contentSize.width + pad * 2,
                                                      height: contentSize.height + pad * 2))
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 16
        effect.layer?.masksToBounds = true
        content.setFrameOrigin(CGPoint(x: pad, y: pad))
        effect.addSubview(content)

        let frame = CGRect(x: vf.midX - effect.frame.width / 2,
                           y: vf.midY - effect.frame.height / 2 + vf.height * 0.05,
                           width: effect.frame.width, height: effect.frame.height)
        p.setFrame(frame, display: true)
        p.contentView = effect

        p.acceptsKeys = keyboardFocus
        if keyboardFocus {
            p.makeKeyAndOrderFront(nil)
        } else {
            p.orderFrontRegardless()
        }
        scrollSelectionIntoView(selection)
    }

    // MARK: - Sectioned (sticky) mode

    private func buildSectioned(items: [SwitcherDisplayItem], sections: [SwitcherSection],
                                appearance: SwitcherAppearance, selection: Int, maxW: CGFloat,
                                maxH: CGFloat, headerH: CGFloat, gap: CGFloat) -> (NSView, CGSize) {
        let titleH: Double = 22, emptyH: Double = 40
        let cols: Int, cell: CGSize
        switch appearance {
        case .thumbnails, .icons:
            let base: (w: Double, minW: Double, label: Double) = appearance == .thumbnails
                ? (240, 128, 24) : (136, 104, 44)
            // Size cells as if every window (plus a header per card) shared one grid.
            let grid = SwitcherLayout.grid(count: max(items.count + sections.count, 1), maxWidth: Double(maxW),
                                           maxHeight: Double(maxH),
                                           baseCellWidth: base.w, minCellWidth: base.minW,
                                           labelHeight: base.label, gap: Double(gap))
            cols = 3  // per space card; cards themselves flow across the panel
            cell = CGSize(width: grid.cellWidth, height: grid.cellHeight)
        case .titles:
            cols = 1
            cell = CGSize(width: min(CGFloat(640), maxW), height: 30)
        }
        columns = cols
        let displays = sections.map(\.display)
        let multiDisplay = Set(displays).count > 1
        let layout = SwitcherSections.layout(counts: sections.map { $0.items.count }, columns: cols,
                                             cell: cell, gap: Double(gap), headerHeight: titleH,
                                             emptyHeight: emptyH, maxWidth: Double(maxW),
                                             displays: multiDisplay ? displays : [],
                                             displayHeader: 26, displayPad: 12)
        sectionLayout = layout
        sectionSpaces = sections.map(\.space)
        cellFrames = layout.cells

        let body = FlippedView(frame: CGRect(origin: .zero, size: layout.size))
        sectionBody = body
        // One band per display, its number in the corner.
        let orderedDisplays = displays.reduce(into: [Int]()) { if $0.last != $1 { $0.append($1) } }
        for (bi, band) in layout.displays.enumerated() {
            let v = NSView(frame: band)
            v.wantsLayer = true
            v.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.16).cgColor
            v.layer?.borderColor = NSColor.white.withAlphaComponent(0.10).cgColor
            v.layer?.borderWidth = 1
            v.layer?.cornerRadius = 14
            body.addSubview(v)
            let n = orderedDisplays.indices.contains(bi) ? orderedDisplays[bi] : bi + 1
            let label = NSTextField(labelWithString: String(format: L10n.t("ui.menu.displayN"), n))
            label.font = .systemFont(ofSize: 12, weight: .bold)
            label.textColor = .labelColor
            label.sizeToFit()
            label.frame.origin = CGPoint(x: band.minX + 12, y: band.minY + (26 - label.frame.height) / 2 + 2)
            body.addSubview(label)
        }
        for (si, section) in sections.enumerated() {
            let h = layout.headers[si]
            let card = NSView(frame: layout.sections[si].insetBy(dx: -4, dy: -2))
            card.wantsLayer = true
            card.layer?.cornerRadius = 10
            card.layer?.backgroundColor = NSColor.white.withAlphaComponent(section.hasFocus ? 0.12 : 0.05).cgColor
            if section.hasFocus {
                card.layer?.borderColor = NSColor.systemGreen.cgColor
                card.layer?.borderWidth = 2
            } else if section.isVisible {
                card.layer?.borderColor = NSColor.white.withAlphaComponent(0.3).cgColor
                card.layer?.borderWidth = 1
            }
            body.addSubview(card)
            // "Current" (the space you're on) / "Visible" (on screen on another display).
            var tagW: CGFloat = 0
            if section.hasFocus || section.isVisible {
                let tag = NSTextField(labelWithString: L10n.t(section.hasFocus ? "ui.switcher.currentSpace"
                                                                               : "ui.switcher.visibleSpace"))
                tag.font = .systemFont(ofSize: 10, weight: .bold)
                tag.textColor = section.hasFocus ? .white : .labelColor
                tag.alignment = .center
                tag.wantsLayer = true
                tag.layer?.cornerRadius = 4
                tag.layer?.backgroundColor = (section.hasFocus ? NSColor.systemGreen
                                              : NSColor.white.withAlphaComponent(0.18)).cgColor
                tag.sizeToFit()
                tagW = tag.frame.width + 10
                tag.frame = CGRect(x: h.maxX - tagW, y: h.minY + (h.height - tag.frame.height) / 2,
                                   width: tagW, height: tag.frame.height)
                body.addSubview(tag)
            }
            let title = NSTextField(labelWithString: section.name)
            let color: NSColor = section.hasFocus ? .labelColor : .secondaryLabelColor
            title.font = .systemFont(ofSize: 12, weight: .semibold)
            title.textColor = color
            title.lineBreakMode = .byTruncatingTail
            title.wantsLayer = true
            title.layer?.cornerRadius = 4
            title.frame = CGRect(x: h.minX, y: h.minY + 2, width: max(h.width - tagW - 4, 20), height: h.height - 4)
            body.addSubview(title)
            sectionHeaders.append(title)
            sectionHeaderColors.append(color)
            if section.items.isEmpty {
                let hint = NSTextField(labelWithString: L10n.t("ui.switcher.emptySpace"))
                hint.font = .systemFont(ofSize: 11)
                hint.textColor = .tertiaryLabelColor
                hint.sizeToFit()
                hint.frame.origin = CGPoint(x: h.minX + 8, y: h.maxY + (CGFloat(emptyH) - hint.frame.height) / 2)
                body.addSubview(hint)
            }
        }
        for (i, di) in items.enumerated() where i < layout.cells.count {
            let c = SwitcherCellView(frame: layout.cells[i], index: i, item: di, mode: appearance,
                                     onHover: { [weak self] in self?.onHover?($0) },
                                     onClick: { [weak self] in self?.onClick?($0) },
                                     onClose: { [weak self] in self?.onCloseItem?($0) })
            c.isSelected = i == selection
            c.onDrag = { [weak self] idx, phase, ev in self?.handleDrag(idx, phase, ev) }
            cells.append(c)
            body.addSubview(c)
        }

        let visibleH = min(layout.size.height, maxH)
        let holder = FlippedView(frame: CGRect(x: 0, y: 0, width: layout.size.width, height: visibleH + headerH))
        if layout.size.height > visibleH {
            let scroll = NSScrollView(frame: CGRect(x: 0, y: headerH, width: layout.size.width, height: visibleH))
            scroll.hasVerticalScroller = true
            scroll.drawsBackground = false
            scroll.documentView = body
            holder.addSubview(scroll)
        } else {
            body.frame.origin.y = headerH
            holder.addSubview(body)
        }
        return (holder, holder.frame.size)
    }

    private func handleDrag(_ index: Int, _ phase: SwitcherCellView.DragPhase, _ event: NSEvent) {
        guard let body = sectionBody, let layout = sectionLayout,
              let root = panel?.contentView, cells.indices.contains(index) else { return }
        switch phase {
        case .began:
            dragSource = index
            dragWindowId = itemIDs.indices.contains(index) ? itemIDs[index] : nil  // by id, not index
            let cell = cells[index]
            if let rep = cell.bitmapImageRepForCachingDisplay(in: cell.bounds) {
                cell.cacheDisplay(in: cell.bounds, to: rep)
                let img = NSImage(size: cell.bounds.size)
                img.addRepresentation(rep)
                let ghost = NSImageView(frame: CGRect(origin: .zero, size: cell.bounds.size))
                ghost.image = img
                ghost.alphaValue = 0.75
                root.addSubview(ghost)
                dragGhost = ghost
            }
            cell.alphaValue = 0.35
        case .moved:
            let p = root.convert(event.locationInWindow, from: nil)
            dragGhost?.frame.origin = CGPoint(x: p.x - (dragGhost?.frame.width ?? 0) / 2,
                                              y: p.y - (dragGhost?.frame.height ?? 0) / 2)
            let hovered = SwitcherSections.section(at: body.convert(event.locationInWindow, from: nil),
                                                   layout: layout, visible: body.visibleRect)
            for (i, h) in sectionHeaders.enumerated() {
                h.layer?.backgroundColor = i == hovered
                    ? NSColor.controlAccentColor.withAlphaComponent(0.35).cgColor : nil
                h.textColor = i == hovered ? .labelColor : sectionHeaderColors[i]
            }
        case .ended:
            let target = SwitcherSections.section(at: body.convert(event.locationInWindow, from: nil),
                                                  layout: layout, visible: body.visibleRect)
            let id = dragWindowId
            endDrag()
            if let target, let id, sectionSpaces.indices.contains(target) {
                onDropToSpace?(id, sectionSpaces[target])
            } else {
                onDragEnded?()
            }
        }
    }

    private func endDrag() {
        dragGhost?.removeFromSuperview()
        dragGhost = nil
        if let src = dragSource, cells.indices.contains(src) { cells[src].alphaValue = 1 }
        dragSource = nil
        dragWindowId = nil
        for (i, h) in sectionHeaders.enumerated() {
            h.layer?.backgroundColor = nil
            h.textColor = sectionHeaderColors[i]
        }
    }

    public func updateSelection(_ index: Int) {
        for cell in cells { cell.isSelected = cell.index == index }
        scrollSelectionIntoView(index)
    }

    private func scrollSelectionIntoView(_ index: Int) {
        guard cells.indices.contains(index) else { return }
        cells[index].scrollToVisible(cells[index].bounds)
    }

    public func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> SwitcherKeyPanel {
        let p = SwitcherKeyPanel(contentRect: .zero,
                                 styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: false)
        p.level = .popUpMenu
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.isFloatingPanel = true
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        p.handleKey = { [weak self] ev in self?.onKeyEvent?(ev) ?? false }
        p.didResignKey = { [weak self] in self?.onResignKey?() }
        return p
    }
}

/// Borderless non-activating panel that can optionally become key (sticky mode)
/// and routes keyDown to a closure before AppKit's default handling.
final class SwitcherKeyPanel: NSPanel {
    var acceptsKeys = false
    var handleKey: ((NSEvent) -> Bool)?
    var didResignKey: (() -> Void)?

    override var canBecomeKey: Bool { acceptsKeys }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        if handleKey?(event) == true { return }
        super.keyDown(with: event)
    }

    override func resignKey() {
        super.resignKey()
        if isVisible { didResignKey?() }
    }
}

/// One switcher cell: thumbnail / big icon / title row, selection highlight,
/// hover tracking, click-to-commit, and a ✕ close button on the selected cell.
final class SwitcherCellView: NSView {
    let index: Int
    var isSelected: Bool = false {
        didSet { if isSelected != oldValue { refreshSelection() } }
    }

    private let mode: SwitcherAppearance
    private let onHover: (Int) -> Void
    private let onClick: (Int) -> Void
    private let onClose: (Int) -> Void
    private let closeButton = NSButton()

    init(frame: NSRect, index: Int, item: SwitcherDisplayItem, mode: SwitcherAppearance,
         onHover: @escaping (Int) -> Void, onClick: @escaping (Int) -> Void,
         onClose: @escaping (Int) -> Void) {
        self.index = index
        self.mode = mode
        self.onHover = onHover
        self.onClick = onClick
        self.onClose = onClose
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = mode == .titles ? 6 : 10
        layer?.borderColor = NSColor.controlAccentColor.cgColor

        switch mode {
        case .thumbnails: buildThumbnailCell(item)
        case .icons: buildIconCell(item)
        case .titles: buildTitleRow(item)
        }

        closeButton.bezelStyle = .circular
        closeButton.isBordered = false
        closeButton.title = ""
        closeButton.image = NSImage(systemSymbolName: "xmark.circle.fill",
                                    accessibilityDescription: nil)
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.target = self
        closeButton.action = #selector(closeTapped)
        closeButton.frame = mode == .titles
            ? NSRect(x: frame.width - 24, y: (frame.height - 18) / 2, width: 18, height: 18)
            : NSRect(x: 6, y: 6, width: 18, height: 18)
        closeButton.autoresizingMask = mode == .titles ? [.minXMargin] : []
        closeButton.isHidden = true
        addSubview(closeButton)

        refreshSelection()
    }

    required init?(coder: NSCoder) { fatalError() }

    // Subviews are laid out for a flipped superview; keep the cell flipped too
    // so y grows downward consistently.
    override var isFlipped: Bool { true }

    private func buildThumbnailCell(_ item: SwitcherDisplayItem) {
        let pad: CGFloat = 8
        let labelH: CGFloat = 18
        let imgView = NSImageView(frame: NSRect(x: pad, y: pad, width: frame.width - pad * 2,
                                                height: frame.height - pad * 2 - labelH - 2))
        imgView.imageScaling = .scaleProportionallyUpOrDown
        if let t = item.thumbnail { imgView.image = NSImage(cgImage: t, size: .zero) }
        else { imgView.image = item.icon }
        addSubview(imgView)

        // Small app-icon badge over the thumbnail's bottom-left corner.
        if item.thumbnail != nil {
            let badge = NSImageView(frame: NSRect(x: pad + 2, y: imgView.frame.maxY - 24,
                                                  width: 22, height: 22))
            badge.image = item.icon
            addSubview(badge)
        }

        let label = cellLabel(item, size: 11)
        label.lineBreakMode = .byTruncatingTail
        label.alignment = .center
        label.frame = NSRect(x: pad, y: frame.height - pad - labelH + 2,
                             width: frame.width - pad * 2, height: labelH)
        addSubview(label)

        addSpaceTag(item)
    }

    private func buildIconCell(_ item: SwitcherDisplayItem) {
        let iconSide: CGFloat = min(64, frame.width - 40)
        let icon = NSImageView(frame: NSRect(x: (frame.width - iconSide) / 2, y: 10,
                                             width: iconSide, height: iconSide))
        icon.image = item.icon
        addSubview(icon)

        let label = cellLabel(item, size: 11)
        label.lineBreakMode = .byTruncatingTail
        label.alignment = .center
        label.maximumNumberOfLines = 2
        label.frame = NSRect(x: 6, y: iconSide + 14, width: frame.width - 12,
                             height: frame.height - iconSide - 18)
        addSubview(label)

        addSpaceTag(item)
    }

    private func buildTitleRow(_ item: SwitcherDisplayItem) {
        let icon = NSImageView(frame: NSRect(x: 8, y: (frame.height - 18) / 2,
                                             width: 18, height: 18))
        icon.image = item.icon
        addSubview(icon)

        let space = NSTextField(labelWithString: "S\(item.item.space)")
        space.font = .monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        space.textColor = .secondaryLabelColor
        space.sizeToFit()
        space.frame.origin = CGPoint(x: frame.width - space.frame.width - 30,
                                     y: (frame.height - space.frame.height) / 2)
        space.autoresizingMask = [.minXMargin]
        addSubview(space)

        let label = cellLabel(item, size: 12)
        label.lineBreakMode = .byTruncatingTail
        label.frame = NSRect(x: 34, y: (frame.height - 16) / 2,
                             width: space.frame.minX - 42, height: 16)
        addSubview(label)
    }

    /// Keyword (e.g. project name) first in semibold, app dimmed after it;
    /// the full title is on the tooltip.
    private func cellLabel(_ item: SwitcherDisplayItem, size: CGFloat) -> NSTextField {
        let it = item.item
        let text = NSMutableAttributedString(string: it.keyword, attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
        ])
        if it.keyword != it.app {
            text.append(NSAttributedString(string: "  ·  \(it.app)", attributes: [
                .font: NSFont.systemFont(ofSize: size),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]))
        }
        let label = NSTextField(labelWithAttributedString: text)
        label.toolTip = it.title.isEmpty ? it.app : "\(it.app) — \(it.title)"
        return label
    }

    private func addSpaceTag(_ item: SwitcherDisplayItem) {
        let tag = NSTextField(labelWithString: "S\(item.item.space)")
        tag.font = .monospacedDigitSystemFont(ofSize: 9, weight: .semibold)
        tag.textColor = .white
        tag.wantsLayer = true
        tag.drawsBackground = false
        tag.sizeToFit()
        let w = tag.frame.width + 8
        let holder = NSView(frame: NSRect(x: frame.width - w - 8, y: 8, width: w, height: 15))
        holder.wantsLayer = true
        holder.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        holder.layer?.cornerRadius = 4
        tag.frame.origin = CGPoint(x: 4, y: 1)
        holder.addSubview(tag)
        addSubview(holder)
    }

    private func refreshSelection() {
        layer?.backgroundColor = isSelected
            ? NSColor.white.withAlphaComponent(0.18).cgColor
            : NSColor.white.withAlphaComponent(0.06).cgColor
        layer?.borderWidth = isSelected && mode != .titles ? 2 : 0
        closeButton.isHidden = !isSelected
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeAlways],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { onHover(index) }

    /// Set in sticky (sectioned) mode: a press that moves past the threshold
    /// becomes a drag instead of a click.
    var onDrag: ((_ index: Int, _ phase: DragPhase, _ event: NSEvent) -> Void)?
    enum DragPhase { case began, moved, ended }
    private var pressPoint: NSPoint?
    private var dragging = false

    override func mouseDown(with event: NSEvent) {
        guard onDrag != nil else { onClick(index); return }  // hold mode: click on press
        pressPoint = event.locationInWindow
        dragging = false
    }
    override func mouseDragged(with event: NSEvent) {
        guard let onDrag, let start = pressPoint else { return }
        let p = event.locationInWindow
        if !dragging {
            guard abs(p.x - start.x) + abs(p.y - start.y) > 4 else { return }
            dragging = true
            onDrag(index, .began, event)
        }
        onDrag(index, .moved, event)
    }
    override func mouseUp(with event: NSEvent) {
        guard onDrag != nil, pressPoint != nil else { return }
        pressPoint = nil
        if dragging { dragging = false; onDrag?(index, .ended, event) } else { onClick(index) }
    }
    @objc private func closeTapped() { onClose(index) }
}
