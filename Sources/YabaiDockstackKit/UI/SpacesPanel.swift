import AppKit
import CoreGraphics

public final class SpacesPanel {
    public var onWindowClick: ((Int) -> Void)?
    public var onWindowDrop: ((Int, Int) -> Void)?
    public var onSpaceClick: ((Int) -> Void)?
    public var onSpaceDrop: ((Int, Int) -> Void)?
    public var onKeyEvent: ((NSEvent) -> Bool)?
    public var onResignKey: (() -> Void)?

    private var panel: SpacesKeyPanel?
    private var thumbnails: [Int: CGImage] = [:]
    private var spaceRects: [(id: Int, display: Int, rect: CGRect)] = []
    private var spaceCards: [Int: SpacesCardView] = [:]
    private var windowSpaces: [Int: Int] = [:]
    private var windowPIDs: [Int: Int] = [:]
    private var spaceThumbnails: [Int: [CGImage]] = [:]
    private var dragPreview: SpacesDragPreviewView?
    private var lastDragPoint: CGPoint?
    private var draggingWindowID: Int?
    private var draggingSpaceID: Int?
    private var draggingSourceSpaceID: Int?

    public init() {}

    public var isVisible: Bool { panel?.isVisible ?? false }
    public private(set) var isDragging = false

    public func show(groups: [SpacesDisplayGroup], metrics: SpacesLayoutMetrics,
                     thumbnails: [Int: CGImage],
                     wallpaper: NSImage?,
                     keyboardFocus: Bool) {
        self.thumbnails = thumbnails
        let p = panel ?? makePanel()
        panel = p
        let screen = NSScreen.main ?? NSScreen.screens.first
        let vf = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let maxW = vf.width * 0.86
        let maxH = vf.height * 0.78
        let pad: CGFloat = 18
        let gap: CGFloat = 12
        let sectionHeader: CGFloat = 24
        let cardW = CGFloat(min(metrics.spaceWidth, Double(maxW - pad * 2)))
        let cardH = CGFloat(metrics.spaceHeight)
        let columns = max(1, min(metrics.columns, groups.map { $0.spaces.count }.max() ?? 1))
        let naturalWidth = CGFloat(columns) * (cardW + gap) - gap
        let bodyW = max(cardW, min(CGFloat(maxW - pad * 2), naturalWidth))
        let bodyH = groups.reduce(CGFloat(0)) { result, group in
            let rows = CGFloat((group.spaces.count + columns - 1) / columns)
            return result + sectionHeader + rows * cardH + max(0, rows - 1) * gap + gap
        }
        let body = SpacesFlippedView(frame: CGRect(x: 0, y: 0,
                                                    width: bodyW, height: max(bodyH - gap, 1)))
        spaceRects.removeAll()
        spaceCards.removeAll()
        windowSpaces.removeAll()
        windowPIDs.removeAll()
        spaceThumbnails.removeAll()
        var y: CGFloat = 0

        for group in groups {
            let displayLabel = NSTextField(labelWithString: "Display \(group.id)")
            displayLabel.font = .systemFont(ofSize: 13, weight: .semibold)
            displayLabel.textColor = .secondaryLabelColor
            displayLabel.frame = CGRect(x: 0, y: y, width: bodyW, height: sectionHeader)
            body.addSubview(displayLabel)
            y += sectionHeader

            for (index, space) in group.spaces.enumerated() {
                for window in space.windows {
                    windowSpaces[window.id] = space.id
                    windowPIDs[window.id] = window.pid
                }
                spaceThumbnails[space.id] = space.windows.compactMap { thumbnails[$0.id] }
                let column = index % columns
                let row = index / columns
                let x = CGFloat(column) * (cardW + gap)
                let frame = CGRect(x: x, y: y + CGFloat(row) * (cardH + gap),
                                   width: cardW, height: cardH)
                spaceRects.append((space.id, group.id, frame))
                let card = SpacesCardView(frame: frame, space: space,
                                          thumbnails: thumbnails,
                                          wallpaper: wallpaper,
                                          onWindowClick: { [weak self] id in self?.onWindowClick?(id) },
                                          onWindowDrag: { [weak self] id, point in
                                              self?.windowDragged(id: id, point: point)
                                          },
                                          onWindowDragEnd: { [weak self] id, point in
                                              self?.windowDragEnded(id: id, point: point)
                                          },
                                          onSpaceClick: { [weak self] id in self?.onSpaceClick?(id) },
                                          onSpaceDrag: { [weak self] id, point in
                                              self?.spaceDragged(id: id, point: point)
                                          },
                                          onSpaceDragEnd: { [weak self] id, point in
                                              self?.spaceDragEnded(id: id, point: point)
                                          })
                spaceCards[space.id] = card
                body.addSubview(card)
            }
            let rows = CGFloat((group.spaces.count + columns - 1) / columns)
            y += rows * cardH + max(0, rows - 1) * gap + gap
        }

        let shell = RoundedPanelView(frame: CGRect(x: 0, y: 0,
                               width: bodyW + pad * 2,
                               height: min(bodyH, CGFloat(maxH - pad * 2)) + pad * 2),
                        radius: 16)
        let effect = NSVisualEffectView(frame: shell.bounds)
        effect.autoresizingMask = [.width, .height]
        effect.alphaValue = 1
        effect.material = NSVisualEffectView.Material.hudWindow
        effect.blendingMode = NSVisualEffectView.BlendingMode.behindWindow
        effect.state = NSVisualEffectView.State.active
        body.frame.origin = CGPoint(x: pad, y: pad)
        effect.addSubview(body)
        shell.addSubview(effect)

        let frame = CGRect(x: vf.midX - effect.frame.width / 2,
                           y: vf.midY - effect.frame.height / 2 + vf.height * 0.04,
                           width: effect.frame.width, height: effect.frame.height)
        p.setFrame(frame, display: true)
        p.contentView = shell
        p.acceptsKeys = keyboardFocus
        if keyboardFocus { p.makeKeyAndOrderFront(nil) }
        else { p.orderFrontRegardless() }
    }

