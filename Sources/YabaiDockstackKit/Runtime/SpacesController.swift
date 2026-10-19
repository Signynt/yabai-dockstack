import AppKit

/// Coordinates the sticky Spaces View, its cached snapshot, and serialized
/// yabai mutations triggered by drag-and-drop.
public final class SpacesController {
    private let client: YabaiClient
    private let cache: ThumbnailCache
    private let capturer = ThumbnailCapturer()
    private let visibilityProbe = WindowVisibilityProbe()
    private let panel = SpacesPanel()
    private let mutationQueue = DispatchQueue(label: "yabai-dockstack.spaces-mutations")
    private let activeSpaceQueue = DispatchQueue(label: "yabai-dockstack.active-space-refresh")
    private var focusDestination: Bool
    private var wallpaperEnabled: Bool
    private var wallpaperPath: String
    private var wallpaperDarkPath: String
    private var wallpaper: NSImage?
    private var spaces: [SpaceInfo] = []
    private var windows: [YabaiWindow] = []
    private var labels: [Int: String] = [:]
    private var hiddenWindowIDs: Set<Int> = []
    private var generation = 0
    private var wallpaperGeneration = 0
    private var sticky = false

    public init(client: YabaiClient, cache: ThumbnailCache,
                focusDestination: Bool = false, wallpaperEnabled: Bool = false,
                wallpaperPath: String = "", wallpaperDarkPath: String = "") {
        self.client = client
        self.cache = cache
        self.focusDestination = focusDestination
        self.wallpaperEnabled = wallpaperEnabled
        self.wallpaperPath = wallpaperPath
        self.wallpaperDarkPath = wallpaperDarkPath
        panel.onWindowClick = { [weak self] id in
            self?.focusWindow(id)
            self?.cancel()
        }
        panel.onWindowDrop = { [weak self] id, space in self?.moveWindow(id: id, to: space) }
        panel.onSpaceClick = { [weak self] id in
            self?.focusSpace(id)
            self?.cancel()
        }
        panel.onSpaceDrop = { [weak self] source, target in
            self?.moveSpaceWindows(from: source, to: target)
        }
        panel.onKeyEvent = { [weak self] event in self?.handleKey(event) ?? false }
        // Focus can move while a window or space transition is in progress.
        // Spaces View is dismissed only by an explicit click, Escape, or toggle.
        panel.onResignKey = { }
    }

    public var isOpen: Bool { panel.isVisible }

    private func hiddenIDs(for windows: [YabaiWindow]) -> Set<Int> {
        var hidden = visibilityProbe.hiddenWindowIDs(windows)
        if let live = visibilityProbe.liveWindowIDs(windows) {
            hidden.formUnion(windows.map(\.id).filter { !live.contains($0) })
        }
        return hidden
    }

    public func updateFocusDestination(_ enabled: Bool) {
        focusDestination = enabled
    }

    /// Fast path for NSWorkspace.activeSpaceDidChangeNotification. It refreshes
    /// only space visibility, leaving window data and thumbnails untouched.
    public func refreshActiveSpaces() {
        guard panel.isVisible else { return }
        let nextGeneration = generation + 1
        generation = nextGeneration
        activeSpaceQueue.async { [weak self] in
            guard let self else { return }
            let spaces = self.client.querySpacesInfo()
            DispatchQueue.main.async {
                guard nextGeneration == self.generation, self.panel.isVisible else { return }
                self.spaces = spaces
                if !self.panel.isDragging { self.render() }
            }
        }
    }

    public func updateWallpaper(_ enabled: Bool, path: String, darkPath: String) {
        wallpaperEnabled = enabled
        wallpaperPath = path
        wallpaperDarkPath = darkPath
        refreshWallpaper()
    }

