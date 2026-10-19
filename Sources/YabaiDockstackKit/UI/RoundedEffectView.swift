import AppKit

/// Clips the visual-effect material inside the panel shell, avoiding pale
/// square corners behind the rounded overlay layer.
final class RoundedPanelView: NSView {
    private let radius: CGFloat

    init(frame: CGRect, radius: CGFloat) {
        self.radius = radius
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = radius
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor.clear.cgColor
        clipsToBounds = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).addClip()
        super.draw(dirtyRect)
    }
}
