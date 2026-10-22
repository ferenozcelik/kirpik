import AppKit

/// The app icon's shape (selection corners and a closed eye) as a monochrome template image,
/// so it follows the menu bar's light and dark appearance.
enum MenuBarIcon {
    static func make() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            // Same geometry as scripts/make_icon.swift, which draws on a 1024 canvas.
            let transform = NSAffineTransform()
            transform.scale(by: 18 / 580)
            transform.translateX(by: -222, yBy: -222)
            transform.concat()
            NSColor.black.setStroke()

            let inner = CGRect(x: 250, y: 250, width: 524, height: 524)
            let arm: CGFloat = 130
            let corners = NSBezierPath()
            corners.lineWidth = 52
            corners.lineCapStyle = .round
            corners.lineJoinStyle = .round
            for (x, y, dx, dy) in [(inner.minX, inner.maxY, 1.0, -1.0), (inner.maxX, inner.maxY, -1.0, -1.0),
                                   (inner.maxX, inner.minY, -1.0, 1.0), (inner.minX, inner.minY, 1.0, 1.0)] {
                corners.move(to: CGPoint(x: x, y: y + dy * arm))
                corners.line(to: CGPoint(x: x, y: y))
                corners.line(to: CGPoint(x: x + dx * arm, y: y))
            }
            corners.stroke()

            let p0 = CGPoint(x: 352, y: 560), control = CGPoint(x: 512, y: 430), p2 = CGPoint(x: 672, y: 560)
            let lid = NSBezierPath()
            lid.lineWidth = 46
            lid.lineCapStyle = .round
            lid.move(to: p0)
            lid.curve(to: p2,
                      controlPoint1: CGPoint(x: p0.x + (control.x - p0.x) * 2 / 3, y: p0.y + (control.y - p0.y) * 2 / 3),
                      controlPoint2: CGPoint(x: p2.x + (control.x - p2.x) * 2 / 3, y: p2.y + (control.y - p2.y) * 2 / 3))
            lid.stroke()

            let lashes = NSBezierPath()
            lashes.lineWidth = 40
            lashes.lineCapStyle = .round
            for t in [0.18, 0.39, 0.61, 0.82] as [CGFloat] {
                let point = CGPoint(x: (1 - t) * (1 - t) * p0.x + 2 * (1 - t) * t * control.x + t * t * p2.x,
                                    y: (1 - t) * (1 - t) * p0.y + 2 * (1 - t) * t * control.y + t * t * p2.y)
                let tangent = CGPoint(x: 2 * (1 - t) * (control.x - p0.x) + 2 * t * (p2.x - control.x),
                                      y: 2 * (1 - t) * (control.y - p0.y) + 2 * t * (p2.y - control.y))
                let length = hypot(tangent.x, tangent.y)
                let normal = CGPoint(x: tangent.y / length, y: -tangent.x / length) // points downward
                lashes.move(to: CGPoint(x: point.x + normal.x * 24, y: point.y + normal.y * 24))
                lashes.line(to: CGPoint(x: point.x + normal.x * 85, y: point.y + normal.y * 85))
            }
            lashes.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Kirpik"
        return image
    }
}