    public func refreshWallpaper() {
        wallpaperGeneration += 1
        let request = wallpaperGeneration
        guard wallpaperEnabled else {
            wallpaper = nil
            if panel.isVisible && !panel.isDragging { render() }
            return
        }
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let path = isDark && !wallpaperDarkPath.isEmpty ? wallpaperDarkPath : wallpaperPath
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let image = path.isEmpty ? nil : NSImage(contentsOfFile: path)
            DispatchQueue.main.async {
                guard let self, self.wallpaperGeneration == request else { return }
                self.wallpaper = image
                if self.panel.isVisible && !self.panel.isDragging { self.render() }
            }
        }
    }

    /// Receives the refresh coordinator's callback on a worker queue.
    public func noteSnapshot(windows: [YabaiWindow], spaces: [SpaceInfo],
                             labels: [Int: String]) {
        let hidden = hiddenIDs(for: windows)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.windows = windows
            self.spaces = spaces
            self.labels = labels
            self.hiddenWindowIDs = hidden
            if self.panel.isVisible && !self.panel.isDragging {
                self.render()
                self.warmThumbnails(windows, hiddenIDs: hidden)
            }
        }
    }

    @discardableResult
    public func open(sticky: Bool = true) -> Bool {
        self.sticky = sticky
        refreshWallpaper()
        render()
        refreshAsync()
        return true
    }

    public func cancel() {
        generation += 1
        sticky = false
        panel.hide()
    }

    private func render() {
        guard !panel.isDragging else { return }
        let visibleWindows = SpacesModel.displayableWindows(windows, hiddenIDs: hiddenWindowIDs)
        let groups = SpacesModel.build(spaces: spaces, windows: visibleWindows, labels: labels)
        let metrics = SpacesLayout.metrics(
            displayCount: groups.reduce(0) { $0 + $1.spaces.count },
            maxWidth: 1100, maxHeight: 700)
        let ids = groups.flatMap { $0.spaces }.flatMap { $0.windows }.map(\.id)
        let thumbnails = Dictionary(uniqueKeysWithValues: ids.compactMap { id in
            cache.get(id).map { (id, $0) }
        })
        panel.show(groups: groups, metrics: metrics, thumbnails: thumbnails,
               wallpaper: wallpaper, keyboardFocus: sticky)
    }

    private func warmThumbnails(_ windows: [YabaiWindow], hiddenIDs: Set<Int>) {
        let ids = Set(SpacesModel.displayableWindows(windows, hiddenIDs: hiddenIDs).map(\.id))
        guard !ids.isEmpty else { return }
        Task { [weak self] in
            guard let self else { return }
            let fresh = await self.capturer.captureOnScreen(windowIDs: ids)
            for (id, image) in fresh { self.cache.put(id, image) }
            await MainActor.run {
                guard self.panel.isVisible, !self.panel.isDragging else { return }
                self.render()
            }
        }
    }

    private func focusWindow(_ id: Int) {
        DispatchQueue.global(qos: .userInitiated).async { [client] in
            client.focus(windowId: id)
        }
    }

    private func focusSpace(_ id: Int) {
        DispatchQueue.global(qos: .userInitiated).async { [client] in
            client.focus(spaceId: id)
        }
    }

    private func moveWindow(id: Int, to space: Int) {
        guard let window = windows.first(where: { $0.id == id }), window.space != space else { return }
        mutationQueue.async { [weak self] in
            guard let self else { return }
            self.client.moveWindow(id: id, toSpace: space,
                                   focusDestination: self.focusDestination)
            self.refreshAsync()
        }
    }

    private func moveSpaceWindows(from source: Int, to target: Int) {
        guard source != target else { return }
        let displayable = SpacesModel.displayableWindows(windows, hiddenIDs: hiddenWindowIDs)
        let sourceWindows = displayable.filter { $0.space == source }
        let targetWindows = displayable.filter { $0.space == target }
        guard !sourceWindows.isEmpty || !targetWindows.isEmpty else { return }
        mutationQueue.async { [weak self] in
            guard let self else { return }
            for window in sourceWindows {
                self.client.moveWindow(id: window.id, toSpace: target,
                                       focusDestination: false)
            }
            for window in targetWindows {
                self.client.moveWindow(id: window.id, toSpace: source,
                                       focusDestination: false)
            }
            self.refreshAsync()
        }
    }

    private func refreshAsync() {
        generation += 1
        let currentGeneration = generation
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let windows = self.client.queryWindows()
            let spaces = self.client.querySpacesInfo()
            let labels = self.client.querySpaceLabels()
            let hidden = self.hiddenIDs(for: windows)
            DispatchQueue.main.async {
                guard currentGeneration == self.generation, self.panel.isVisible else { return }
                self.windows = windows
                self.spaces = spaces
                self.labels = labels
                self.hiddenWindowIDs = hidden
                self.render()
            }
            Task { [weak self] in
                guard let self else { return }
                let fresh = await self.capturer.captureOnScreen(windowIDs: Set(windows.map(\.id)))
                for (id, image) in fresh { self.cache.put(id, image) }
                await MainActor.run {
                    guard currentGeneration == self.generation, self.panel.isVisible else { return }
                    self.render()
                }
            }
        }
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        if event.keyCode == 0x35 { cancel(); return true }
        if event.keyCode == 0x24 || event.keyCode == 0x4C { cancel(); return true }
        return false
    }
}
