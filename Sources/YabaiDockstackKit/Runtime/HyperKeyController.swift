import AppKit
import CoreGraphics
import IOKit
import IOKit.hidsystem

/// Runs the Hyper Key: `hidutil` remaps the chosen source key to F18, and an
/// HID-level event tap turns "F18 held" into ⌃⌥⌘(⇧) on every other key. The tap
/// sits at the HID level so it runs before skhd's session tap whatever their
/// start order. Requires Accessibility; without it the mapping is removed so
/// the source key is never left dead. Main thread only.
public final class HyperKeyController {
    private static let f18KeyCode: Int64 = 79
    private static let escKeyCode: CGKeyCode = 53

    private var reducer = HyperKeyReducer()
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var quickPress: HyperQuickPress = .none
    private var flags: CGEventFlags = []

    public init() {}

    public var isRunning: Bool { tap != nil }

    /// `.none` (or missing Accessibility) disables: removes our mapping, stops the tap.
    public func apply(source: HyperSource, quickPress: HyperQuickPress, includeShift: Bool) {
        let active = source != .none && PermissionsHelper.hasAccessibility()
        setMapping(active ? source : .none)
        self.quickPress = quickPress
        flags = [.maskControl, .maskAlternate, .maskCommand]
        if includeShift { flags.insert(.maskShift) }
        if active { startTap() } else { stopTap() }
    }

    public func shutdown() {
        apply(source: .none, quickPress: .none, includeShift: true)
    }

    // MARK: - hidutil

    private func setMapping(_ source: HyperSource) {
        let current = HyperKeyMapping.parse(Self.hidutil(["property", "--get", "UserKeyMapping"]))
        let next = HyperKeyMapping.merged(existing: current, source: source)
        guard next != current else { return }
        _ = Self.hidutil(["property", "--set", HyperKeyMapping.hidutilJSON(next)])
    }

    @discardableResult
    private static func hidutil(_ args: [String]) -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        proc.arguments = args
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do { try proc.run() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - Event tap

    private func startTap() {
        guard tap == nil else { return }
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let me = Unmanaged<HyperKeyController>.fromOpaque(refcon).takeUnretainedValue()
            return me.handle(type: type, event: event)
        }
        let me = Unmanaged.passUnretained(self).toOpaque()
        // HID level first (ahead of skhd); fall back to a session tap if refused.
        guard let port = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap,
                                           options: .defaultTap, eventsOfInterest: mask,
                                           callback: callback, userInfo: me)
                ?? CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                     options: .defaultTap, eventsOfInterest: mask,
                                     callback: callback, userInfo: me) else {
            NSLog("yabai-dockstack: hyper key tap could not be created")
            return
        }
        tap = port
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        runLoopSource = src
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
    }

    private func stopTap() {
        if let port = tap { CGEvent.tapEnable(tap: port, enable: false) }
        if let src = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes) }
        tap = nil
        runLoopSource = nil
        reducer = HyperKeyReducer()
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let port = tap { CGEvent.tapEnable(tap: port, enable: true) }
            reducer = HyperKeyReducer()  // the F18 release may have been missed
            return Unmanaged.passUnretained(event)
        }
        let isHyper = event.getIntegerValueField(.keyboardEventKeycode) == Self.f18KeyCode
        let e: HyperKeyReducer.Event
        switch (type, isHyper) {
        case (.keyDown, true): e = .hyperDown
        case (.keyUp, true): e = .hyperUp
        case (.keyDown, false): e = .keyDown
        case (.keyUp, false): e = .keyUp
        default: return Unmanaged.passUnretained(event)
        }
        switch reducer.handle(e) {
        case .pass:
            return Unmanaged.passUnretained(event)
        case .addHyperFlags:
            event.flags = event.flags.union(flags)
            return Unmanaged.passUnretained(event)
        case .swallow:
            return nil
        case .quickPress:
            DispatchQueue.main.async { [quickPress] in Self.perform(quickPress) }
            return nil
        }
    }

    private static func perform(_ action: HyperQuickPress) {
        switch action {
        case .none:
            break
        case .escape:
            let src = CGEventSource(stateID: .hidSystemState)
            CGEvent(keyboardEventSource: src, virtualKey: escKeyCode, keyDown: true)?.post(tap: .cghidEventTap)
            CGEvent(keyboardEventSource: src, virtualKey: escKeyCode, keyDown: false)?.post(tap: .cghidEventTap)
        case .toggleCapsLock:
            toggleCapsLock()
        }
    }

    private static func toggleCapsLock() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(kIOHIDSystemClass))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }
        var conn: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, UInt32(kIOHIDParamConnectType), &conn) == KERN_SUCCESS else { return }
        defer { IOServiceClose(conn) }
        var on = false
        IOHIDGetModifierLockState(conn, Int32(kIOHIDCapsLockState), &on)
        IOHIDSetModifierLockState(conn, Int32(kIOHIDCapsLockState), !on)
    }
}
