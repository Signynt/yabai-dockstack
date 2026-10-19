import ApplicationServices
import AppKit
import CoreGraphics

/// Best-effort detection of windows that should not appear in the Spaces View.
/// Yabai's is-visible describes stack membership, not minimized/app-hidden state.
public final class WindowVisibilityProbe {
    public init() {}

    /// Returns yabai ids still represented by a real macOS window. A nil result
    /// means the window-list query was unavailable, so callers should preserve
    /// the yabai data instead of hiding everything.
    public func liveWindowIDs(_ windows: [YabaiWindow]) -> Set<Int>? {
        guard let raw = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID)
                as? [[String: Any]] else { return nil }
        let ids = raw.compactMap { ($0[kCGWindowNumber as String] as? NSNumber)?.intValue }
        guard !ids.isEmpty else { return nil }
        let candidates = Set(ids)
        return Set(windows.map(\.id).filter { candidates.contains($0) })
    }

    /// Returns yabai window ids that are minimized or owned by a hidden app.
    /// A missing Accessibility grant is treated as "unknown", not hidden.
    public func hiddenWindowIDs(_ windows: [YabaiWindow]) -> Set<Int> {
        guard AXIsProcessTrusted() else { return [] }
        var hidden = Set<Int>()
        let byPID = Dictionary(grouping: windows, by: \.pid)

        for (pid, appWindows) in byPID {
            let application = NSRunningApplication(processIdentifier: pid_t(pid))
            if application?.isHidden == true {
                hidden.formUnion(appWindows.map(\.id))
                continue
            }

            let axApplication = AXUIElementCreateApplication(pid_t(pid))
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(axApplication,
                                                kAXWindowsAttribute as CFString,
                                                &value) == .success,
                  let axWindows = value as? [AXUIElement] else { continue }

            for axWindow in axWindows {
                var minimizedValue: CFTypeRef?
                guard AXUIElementCopyAttributeValue(axWindow,
                                                    kAXMinimizedAttribute as CFString,
                                                    &minimizedValue) == .success,
                      (minimizedValue as? NSNumber)?.boolValue == true else { continue }
                if let id = matchingWindowID(of: axWindow, in: appWindows) {
                    hidden.insert(id)
                }
            }
        }
        return hidden
    }

    private func matchingWindowID(of window: AXUIElement,
                                  in windows: [YabaiWindow]) -> Int? {
        var value: CFTypeRef?
        let title: String?
        if AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString,
                                         &value) == .success {
            title = value as? String
        } else {
            title = nil
        }
        let titleMatches = title.map { value in windows.filter { $0.title == value } } ?? []
        if titleMatches.count == 1 { return titleMatches[0].id }

        guard let axFrame = frame(of: window) else {
            return windows.count == 1 ? windows[0].id : nil
        }
        let frameMatches = windows.filter { distance($0.frame, axFrame) < 8 }
        if frameMatches.count == 1 { return frameMatches[0].id }
        return windows.count == 1 ? windows[0].id : nil
    }

    private func frame(of window: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString,
                                            &positionValue) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString,
                                            &sizeValue) == .success,
              let positionValue,
              let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }
        let positionAX = positionValue as! AXValue
        let sizeAX = sizeValue as! AXValue
        var origin = CGPoint.zero
        var size = CGSize.zero
          guard AXValueGetValue(positionAX, .cgPoint, &origin),
              AXValueGetValue(sizeAX, .cgSize, &size) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    private func distance(_ window: YRect, _ axFrame: CGRect) -> Double {
        abs(window.x - axFrame.origin.x) + abs(window.y - axFrame.origin.y)
            + abs(window.w - axFrame.width) + abs(window.h - axFrame.height)
    }
}