    public func hide() { panel?.orderOut(nil) }

    private func windowDragged(id: Int, point: CGPoint) {
        let converted = panelPoint(point)
        guard space(at: converted) != nil else { return }
        beginDrag(windowID: id, spaceID: nil)
        updateDrag(point: converted, excluding: windowSpaces[id])
    }

    private func windowDragEnded(id: Int, point: CGPoint) {
        let converted = panelPoint(point)
        if let target = space(at: converted), target.id != windowSpaces[id] {
            onWindowDrop?(id, target.id)
        }
        endDrag()
    }

    private func spaceDragged(id: Int, point: CGPoint) {
        let point = panelPoint(point)
                guard spaceRects.contains(where: { $0.id == id }), space(at: point) != nil else { return }
        beginDrag(windowID: nil, spaceID: id)
                updateDrag(point: point, excluding: id)
    }

    private func spaceDragEnded(id: Int, point: CGPoint) {
        let point = panelPoint(point)
        if let target = space(at: point) {
            onSpaceDrop?(id, target.id)
        }
        endDrag()
    }

    private func panelPoint(_ point: CGPoint) -> CGPoint {
        guard let content = panel?.contentView,
                            let body = bodyView(in: content) else {
            return point
        }
        let contentPoint = content.convert(point, from: nil)
        let bodyPoint = CGPoint(x: contentPoint.x - body.frame.minX,
                                y: body.frame.maxY - contentPoint.y)
        return bodyPoint
    }

    private func beginDrag(windowID: Int?, spaceID: Int?) {
        if draggingWindowID == windowID && draggingSpaceID == spaceID { return }
        endDrag()
        isDragging = true
        draggingWindowID = windowID
        draggingSpaceID = spaceID
        draggingSourceSpaceID = spaceID ?? windowID.flatMap { windowSpaces[$0] }
        if let id = windowID { draggingWindowID = id }
        if let id = spaceID { spaceCards[id]?.alphaValue = 0.55 }
        if let id = draggingSourceSpaceID { spaceCards[id]?.isDragSource = true }
        let preview = SpacesDragPreviewView(
            title: windowID == nil ? "Moving space" : "Moving window",
            thumbnails: windowID.map { id in thumbnails[id].map { [$0] } ?? [] }
                ?? spaceID.flatMap { spaceThumbnails[$0] } ?? [],
            appIcon: windowID.flatMap { windowPIDs[$0] }
                .flatMap { NSRunningApplication(processIdentifier: pid_t($0))?.icon })
        preview.frame.origin = .zero
        preview.autoresizingMask = []
        panel?.contentView?.addSubview(preview)
        dragPreview = preview
    }

