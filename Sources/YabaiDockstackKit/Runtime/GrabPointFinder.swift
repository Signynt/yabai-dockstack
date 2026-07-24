import AppKit
import ApplicationServices

/// Probes what UI element sits at a global point, so the space-move drag can
/// avoid grabbing controls (search bars, buttons, tabs) that would activate or
/// hijack the drag instead of lifting the window.
public protocol GrabPointProbing {
    /// AX role of the deepest element at a global (top-left origin) point,
    /// or nil when the hit-test fails.
    func role(at point: CGPoint) -> String?
}

public final class AXGrabPointProbe: GrabPointProbing {
    private let systemWide = AXUIElementCreateSystemWide()
    public init() {}

    public func role(at point: CGPoint) -> String? {
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y),
                                               &element) == .success,
              let element else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString,
                                            &value) == .success else { return nil }
        return value as? String
    }
}

/// Pure logic that picks drag points along a window's top strip.
public enum GrabPointPlanner {
    /// Clicking these either has side effects (fields focus and pop open,
    /// buttons fire on release) or hijacks the drag (browser tabs detach).
    public static let unsafeRoles: Set<String> = [
        "AXButton", "AXTextField", "AXSearchField", "AXTextArea", "AXComboBox",
        "AXPopUpButton", "AXMenuButton", "AXRadioButton", "AXCheckBox",
        "AXSlider", "AXLink", "AXSegmentedControl", "AXIncrementor",
        "AXDisclosureTriangle", "AXTabGroup", "AXPopover",
    ]
    /// Keep clear of the traffic lights / sidebar toggles on the left and
    /// right-aligned toolbar buttons on the right.
    static let leftInset: Double = 140
    static let rightInset: Double = 90
    /// 8 pt below the top edge stays inside the titlebar drag strip.
    static let dy: Double = 8

    /// Candidate grab points ordered by how rarely apps put controls there:
    /// off-center first (title strips are usually empty there), center last —
    /// browsers and editors park URL/search fields dead center.
    public static func candidates(frame: YRect) -> [CGPoint] {
        let y = frame.y + dy
        let minX = frame.x + leftInset
        let maxX = frame.x + frame.w - rightInset
        guard maxX > minX else {
            return [CGPoint(x: frame.x + frame.w / 2, y: y)]
        }
        var seen = Set<Int>()
        var points: [CGPoint] = []
        for fraction in [0.18, 0.82, 0.32, 0.68, 0.5] {
            let x = min(max(frame.x + frame.w * fraction, minX), maxX)
            if seen.insert(Int(x.rounded())).inserted {
                points.append(CGPoint(x: x, y: y))
            }
        }
        return points
    }

    public static func isSafe(role: String?) -> Bool {
        guard let role else { return true }  // unknown ≈ empty titlebar area
        return !unsafeRoles.contains(role)
    }

    /// Candidates with control hot-spots filtered out via `roleAt`. Falls back
    /// to the unfiltered list when every point probes unsafe — a blocked move
    /// beats popping a search field, but only as a last resort.
    public static func choose(frame: YRect, roleAt: (CGPoint) -> String?) -> [CGPoint] {
        let all = candidates(frame: frame)
        let safe = all.filter { isSafe(role: roleAt($0)) }
        return safe.isEmpty ? all : safe
    }
}
