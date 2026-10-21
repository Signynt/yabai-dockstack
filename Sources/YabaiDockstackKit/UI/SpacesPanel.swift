import AppKit
import CoreGraphics

/// The search switcher's view (PR #4's Spaces View look): a search box, then
/// one titled section per display with a mini-desktop card per space; windows
/// are tiled inside their card. Tiles and cards can be dragged onto other
/// cards. Keyboard handling lives in `SwitcherController`.
public final class SpacesPanel {
    public var onHover: ((Int) -> Void)?
    public var onHoverExit: ((Int) -> Void)?
    public var onClick: ((Int) -> Void)?
    public var onCloseItem: ((Int) -> Void)?
    /// (window id, target space)
    public var onWindowDrop: ((Int, Int) -> Void)?
    public var onSpaceClick: ((Int) -> Void)?
    /// (source space, target space)
    public var onSpaceDrop: ((Int, Int) -> Void)?
    /// A drag ended (dropped or not) — re-render now if one was deferred.
    public var onDragEnded: (() -> Void)?
    public var onKeyEvent: ((NSEvent) -> Bool)?
    public var onResignKey: (() -> Void)?

    public private(set) var isDragging = false
    /// Space cards can only be dragged (swapped) with the scripting addition;
    /// without it a card drag shows nothing at all.
    public var spaceDragEnabled = false
    /// Tile frames in body coordinates, by window id (for ↑/↓).
    public private(set) var tileFrames: [Int: CGRect] = [:]

    private var panel: SwitcherKeyPanel?
    private weak var body: FlippedView?
    private var tiles: [Int: SpacesTileView] = [:]
    private var cardViews: [Int: SpacesCardView] = [:]
    private var cardRects: [(space: Int, rect: CGRect, isFullscreen: Bool)] = []
    private var tileSpace: [Int: Int] = [:]
    private var selectedID: Int?
    private var ghost: NSView?
    private var drag: (windowID: Int?, space: Int)?

    public init() {}

    public var isVisible: Bool { panel?.isVisible ?? false }