    private func updateDrag(point: CGPoint, excluding sourceSpace: Int?) {
        lastDragPoint = point
        let targetID = space(at: point)?.id
        if let content = panel?.contentView,
              let body = bodyView(in: content) {
            let contentPoint = CGPoint(x: point.x + body.frame.minX,
                                       y: body.frame.maxY - point.y)
            dragPreview?.setFrameOrigin(CGPoint(
                x: contentPoint.x - (dragPreview?.frame.width ?? 0) / 2,
                y: contentPoint.y - (dragPreview?.frame.height ?? 0) / 2))
        }
        for (id, card) in spaceCards {
            card.isDropTarget = targetID != nil && targetID != sourceSpace && id == targetID
        }
    }

    private func bodyView(in view: NSView) -> SpacesFlippedView? {
        if let body = view as? SpacesFlippedView { return body }
        for subview in view.subviews {
            if let body = bodyView(in: subview) { return body }
        }
        return nil
    }

    private func endDrag() {
        if let id = draggingSpaceID { spaceCards[id]?.alphaValue = 1 }
        if let id = draggingSourceSpaceID { spaceCards[id]?.isDragSource = false }
        for card in spaceCards.values { card.isDropTarget = false }
        dragPreview?.removeFromSuperview()
        dragPreview = nil
        lastDragPoint = nil
        draggingWindowID = nil
        draggingSpaceID = nil
        draggingSourceSpaceID = nil
        isDragging = false
    }

    private func space(at point: CGPoint) -> (id: Int, display: Int, rect: CGRect)? {
        spaceRects.first { $0.rect.contains(point) }
    }

    private func makePanel() -> SpacesKeyPanel {
        let p = SpacesKeyPanel(contentRect: .zero,
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
        p.handleKey = { [weak self] event in self?.onKeyEvent?(event) ?? false }
        p.didResignKey = { [weak self] in self?.onResignKey?() }
        return p
    }
}

private final class SpacesKeyPanel: NSPanel {
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

private final class SpacesFlippedView: NSView {
    override var isFlipped: Bool { true }
}

private final class SpacesCardView: NSView {
    private let space: SpacesItem
    private let thumbnails: [Int: CGImage]
    private let wallpaper: NSImage?
    private let onWindowClick: (Int) -> Void
    private let onWindowDrag: (Int, CGPoint) -> Void
    private let onWindowDragEnd: (Int, CGPoint) -> Void
    private let onSpaceClick: (Int) -> Void
    private let onSpaceDrag: (Int, CGPoint) -> Void
    private let onSpaceDragEnd: (Int, CGPoint) -> Void
    private var draggingSpace = false
    private var dragStart: CGPoint?

    var isDragSource = false {
        didSet { updateBorder() }
    }

    var isDropTarget = false {
        didSet { updateBorder() }
    }

    private func updateBorder() {
        if isDropTarget {
            layer?.borderColor = NSColor.controlAccentColor.cgColor
            layer?.borderWidth = 3
        } else if isDragSource {
            layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
            layer?.borderWidth = 1
        } else {
            layer?.borderColor = (space.isVisible ? NSColor.controlAccentColor : NSColor.white.withAlphaComponent(0.12)).cgColor
            layer?.borderWidth = space.isVisible ? 2 : 1
        }
    }

