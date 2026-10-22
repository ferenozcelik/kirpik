import AppKit

/// One shape drawn on top of the captured image, in overlay view coordinates (points, origin bottom-left).
struct Annotation {
    enum Kind { case pen, line, arrow, rectangle, ellipse, marker, pixelate, text, counter }

    var kind: Kind
    /// Pen and marker: the whole stroke. Text and counter: one anchor. Everything else: start and end.
    var points: [CGPoint]
    var color: NSColor
    var width: CGFloat
    var filled = false
    var text = ""
    var number = 0

    var start: CGPoint { points[0] }
    var end: CGPoint { points[points.count - 1] }

    var rect: CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
               width: abs(end.x - start.x), height: abs(end.y - start.y))
    }

    /// Drops accidental clicks that would leave an invisible shape behind.
    var isVisible: Bool {
        switch kind {
        case .pen, .marker: return points.count > 1
        case .text: return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .counter: return true
        case .line, .arrow: return hypot(end.x - start.x, end.y - start.y) > 2
        case .rectangle, .ellipse, .pixelate: return rect.width > 2 && rect.height > 2
        }
    }

    static func font(forWidth width: CGFloat) -> NSFont {
        .systemFont(ofSize: 12 + width * 3, weight: .semibold)
    }

    /// Draws into the current NSGraphicsContext. `pixelated` supplies the pixelated full-screen image,
    /// which is drawn into `imageBounds` and clipped to the annotation for the pixelate tool.
    func draw(pixelated: () -> CGImage?, imageBounds: CGRect) {
        switch kind {
        case .pen:
            stroke(smoothPath(), color: color, width: width)
        case .marker:
            stroke(smoothPath(), color: color.withAlphaComponent(0.4), width: max(width * 4, 10))
        case .line:
            let path = NSBezierPath()
            path.move(to: start)
            path.line(to: end)
            stroke(path, color: color, width: width)
        case .arrow:
            drawArrow()
        case .rectangle:
            fillOrStroke(NSBezierPath(rect: rect))
        case .ellipse:
            fillOrStroke(NSBezierPath(ovalIn: rect))
        case .pixelate:
            guard let image = pixelated(), let context = NSGraphicsContext.current?.cgContext else { return }
            context.saveGState()
            context.clip(to: rect)
            context.draw(image, in: imageBounds)
            context.restoreGState()
        case .text:
            let string = NSAttributedString(string: text, attributes: [
                .font: Annotation.font(forWidth: width),
                .foregroundColor: color,
            ])
            // The anchor is the top-left corner of the text.
            string.draw(at: CGPoint(x: start.x, y: start.y - string.size().height))
        case .counter:
            drawCounter()
        }
    }

    private func stroke(_ path: NSBezierPath, color: NSColor, width: CGFloat) {
        path.lineWidth = width
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        color.setStroke()
        path.stroke()
    }

    private func fillOrStroke(_ path: NSBezierPath) {
        if filled {
            color.setFill()
            path.fill()
        } else {
            path.lineJoinStyle = .round
            stroke(path, color: color, width: width)
        }
    }

    /// Curves through the midpoints of the recorded mouse positions so strokes don't look jagged.
    private func smoothPath() -> NSBezierPath {
        let path = NSBezierPath()
        guard points.count > 2 else {
            path.move(to: start)
            path.line(to: end)
            return path
        }
        path.move(to: points[0])
        for i in 1..<points.count - 1 {
            let mid = CGPoint(x: (points[i].x + points[i + 1].x) / 2, y: (points[i].y + points[i + 1].y) / 2)
            path.curve(to: mid, controlPoint1: points[i], controlPoint2: points[i])
        }
        path.line(to: end)
        return path
    }

    private func drawArrow() {
        let angle = atan2(end.y - start.y, end.x - start.x)
        let length = hypot(end.x - start.x, end.y - start.y)
        let headLength = min(max(14, width * 4), length)
        let headAngle = CGFloat.pi / 7

        // Stop the shaft inside the head so its round cap doesn't poke through the tip.
        let shaftEnd = CGPoint(x: end.x - cos(angle) * headLength * 0.7, y: end.y - sin(angle) * headLength * 0.7)
        let shaft = NSBezierPath()
        shaft.move(to: start)
        shaft.line(to: shaftEnd)
        stroke(shaft, color: color, width: width)

        let head = NSBezierPath()
        head.move(to: end)
        head.line(to: CGPoint(x: end.x - cos(angle - headAngle) * headLength,
                              y: end.y - sin(angle - headAngle) * headLength))
        head.line(to: CGPoint(x: end.x - cos(angle + headAngle) * headLength,
                              y: end.y - sin(angle + headAngle) * headLength))
        head.close()
        color.setFill()
        head.fill()
    }

    private func drawCounter() {
        let radius = 11 + width * 1.5
        let circle = NSBezierPath(ovalIn: CGRect(x: start.x - radius, y: start.y - radius,
                                                 width: radius * 2, height: radius * 2))
        color.setFill()
        circle.fill()

        let string = NSAttributedString(string: "\(number)", attributes: [
            .font: NSFont.systemFont(ofSize: radius * 1.1, weight: .bold),
            .foregroundColor: color.isLight ? NSColor.black : NSColor.white,
        ])
        let size = string.size()
        string.draw(at: CGPoint(x: start.x - size.width / 2, y: start.y - size.height / 2))
    }
}

extension NSColor {
    var isLight: Bool {
        guard let rgb = usingColorSpace(.sRGB) else { return false }
        return 0.299 * rgb.redComponent + 0.587 * rgb.greenComponent + 0.114 * rgb.blueComponent > 0.6
    }
}