    public func show(cards: [SpaceCard], thumbnails: [Int: CGImage], wallpaper: NSImage?,
                     query: String, selectedID: Int?) {
        let p = panel ?? makePanel()
        panel = p
        endDrag()
        tiles = [:]; cardViews = [:]; cardRects = []; tileSpace = [:]; tileFrames = [:]
        self.selectedID = selectedID

        let screen = NSScreen.main ?? NSScreen.screens.first
        let vf = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let pad: CGFloat = 18, gap: CGFloat = 12, searchH: CGFloat = 40
        let maxW = vf.width * 0.86 - pad * 2
        let maxH = vf.height * 0.8 - pad * 2 - searchH

        let groups = Dictionary(grouping: cards, by: \.display).sorted { $0.key < $1.key }
        let multiDisplay = groups.count > 1
        let displayH: CGFloat = multiDisplay ? 24 : 0
        // Card size: as large as fits (300 → 200 pt wide), desktop-shaped.
        var cardW: CGFloat = 300, cols = 1
        func bodyHeight(_ w: CGFloat) -> CGFloat {
            cols = max(1, min(cards.count, Int((maxW + gap) / (w + gap))))
            let rows = groups.reduce(0) { $0 + ($1.value.count + cols - 1) / cols }
            return CGFloat(groups.count) * displayH + CGFloat(rows) * (w * 0.62 + gap) - gap
        }
        while cardW > 200 && bodyHeight(cardW) > maxH { cardW -= 10 }
        let bodyH = bodyHeight(cardW)
        let cardH = (cardW * 0.62).rounded()
        let usedCols = min(cols, groups.map(\.value.count).max() ?? 1)
        let bodyW = max(CGFloat(usedCols) * (cardW + gap) - gap, 360)

        let body = FlippedView(frame: CGRect(x: 0, y: 0, width: bodyW, height: max(bodyH, 1)))
        self.body = body
        var y: CGFloat = 0
        for (display, group) in groups {
            if multiDisplay {
                let label = NSTextField(labelWithString: String(format: L10n.t("ui.menu.displayN"), display))
                label.font = .systemFont(ofSize: 12, weight: .bold)
                label.textColor = .secondaryLabelColor
                label.frame = CGRect(x: 2, y: y + 3, width: bodyW, height: 18)
                body.addSubview(label)
                y += displayH
            }
            for (i, card) in group.enumerated() {
                let frame = CGRect(x: CGFloat(i % cols) * (cardW + gap),
                                   y: y + CGFloat(i / cols) * (cardH + gap), width: cardW, height: cardH)
                let view = SpacesCardView(frame: frame, card: card, wallpaper: wallpaper)
                view.onPress = { [weak self] phase, ev in self?.cardPressed(card, phase, ev) }
                body.addSubview(view)
                cardViews[card.space] = view
                cardRects.append((card.space, frame, card.isFullscreen))
                for (tile, rect) in zip(card.tiles, view.tileRects) {
                    let tv = SpacesTileView(frame: rect, tile: tile, thumbnail: thumbnails[tile.item.id])
                    tv.isSelected = tile.item.id == selectedID
                    tv.onHover = { [weak self] in self?.onHover?($0) }
                    tv.onHoverExit = { [weak self] in self?.onHoverExit?($0) }
                    tv.onClose = { [weak self] in self?.onCloseItem?($0) }
                    tv.onPress = { [weak self] phase, ev in
                        self?.tilePressed(tile.item.id, card.space, draggable: !card.isFullscreen, phase, ev)
                    }
                    view.addSubview(tv)
                    tiles[tile.item.id] = tv
                    tileSpace[tile.item.id] = card.space
                    tileFrames[tile.item.id] = rect.offsetBy(dx: frame.minX, dy: frame.minY)
                }
            }
            y += CGFloat((group.count + cols - 1) / cols) * (cardH + gap)
        }

        // Body, scrolling when taller than the screen allows.
        let visibleH = min(body.frame.height, maxH)
        let scrolls = body.frame.height > visibleH
        let scrollerW = scrolls ? NSScroller.scrollerWidth(for: .regular, scrollerStyle: NSScroller.preferredScrollerStyle) : 0
        let content = FlippedView(frame: CGRect(x: pad, y: pad, width: bodyW + scrollerW, height: searchH + visibleH))
        addSwitcherSearchBox(to: content, width: content.frame.width, query: query)
        if scrolls {
            let scroll = NSScrollView(frame: CGRect(x: 0, y: searchH, width: bodyW + scrollerW, height: visibleH))
            scroll.hasVerticalScroller = true
            scroll.drawsBackground = false
            scroll.documentView = body
            content.addSubview(scroll)
        } else {
            body.frame.origin.y = searchH
            content.addSubview(body)
        }

        let size = CGSize(width: content.frame.width + pad * 2, height: content.frame.height + pad * 2)
        let shell = RoundedPanelView(frame: CGRect(origin: .zero, size: size), radius: 16)
        let effect = NSVisualEffectView(frame: shell.bounds)
        effect.autoresizingMask = [.width, .height]
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.addSubview(content)
        shell.addSubview(effect)

        p.setFrame(CGRect(x: vf.midX - size.width / 2, y: vf.midY - size.height / 2 + vf.height * 0.04,
                          width: size.width, height: size.height), display: true)
        p.contentView = shell
        p.acceptsKeys = true
        p.makeKeyAndOrderFront(nil)
        scrollIntoView(selectedID)
    }

    public func updateSelection(_ id: Int?) {
        if let old = selectedID { tiles[old]?.isSelected = false }
        selectedID = id
        if let id { tiles[id]?.isSelected = true }
        scrollIntoView(id)
    }

    /// Take key status back (our own SA move may have activated another app).
    public func regainKey() { panel?.makeKeyAndOrderFront(nil) }

    public func hide() {
        endDrag()
        panel?.orderOut(nil)
    }