            init(frame: CGRect, space: SpacesItem,
                thumbnails: [Int: CGImage], wallpaper: NSImage?,
         onWindowClick: @escaping (Int) -> Void,
         onWindowDrag: @escaping (Int, CGPoint) -> Void,
         onWindowDragEnd: @escaping (Int, CGPoint) -> Void,
         onSpaceClick: @escaping (Int) -> Void,
         onSpaceDrag: @escaping (Int, CGPoint) -> Void,
         onSpaceDragEnd: @escaping (Int, CGPoint) -> Void) {
        self.space = space
        self.thumbnails = thumbnails
        self.wallpaper = wallpaper
        self.onWindowClick = onWindowClick
        self.onWindowDrag = onWindowDrag
        self.onWindowDragEnd = onWindowDragEnd
        self.onSpaceClick = onSpaceClick
        self.onSpaceDrag = onSpaceDrag
        self.onSpaceDragEnd = onSpaceDragEnd
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor.white.withAlphaComponent(space.isVisible ? 0.14 : 0.07).cgColor
        layer?.borderWidth = space.isVisible ? 2 : 1
        layer?.borderColor = (space.isVisible ? NSColor.controlAccentColor : NSColor.white.withAlphaComponent(0.12)).cgColor

        if let wallpaper {
            let background = WallpaperBackgroundView(frame: bounds, image: wallpaper, radius: 10)
            background.autoresizingMask = [.width, .height]
            addSubview(background)
        }

        let title = NSTextField(labelWithString: space.label ?? "Desktop \(space.id)")
        title.font = .systemFont(ofSize: 12, weight: .semibold)
        title.textColor = .labelColor
        title.frame = CGRect(x: 10, y: 8, width: frame.width - 20, height: 18)
        addSubview(title)

        let body = CGRect(x: 8, y: 34, width: frame.width - 16, height: frame.height - 42)
        let tiles = SpacesLayout.windowTiles(
            aspects: space.windows.map(\.aspectRatio),
            width: Double(body.width), height: Double(body.height))
        for (index, window) in space.windows.enumerated() {
            let tile = CGRect(x: body.minX + tiles[index].minX,
                              y: body.minY + tiles[index].minY,
                              width: tiles[index].width, height: tiles[index].height)
            let cell = SpacesWindowCell(frame: tile,
                                        item: window,
                                        thumbnail: thumbnails[window.id],
                                        onClick: onWindowClick,
                                        onDrag: { [weak self] id, point in
                                            guard let self else { return }
                                            self.onWindowDrag(id, point)
                                        },
                                        onDragEnd: { [weak self] id, point in
                                            guard let self else { return }
                                            self.onWindowDragEnd(id, point)
                                        })
            addSubview(cell)
        }
    }

    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    override func mouseDown(with event: NSEvent) {
        draggingSpace = false
        dragStart = event.locationInWindow
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStart,
              hypot(event.locationInWindow.x - dragStart.x,
                    event.locationInWindow.y - dragStart.y) > 4 else { return }
        draggingSpace = true
        onSpaceDrag(space.id, event.locationInWindow)
    }

    override func mouseUp(with event: NSEvent) {
        if draggingSpace { onSpaceDragEnd(space.id, event.locationInWindow) }
        else { onSpaceClick(space.id) }
        draggingSpace = false
        dragStart = nil
    }
}

private final class SpacesWindowCell: NSView {
    private let item: SpacesWindowItem
    private let thumbnail: CGImage?
    private let onClick: (Int) -> Void
    private let onDrag: (Int, CGPoint) -> Void
    private let onDragEnd: (Int, CGPoint) -> Void
    private var didDrag = false

