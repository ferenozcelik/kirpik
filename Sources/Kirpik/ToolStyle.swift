import AppKit

enum Tool: Int, CaseIterable {
    case select, pen, line, arrow, rectangle, filledRectangle, ellipse, marker, text, pixelate, counter

    /// Shown when hovering the tool's button.
    var title: String {
        switch self {
        case .select: return "Select: move or resize the selection"
        case .pen: return "Pen: draw freehand"
        case .line: return "Line: hold ⇧ for 45° angles"
        case .arrow: return "Arrow: hold ⇧ for 45° angles"
        case .rectangle: return "Rectangle: outline, hold ⇧ for a square"
        case .filledRectangle: return "Filled rectangle: solid box to cover something"
        case .ellipse: return "Ellipse: hold ⇧ for a circle"
        case .marker: return "Marker: translucent highlighter"
        case .text: return "Text: click to type, ↩ to finish"
        case .pixelate: return "Pixelate: hide sensitive information"
        case .counter: return "Numbered step: click to place 1, 2, 3…"
        }
    }

    var symbolName: String {
        switch self {
        case .select: return "cursorarrow"
        case .pen: return "pencil"
        case .line: return "line.diagonal"
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .filledRectangle: return "rectangle.fill"
        case .ellipse: return "circle"
        case .marker: return "highlighter"
        case .text: return "textformat"
        case .pixelate: return "checkerboard.rectangle"
        case .counter: return "1.circle"
        }
    }

    var annotationKind: Annotation.Kind? {
        switch self {
        case .select: return nil
        case .pen: return .pen
        case .line: return .line
        case .arrow: return .arrow
        case .rectangle, .filledRectangle: return .rectangle
        case .ellipse: return .ellipse
        case .marker: return .marker
        case .text: return .text
        case .pixelate: return .pixelate
        case .counter: return .counter
        }
    }
}

/// Color, size and fill used for new annotations; remembered between captures and launches.
enum ToolStyle {
    static let palette: [(name: String, color: NSColor)] = [
        ("Red", NSColor(srgbRed: 1.00, green: 0.23, blue: 0.19, alpha: 1)),
        ("Orange", NSColor(srgbRed: 1.00, green: 0.58, blue: 0.00, alpha: 1)),
        ("Yellow", NSColor(srgbRed: 1.00, green: 0.84, blue: 0.04, alpha: 1)),
        ("Green", NSColor(srgbRed: 0.20, green: 0.78, blue: 0.35, alpha: 1)),
        ("Blue", NSColor(srgbRed: 0.04, green: 0.52, blue: 1.00, alpha: 1)),
        ("Purple", NSColor(srgbRed: 0.69, green: 0.32, blue: 0.87, alpha: 1)),
        ("Black", NSColor(srgbRed: 0.08, green: 0.08, blue: 0.08, alpha: 1)),
        ("White", NSColor(srgbRed: 1.00, green: 1.00, blue: 1.00, alpha: 1)),
    ]

    static let widthRange: ClosedRange<CGFloat> = 1...20

    static var colorIndex: Int {
        get { min(max(UserDefaults.standard.integer(forKey: "styleColor"), 0), palette.count - 1) }
        set { UserDefaults.standard.set(newValue, forKey: "styleColor") }
    }

    static var color: NSColor { palette[colorIndex].color }

    static var width: CGFloat {
        get {
            let stored = UserDefaults.standard.double(forKey: "styleWidth")
            return stored == 0 ? 3 : CGFloat(stored)
        }
        set {
            let clamped = min(max(newValue, widthRange.lowerBound), widthRange.upperBound)
            UserDefaults.standard.set(Double(clamped), forKey: "styleWidth")
        }
    }

    static func swatch(_ color: NSColor, size: CGFloat = 16) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let circle = NSBezierPath(ovalIn: rect.insetBy(dx: 1.5, dy: 1.5))
            color.setFill()
            circle.fill()
            NSColor.white.withAlphaComponent(0.85).setStroke()
            circle.lineWidth = 1.5
            circle.stroke()
            return true
        }
    }
}