    private func scrollIntoView(_ id: Int?) {
        guard let id, let r = tileFrames[id], let body, body.enclosingScrollView != nil else { return }
        body.scrollToVisible(r.insetBy(dx: 0, dy: -8))
    }

    // MARK: - Drag & drop

    private func tilePressed(_ id: Int, _ space: Int, draggable: Bool, _ phase: PressPhase, _ ev: NSEvent) {
        switch phase {
        case .click: onClick?(id)
        case .began:
            guard draggable, let tv = tiles[id] else { return }
            beginDrag(windowID: id, space: space, snapshotOf: tv, scale: 1)
        case .moved: moveDrag(ev)
        case .ended: finishDrag(ev)
        }
    }

    private func cardPressed(_ card: SpaceCard, _ phase: PressPhase, _ ev: NSEvent) {
        switch phase {
        case .click: onSpaceClick?(card.space)
        case .began:
            guard spaceDragEnabled, !card.isFullscreen, let cv = cardViews[card.space] else { return }
            beginDrag(windowID: nil, space: card.space, snapshotOf: cv, scale: 0.6)
        case .moved: moveDrag(ev)
        case .ended: finishDrag(ev)
        }
    }

    private func beginDrag(windowID: Int?, space: Int, snapshotOf view: NSView, scale: CGFloat) {
        guard let root = panel?.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        let img = NSImage(size: view.bounds.size)
        img.addRepresentation(rep)
        let g = NSImageView(frame: CGRect(x: 0, y: 0, width: view.bounds.width * scale,
                                          height: view.bounds.height * scale))
        g.image = img
        g.imageScaling = .scaleProportionallyUpOrDown
        g.alphaValue = 0.8
        root.addSubview(g)
        ghost = g
        drag = (windowID, space)
        isDragging = true
        (windowID.flatMap { tiles[$0] } ?? cardViews[space])?.alphaValue = 0.4
    }

    private func moveDrag(_ ev: NSEvent) {
        guard let drag, let root = panel?.contentView else { return }
        let p = root.convert(ev.locationInWindow, from: nil)
        if let g = ghost { g.frame.origin = CGPoint(x: p.x - g.frame.width / 2, y: p.y - g.frame.height / 2) }
        let target = dropTarget(ev)
        for (space, cv) in cardViews { cv.isDropTarget = space == target && space != drag.space }
    }

    private func finishDrag(_ ev: NSEvent) {
        guard let drag else { return }
        let target = dropTarget(ev)
        endDrag()
        if let target, target != drag.space {
            if let id = drag.windowID { onWindowDrop?(id, target) } else { onSpaceDrop?(drag.space, target) }
        }
        onDragEnded?()
    }

    private func dropTarget(_ ev: NSEvent) -> Int? {
        guard let body else { return nil }
        return SpacesInteraction.dropTarget(at: body.convert(ev.locationInWindow, from: nil),
                                            cards: cardRects, visible: body.visibleRect)
    }

    private func endDrag() {
        ghost?.removeFromSuperview()
        ghost = nil
        if let drag { (drag.windowID.flatMap { tiles[$0] } ?? cardViews[drag.space])?.alphaValue = 1 }
        drag = nil
        isDragging = false
        for cv in cardViews.values { cv.isDropTarget = false }
    }

    private func makePanel() -> SwitcherKeyPanel {
        let p = SwitcherKeyPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
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

enum PressPhase { case click, began, moved, ended }

/// Press → click or drag (past 4 pt), reported through `onPress`.
private class PressTrackingView: NSView {
    var onPress: ((PressPhase, NSEvent) -> Void)?
    var pressEnabled = true
    private var start: NSPoint?
    private var dragging = false

    override var isFlipped: Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard pressEnabled else { return }
        start = event.locationInWindow
        dragging = false
    }
    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        let p = event.locationInWindow
        if !dragging {
            guard abs(p.x - start.x) + abs(p.y - start.y) > 4 else { return }
            dragging = true
            onPress?(.began, event)
        }
        onPress?(.moved, event)
    }
    override func mouseUp(with event: NSEvent) {
        guard start != nil else { return }
        start = nil
        if dragging { dragging = false; onPress?(.ended, event) } else { onPress?(.click, event) }
    }
}