    init(frame: CGRect, item: SpacesWindowItem, thumbnail: CGImage?,
         onClick: @escaping (Int) -> Void,
         onDrag: @escaping (Int, CGPoint) -> Void,
         onDragEnd: @escaping (Int, CGPoint) -> Void) {
        self.item = item
        self.thumbnail = thumbnail
        self.onClick = onClick
        self.onDrag = onDrag
        self.onDragEnd = onDragEnd
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 6

        let icon = NSImageView(frame: bounds.insetBy(dx: 1, dy: 1))
        icon.image = thumbnail.map { NSImage(cgImage: $0, size: .zero) }
            ?? NSRunningApplication(processIdentifier: pid_t(item.pid))?.icon
            ?? NSWorkspace.shared.icon(for: .applicationBundle)
        icon.imageScaling = .scaleProportionallyUpOrDown
        addSubview(icon)

        let appIconSize = min(26, max(18, min(bounds.width, bounds.height) * 0.24))
        let appIcon = SpacesAppIconView(frame: CGRect(
            x: (bounds.width - appIconSize) / 2,
            y: bounds.height - appIconSize - 1,
            width: appIconSize, height: appIconSize))
        appIcon.image = NSRunningApplication(processIdentifier: pid_t(item.pid))?.icon
            ?? NSWorkspace.shared.icon(for: .applicationBundle)
        appIcon.imageScaling = .scaleProportionallyUpOrDown
        appIcon.wantsLayer = true
        appIcon.layer?.cornerRadius = 4
        appIcon.layer?.shadowColor = NSColor.black.cgColor
        appIcon.layer?.shadowOpacity = 0.55
        appIcon.layer?.shadowRadius = 3
        appIcon.layer?.shadowOffset = .zero
        addSubview(appIcon)
    }

    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    override func mouseDown(with event: NSEvent) { didDrag = false }

    override func mouseDragged(with event: NSEvent) {
        didDrag = true
        onDrag(item.id, event.locationInWindow)
    }

    override func mouseUp(with event: NSEvent) {
        if didDrag { onDragEnd(item.id, event.locationInWindow) }
        else { onClick(item.id) }
    }
}

private final class SpacesDragPreviewView: NSView {
    init(title: String, thumbnails: [CGImage], appIcon: NSImage?) {
        let hasThumbnails = !thumbnails.isEmpty
        let iconOnly = !hasThumbnails && appIcon != nil
        super.init(frame: CGRect(x: 0, y: 0,
                                 width: hasThumbnails ? 180 : (iconOnly ? 56 : 150),
                                 height: hasThumbnails ? 120 : (iconOnly ? 56 : 32)))
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.backgroundColor = !hasThumbnails && !iconOnly
            ? NSColor.black.withAlphaComponent(0.78).cgColor
            : NSColor.clear.cgColor
        if hasThumbnails {
            let gap: CGFloat = 3
            let columns = min(2, thumbnails.count)
            let rows = Int(ceil(Double(thumbnails.count) / Double(columns)))
            let tileWidth = (bounds.width - 10 - CGFloat(columns - 1) * gap) / CGFloat(columns)
            let tileHeight = (bounds.height - 10 - CGFloat(rows - 1) * gap) / CGFloat(rows)
            for (index, thumbnail) in thumbnails.enumerated() {
                let column = index % columns
                let row = index / columns
                let image = NSImageView(frame: CGRect(
                    x: 5 + CGFloat(column) * (tileWidth + gap),
                    y: 5 + CGFloat(row) * (tileHeight + gap),
                    width: tileWidth, height: tileHeight))
                image.image = NSImage(cgImage: thumbnail, size: .zero)
                image.imageScaling = .scaleProportionallyUpOrDown
                addSubview(image)
            }
        } else if !iconOnly {
            let label = NSTextField(labelWithString: title)
            label.font = .systemFont(ofSize: 11, weight: .semibold)
            label.textColor = .white
            label.alignment = .center
            label.frame = bounds.insetBy(dx: 8, dy: 7)
            addSubview(label)
        }

        if let appIcon {
            let size = min(28, max(20, min(bounds.width, bounds.height) * 0.22))
            let icon = SpacesAppIconView(frame: CGRect(x: (bounds.width - size) / 2,
                                                       y: 2,
                                                       width: size, height: size))
            icon.image = appIcon
            icon.imageScaling = .scaleProportionallyUpOrDown
            icon.wantsLayer = true
            icon.layer?.shadowColor = NSColor.black.cgColor
            icon.layer?.shadowOpacity = 0.6
            icon.layer?.shadowRadius = 3
            icon.layer?.shadowOffset = .zero
            addSubview(icon)
        }

        let entrance = CABasicAnimation(keyPath: "transform.scale")
        entrance.fromValue = 0.92
        entrance.toValue = 1.0
        entrance.duration = 0.16
        entrance.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer?.add(entrance, forKey: "spaces-drag-entrance")
    }

    required init?(coder: NSCoder) { fatalError() }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private final class SpacesAppIconView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
