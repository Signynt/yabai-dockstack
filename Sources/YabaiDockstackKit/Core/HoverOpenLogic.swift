import Foundation
import CoreGraphics

/// Hover-to-open state for the menu-bar icon: arm a timer when the pointer
/// enters, open when it fires with the pointer still inside — but never right
/// after the menu closed under the pointer, until the pointer has left once.
public struct HoverOpenLogic: Equatable {
    public private(set) var inside = false
    public private(set) var suppressed = false

    public init() {}

    /// Pointer moved; true → (re)arm the open timer.
    public mutating func pointer(inside now: Bool) -> Bool {
        let entered = now && !inside
        inside = now
        if !now { suppressed = false }
        return entered && !suppressed
    }

    public mutating func menuClosed(pointerInside: Bool) {
        inside = pointerInside
        if pointerInside { suppressed = true }
    }

    /// Timer fired; true → open the menu.
    public func timerFired(pointerInside: Bool) -> Bool {
        pointerInside && !suppressed
    }

    /// Height of the top-of-screen band treated as "on the menu bar" (menu bars
    /// differ in height, e.g. notched laptops).
    public static let menuBarBand: CGFloat = 40

    /// The status button only lives on the active display's menu bar; the other
    /// menu bars draw it at the same distance from their right edge. Returns that
    /// spot on `to` as a top-of-screen hover band.
    public static func mirrored(_ icon: CGRect, from: CGRect, to: CGRect) -> CGRect {
        CGRect(x: to.maxX - (from.maxX - icon.minX), y: to.maxY - menuBarBand,
               width: icon.width, height: menuBarBand)
    }
}