/// One space: title, Current / Visible tag, optional wallpaper, tiled windows.
private final class SpacesCardView: PressTrackingView {
    let tileRects: [CGRect]
    private let card: SpaceCard

    var isDropTarget = false { didSet { updateBorder() } }

    init(frame: CGRect, card: SpaceCard, wallpaper: NSImage?) {
        self.card = card
        let header: CGFloat = 26, inset: CGFloat = 7
        let area = CGRect(x: inset, y: header, width: frame.width - inset * 2, height: frame.height - header - inset)
        tileRects = SpacesLayout.windowTiles(aspects: card.tiles.map(\.aspect), width: Double(area.width),
                                             height: Double(area.height))
            .map { $0.offsetBy(dx: area.minX, dy: area.minY) }
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor.white.withAlphaComponent(card.hasFocus ? 0.14 : 0.07).cgColor
        if let wallpaper {
            let bg = WallpaperBackgroundView(frame: bounds, image: wallpaper, radius: 10)
            bg.autoresizingMask = [.width, .height]
            addSubview(bg)
        }
        alphaValue = card.isFullscreen ? 0.6 : 1

        var tagW: CGFloat = 0
        if card.hasFocus || card.isVisible {
            let tag = NSTextField(labelWithString: L10n.t(card.hasFocus ? "ui.switcher.currentSpace"
                                                                        : "ui.switcher.visibleSpace"))
            tag.font = .systemFont(ofSize: 10, weight: .bold)
            tag.textColor = card.hasFocus ? .white : .labelColor
            tag.alignment = .center
            tag.wantsLayer = true
            tag.layer?.cornerRadius = 4
            tag.layer?.backgroundColor = (card.hasFocus ? NSColor.systemGreen
                                          : NSColor.white.withAlphaComponent(0.18)).cgColor
            tag.sizeToFit()
            tagW = tag.frame.width + 10
            tag.frame = CGRect(x: frame.width - tagW - 8, y: 6, width: tagW, height: tag.frame.height)
            addSubview(tag)
        }
        let title = NSTextField(labelWithString: card.name)
        title.font = .systemFont(ofSize: 12, weight: .semibold)
        title.textColor = .labelColor
        title.lineBreakMode = .byTruncatingTail
        title.frame = CGRect(x: 10, y: 5, width: frame.width - 20 - tagW, height: 17)
        addSubview(title)
        updateBorder()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func updateBorder() {
        if isDropTarget {
            layer?.borderColor = NSColor.controlAccentColor.cgColor
            layer?.borderWidth = 3
        } else if card.hasFocus {
            layer?.borderColor = NSColor.systemGreen.cgColor
            layer?.borderWidth = 2
        } else {
            layer?.borderColor = NSColor.white.withAlphaComponent(card.isVisible ? 0.35 : 0.12).cgColor
            layer?.borderWidth = 1
        }
    }
}

/// One window: thumbnail (or app icon), a capsule with the app icon and the
/// project keyword, ✕ when selected. Non-matching tiles are dimmed and inert.
private final class SpacesTileView: PressTrackingView {
    var onHover: ((Int) -> Void)?
    var onHoverExit: ((Int) -> Void)?
    var onClose: ((Int) -> Void)?
    var isSelected = false { didSet { refreshSelection() } }

    private let id: Int
    private let matches: Bool
    private let preview: NSView
    private let closeButton = NSButton()

