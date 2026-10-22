// Generates AppIcons/AppIcon.appiconset. Usage: swift scripts/make_icon.swift
import AppKit

let output = URL(fileURLWithPath: "AppIcons/AppIcon.appiconset")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

/// Drawn on a 1024 canvas: a violet squircle, white selection corners and a closed eye with lashes.
func drawIcon(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let context = NSGraphicsContext.current!.cgContext
    let scale = CGFloat(pixels) / 1024
    context.scaleBy(x: scale, y: scale)

    let body = NSBezierPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
    NSGraphicsContext.saveGraphicsState()
    body.addClip()
    NSGradient(starting: NSColor(srgbRed: 0.45, green: 0.38, blue: 1.0, alpha: 1),
               ending: NSColor(srgbRed: 0.17, green: 0.11, blue: 0.48, alpha: 1))!
        .draw(in: body, angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    NSColor.white.setStroke()

    // Selection corners.
    let inner = CGRect(x: 250, y: 250, width: 524, height: 524)
    let arm: CGFloat = 120
    let corners = NSBezierPath()
    corners.lineWidth = 44
    corners.lineCapStyle = .round
    corners.lineJoinStyle = .round
    for (x, y, dx, dy) in [(inner.minX, inner.maxY, 1.0, -1.0), (inner.maxX, inner.maxY, -1.0, -1.0),
                           (inner.maxX, inner.minY, -1.0, 1.0), (inner.minX, inner.minY, 1.0, 1.0)] {
        corners.move(to: CGPoint(x: x, y: y + dy * arm))
        corners.line(to: CGPoint(x: x, y: y))
        corners.line(to: CGPoint(x: x + dx * arm, y: y))
    }
    corners.stroke()

    // Closed eye: a lid curve with lashes pointing down.
    let p0 = CGPoint(x: 352, y: 560), control = CGPoint(x: 512, y: 430), p2 = CGPoint(x: 672, y: 560)
    let lid = NSBezierPath()
    lid.lineWidth = 36
    lid.lineCapStyle = .round
    lid.move(to: p0)
    lid.curve(to: p2,
              controlPoint1: CGPoint(x: p0.x + (control.x - p0.x) * 2 / 3, y: p0.y + (control.y - p0.y) * 2 / 3),
              controlPoint2: CGPoint(x: p2.x + (control.x - p2.x) * 2 / 3, y: p2.y + (control.y - p2.y) * 2 / 3))
    lid.stroke()

    let lashes = NSBezierPath()
    lashes.lineWidth = 28
    lashes.lineCapStyle = .round
    for t in [0.18, 0.39, 0.61, 0.82] as [CGFloat] {
        let point = CGPoint(x: (1 - t) * (1 - t) * p0.x + 2 * (1 - t) * t * control.x + t * t * p2.x,
                            y: (1 - t) * (1 - t) * p0.y + 2 * (1 - t) * t * control.y + t * t * p2.y)
        let tangent = CGPoint(x: 2 * (1 - t) * (control.x - p0.x) + 2 * t * (p2.x - control.x),
                              y: 2 * (1 - t) * (control.y - p0.y) + 2 * t * (p2.y - control.y))
        let length = hypot(tangent.x, tangent.y)
        let normal = CGPoint(x: tangent.y / length, y: -tangent.x / length) // points downward
        lashes.move(to: CGPoint(x: point.x + normal.x * 20, y: point.y + normal.y * 20))
        lashes.line(to: CGPoint(x: point.x + normal.x * 80, y: point.y + normal.y * 80))
    }
    lashes.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

var images: [[String: String]] = []
for size in [16, 32, 128, 256, 512] {
    for factor in [1, 2] {
        let name = factor == 1 ? "icon_\(size)x\(size).png" : "icon_\(size)x\(size)@2x.png"
        try drawIcon(pixels: size * factor).write(to: output.appendingPathComponent(name))
        images.append(["idiom": "mac", "size": "\(size)x\(size)", "scale": "\(factor)x", "filename": name])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: output.appendingPathComponent("Contents.json"))
print("Wrote \(output.path)")