    init(frame: CGRect, tile: SpaceTile, thumbnail: CGImage?) {
        id = tile.item.id
        matches = tile.matches
        preview = NSView(frame: .zero)
        super.init(frame: frame)
        pressEnabled = matches
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.masksToBounds = true
        alphaValue = matches ? 1 : 0.25
        toolTip = tile.item.title.isEmpty ? tile.item.app : "\(tile.item.app) — \(tile.item.title)"

        let appIcon = NSRunningApplication(processIdentifier: pid_t(tile.item.pid))?.icon
            ?? NSWorkspace.shared.icon(for: .applicationBundle)
        let aspect = thumbnail.map { CGFloat($0.width) / CGFloat(max($0.height, 1)) }
            ?? CGFloat(max(tile.aspect, 0.1))
        let previewRect = Self.aspectFitRect(aspect: aspect, in: bounds)
        preview.frame = previewRect
        preview.wantsLayer = true
        preview.layer?.cornerRadius = 2
        preview.layer?.masksToBounds = true
        preview.layer?.borderColor = NSColor.controlAccentColor.cgColor
        addSubview(preview)

        let image = NSImageView(frame: preview.bounds)
        image.image = thumbnail.map { NSImage(cgImage: $0, size: .zero) } ?? appIcon
        image.imageScaling = .scaleProportionallyUpOrDown
        preview.addSubview(image)

        // Capsule: app icon + project keyword, bottom-center.
        let iconSide: CGFloat = 14, pillH: CGFloat = 20
        let label = NSTextField(labelWithString: tile.item.keyword.isEmpty ? tile.item.app : tile.item.keyword)
        label.font = .systemFont(ofSize: 10, weight: .semibold)
        label.textColor = .white
        label.lineBreakMode = .byTruncatingTail
        label.sizeToFit()
        let pillW = min(label.frame.width + iconSide + 16, bounds.width - 6)
        let pill = NSView(frame: CGRect(x: (bounds.width - pillW) / 2,
                                        y: bounds.height - pillH - 3,
                                        width: max(pillW, iconSide + 10), height: pillH))
        pill.wantsLayer = true
        pill.layer?.cornerRadius = pillH / 2
        pill.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        let icon = NSImageView(frame: CGRect(x: 5, y: (pillH - iconSide) / 2, width: iconSide, height: iconSide))
        icon.image = appIcon
        pill.addSubview(icon)
        label.frame = CGRect(x: iconSide + 8, y: (pillH - label.frame.height) / 2,
                             width: max(pill.frame.width - iconSide - 13, 0), height: label.frame.height)
        pill.addSubview(label)
        if SpacesInteraction.pillFits(bounds.size) { addSubview(pill) }

        closeButton.bezelStyle = .circular
        closeButton.isBordered = false
        closeButton.title = ""
        closeButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: nil)
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.target = self
        closeButton.action = #selector(closeTapped)
        closeButton.frame = NSRect(x: 4, y: preview.bounds.height - 22, width: 18, height: 18)
        closeButton.isHidden = true
        preview.addSubview(closeButton)

        if matches {
            addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                           owner: self, userInfo: nil))
        }
        refreshSelection()
    }

    required init?(coder: NSCoder) { fatalError() }

    private static func aspectFitRect(aspect: CGFloat, in bounds: CGRect) -> CGRect {
        let boundedAspect = max(aspect, 0.1)
        let width = min(bounds.width, bounds.height * boundedAspect)
        let height = min(bounds.height, bounds.width / boundedAspect)
        return CGRect(x: bounds.midX - width / 2, y: bounds.midY - height / 2,
                      width: width, height: height)
    }

    override func mouseEntered(with event: NSEvent) { onHover?(id) }
    override func mouseExited(with event: NSEvent) { onHoverExit?(id) }

    /// Clicks on a dimmed tile fall through to its card (no window action).
    override func hitTest(_ point: NSPoint) -> NSView? { pressEnabled ? super.hitTest(point) : nil }

    private func refreshSelection() {
        preview.layer?.backgroundColor = isSelected ? NSColor.white.withAlphaComponent(0.2).cgColor : nil
        preview.layer?.borderWidth = isSelected ? 2.5 : 0
        closeButton.isHidden = !isSelected
    }

    @objc private func closeTapped() { onClose?(id) }
}
