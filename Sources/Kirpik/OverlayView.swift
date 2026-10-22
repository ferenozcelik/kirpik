import AppKit
import Carbon
import CoreImage
import CoreImage.CIFilterBuiltins

/// Shows one frozen screen and handles selecting, annotating and the toolbars for it.
final class OverlayView: NSView, NSTextFieldDelegate {
    private enum Handle: CaseIterable {
        case topLeft, topRight, bottomRight, bottomLeft, top, right, bottom, left
    }

    private enum Drag {
        case creating(origin: CGPoint, previous: CGRect?)
        case moving(start: CGPoint, original: CGRect)
        case resizing(Handle, original: CGRect)
        case drawing
    }

    private weak var session: CaptureSession?
    private let image: CGImage
    /// Pixels per point of the captured image.
    private let scale: CGFloat

    private var selection: CGRect?
    private var annotations: [Annotation] = []
    private var redoStack: [Annotation] = []
    private var current: Annotation?
    private var tool: Tool = .select
    private var drag: Drag?
    private var mouseLocation: CGPoint?

    private var textField: NSTextField?
    private var textOrigin: CGPoint = .zero

    private var hudMessage: String?
    private var hudWorkItem: DispatchWorkItem?
    private var scrollAccumulator: CGFloat = 0

    private lazy var pixelatedImage: CGImage? = makePixelatedImage()

    private let toolsBar = Toolbar(orientation: .vertical)
    private let actionsBar = Toolbar(orientation: .horizontal)
    private let colorsBar = Toolbar(orientation: .vertical)
    private var toolButtons: [Tool: ToolbarButton] = [:]
    private var fillButton: ToolbarButton!
    private var colorButton: ToolbarButton!
    private var undoButton: ToolbarButton!
    private var redoButton: ToolbarButton!

    var hasSelection: Bool { selection != nil }

    private var isCreatingSelection: Bool {
        if case .creating = drag { return true }
        return false
    }

    private var showsMagnifier: Bool {
        session?.isPickingColor == true || selection == nil || isCreatingSelection
    }

    init(frame: NSRect, image: CGImage, session: CaptureSession) {
        self.image = image
        self.session = session
        scale = CGFloat(image.width) / frame.width
        super.init(frame: frame)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
        buildToolbars()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        mouseLocation = bounds.contains(point) ? point : nil
    }

    func clearSelection() {
        discardTextField()
        selection = nil
        annotations = []
        redoStack = []
        current = nil
        drag = nil
        layoutToolbars()
        needsDisplay = true
    }

    func pickingColorDidChange() {
        colorsBar.isHidden = true
        layoutToolbars()
        updateCursor()
        needsDisplay = true
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.draw(image, in: bounds)

        let dim = NSBezierPath(rect: bounds)
        if let selection {
            dim.append(NSBezierPath(rect: selection))
            dim.windingRule = .evenOdd
        }
        NSColor.black.withAlphaComponent(0.45).setFill()
        dim.fill()

        if let selection {
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: selection).addClip()
            for annotation in annotations + [current].compactMap({ $0 }) {
                annotation.draw(pixelated: { self.pixelatedImage }, imageBounds: bounds)
            }
            NSGraphicsContext.restoreGraphicsState()
            drawSelectionFrame(selection)
            drawSizeLabel(selection)
        }

        if showsMagnifier, let mouseLocation {
            drawMagnifier(at: mouseLocation)
        }
    }

    private func drawSelectionFrame(_ rect: CGRect) {
        let border = NSBezierPath(rect: rect.insetBy(dx: -0.5, dy: -0.5))
        border.lineWidth = 1
        NSColor.white.withAlphaComponent(0.9).setStroke()
        border.stroke()

        guard !isCreatingSelection else { return }
        for handle in Handle.allCases {
            let center = point(of: handle, in: rect)
            let square = NSBezierPath(rect: CGRect(x: center.x - 3.5, y: center.y - 3.5, width: 7, height: 7))
            NSColor.white.setFill()
            square.fill()
            NSColor.black.withAlphaComponent(0.5).setStroke()
            square.lineWidth = 1
            square.stroke()
        }
    }

    private func drawSizeLabel(_ rect: CGRect) {
        var text = "\(Int((rect.width * scale).rounded())) × \(Int((rect.height * scale).rounded()))"
        if let hudMessage { text += "   \(hudMessage)" }
        let string = NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
        ])
        let size = string.size()
        let box = CGSize(width: size.width + 12, height: size.height + 6)
        var origin = CGPoint(x: rect.minX, y: rect.maxY + 6)
        if origin.y + box.height > bounds.maxY { origin.y = rect.maxY - box.height - 6; origin.x += 6 }
        origin.x = min(origin.x, bounds.maxX - box.width - 4)

        let background = NSBezierPath(roundedRect: CGRect(origin: origin, size: box), xRadius: 4, yRadius: 4)
        NSColor.black.withAlphaComponent(0.75).setFill()
        background.fill()
        string.draw(at: CGPoint(x: origin.x + 6, y: origin.y + 3))
    }

    private func drawMagnifier(at point: CGPoint) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let pixelsAcross = 15
        let zoom: CGFloat = 8
        let side = CGFloat(pixelsAcross) * zoom
        let labelHeight: CGFloat = 22

        var box = CGRect(x: point.x + 20, y: point.y - 20 - side, width: side, height: side)
        if box.maxX > bounds.maxX - 4 { box.origin.x = point.x - 20 - side }
        if box.minY - labelHeight < bounds.minY + 4 { box.origin.y = point.y + 20 + labelHeight }

        let pixel = pixelCoordinate(of: point)
        let half = pixelsAcross / 2
        let cropRect = CGRect(x: pixel.x - half, y: pixel.y - half, width: pixelsAcross, height: pixelsAcross)
            .intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))

        let frame = NSBezierPath(roundedRect: box, xRadius: 6, yRadius: 6)
        NSGraphicsContext.saveGraphicsState()
        frame.addClip()
        NSColor.black.setFill()
        box.fill()
        if !cropRect.isNull, let cropped = image.cropping(to: cropRect) {
            // Place the cropped pixels so the pixel under the cursor lands in the center cell.
            let x = box.midX - (CGFloat(pixel.x) + 0.5 - cropRect.minX) * zoom
            let top = box.midY + (CGFloat(pixel.y) + 0.5 - cropRect.minY) * zoom
            context.interpolationQuality = .none
            context.draw(cropped, in: CGRect(x: x, y: top - cropRect.height * zoom,
                                             width: cropRect.width * zoom, height: cropRect.height * zoom))
        }
        let cell = CGRect(x: box.midX - zoom / 2, y: box.midY - zoom / 2, width: zoom, height: zoom)
        NSColor.black.setStroke()
        NSBezierPath(rect: cell.insetBy(dx: -1, dy: -1)).stroke()
        NSColor.white.setStroke()
        NSBezierPath(rect: cell).stroke()
        NSGraphicsContext.restoreGraphicsState()

        NSColor.white.withAlphaComponent(0.9).setStroke()
        frame.lineWidth = 1.5
        frame.stroke()

        var text = "\(Int(point.x)), \(Int(bounds.height - point.y))"
        if let hex = hexColor(atPixel: pixel) { text += "  \(hex)" }
        let string = NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
        ])
        let label = CGRect(x: box.minX, y: box.minY - labelHeight, width: side, height: labelHeight - 2)
        NSColor.black.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: label, xRadius: 4, yRadius: 4).fill()
        let size = string.size()
        string.draw(at: CGPoint(x: label.midX - size.width / 2, y: label.midY - size.height / 2))
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        colorsBar.isHidden = true
        let raw = clamped(convert(event.locationInWindow, from: nil))
        let point = snapped(raw)

        if session?.isPickingColor == true {
            if let hex = hexColor(atPixel: pixelCoordinate(of: raw)) { session?.pickedColor(hex) }
            return
        }
        // A click while typing only finishes the text.
        if commitTextField() { return }

        guard let selection else {
            beginSelection(at: point, previous: nil)
            return
        }
        if let handle = handle(at: point, in: selection) {
            drag = .resizing(handle, original: selection)
            return
        }

        switch tool {
        case .select:
            if selection.contains(point) {
                drag = .moving(start: point, original: selection)
                NSCursor.closedHand.set()
            } else {
                beginSelection(at: point, previous: selection)
            }
        case .text:
            beginTextField(at: raw)
        case .counter:
            let number = annotations.filter { $0.kind == .counter }.count + 1
            add(Annotation(kind: .counter, points: [raw], color: ToolStyle.color, width: ToolStyle.width, number: number))
        default:
            guard let kind = tool.annotationKind else { return }
            current = Annotation(kind: kind, points: [raw, raw], color: ToolStyle.color,
                                 width: ToolStyle.width, filled: ToolStyle.filled)
            drag = .drawing
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let raw = clamped(convert(event.locationInWindow, from: nil))
        let point = snapped(raw)
        mouseLocation = raw

        switch drag {
        case .creating(let origin, _):
            selection = CGRect(x: min(origin.x, point.x), y: min(origin.y, point.y),
                               width: abs(point.x - origin.x), height: abs(point.y - origin.y))
        case .moving(let start, let original):
            var moved = original.offsetBy(dx: point.x - start.x, dy: point.y - start.y)
            moved.origin.x = min(max(moved.minX, 0), bounds.width - moved.width)
            moved.origin.y = min(max(moved.minY, 0), bounds.height - moved.height)
            selection = moved
        case .resizing(let handle, let original):
            selection = resized(original, handle: handle, to: point)
        case .drawing:
            guard var annotation = current else { break }
            switch annotation.kind {
            case .pen, .marker:
                annotation.points.append(raw)
            default:
                let shift = event.modifierFlags.contains(.shift)
                annotation.points[1] = shift ? constrained(raw, from: annotation.start, kind: annotation.kind) : raw
            }
            current = annotation
        case nil:
            break
        }
        layoutToolbars()
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        switch drag {
        case .creating(_, let previous):
            if let selection, selection.width < 4 || selection.height < 4 {
                self.selection = previous
            }
        case .drawing:
            if let current, current.isVisible { add(current) }
            current = nil
        default:
            break
        }
        drag = nil
        layoutToolbars()
        updateCursor()
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        mouseLocation = convert(event.locationInWindow, from: nil)
        updateCursor()
        if showsMagnifier { needsDisplay = true }
    }

    override func mouseExited(with event: NSEvent) {
        mouseLocation = nil
        needsDisplay = true
    }

    override func scrollWheel(with event: NSEvent) {
        scrollAccumulator += event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 0.1 : 1)
        guard abs(scrollAccumulator) >= 1 else { return }
        let step = scrollAccumulator > 0 ? 1 : -1
        scrollAccumulator = 0
        ToolStyle.width += CGFloat(step)
        textField?.font = Annotation.font(forWidth: ToolStyle.width)
        resizeTextField()
        showHUD("Size \(Int(ToolStyle.width))")
    }

    private func beginSelection(at point: CGPoint, previous: CGRect?) {
        session?.viewDidBeginSelection(self)
        drag = .creating(origin: point, previous: previous)
        selection = CGRect(origin: point, size: .zero)
        layoutToolbars()
        needsDisplay = true
    }

    private func updateCursor() {
        guard let point = mouseLocation else { return }
        if !toolsBar.isHidden, toolsBar.frame.contains(point) || actionsBar.frame.contains(point)
            || (!colorsBar.isHidden && colorsBar.frame.contains(point)) {
            NSCursor.arrow.set()
            return
        }
        guard session?.isPickingColor != true, let selection else {
            NSCursor.crosshair.set()
            return
        }
        if let handle = handle(at: snapped(point), in: selection) {
            switch handle {
            case .left, .right: NSCursor.resizeLeftRight.set()
            case .top, .bottom: NSCursor.resizeUpDown.set()
            default: NSCursor.crosshair.set()
            }
            return
        }
        switch tool {
        case .select: (selection.contains(point) ? NSCursor.openHand : NSCursor.crosshair).set()
        case .text: NSCursor.iBeam.set()
        default: NSCursor.crosshair.set()
        }
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        switch Int(event.keyCode) {
        case kVK_Escape:
            if session?.isPickingColor == true {
                session?.isPickingColor = false
            } else {
                session?.cancel()
            }
        case kVK_Return, kVK_ANSI_KeypadEnter:
            copyImage()
        default:
            super.keyDown(with: event)
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // While typing, ⌘C/⌘Z belong to the text field.
        guard textField == nil else { return super.performKeyEquivalent(with: event) }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command), let key = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }
        switch key {
        case "c": copyImage()
        case "s": saveImage()
        case "z": flags.contains(.shift) ? redo() : undo()
        default: return super.performKeyEquivalent(with: event)
        }
        return true
    }

    // MARK: - Text

    private func beginTextField(at point: CGPoint) {
        let field = NSTextField(string: "")
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = Annotation.font(forWidth: ToolStyle.width)
        field.textColor = ToolStyle.color
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.delegate = self
        textOrigin = point
        textField = field
        addSubview(field)
        resizeTextField()
        window?.makeFirstResponder(field)
    }

    private func resizeTextField() {
        guard let field = textField else { return }
        let size = field.sizeThatFits(NSSize(width: 10_000, height: 10_000))
        // NSTextField insets its text by about 2pt; shift left so the text starts at the click.
        field.frame = CGRect(x: textOrigin.x - 2, y: textOrigin.y - size.height,
                             width: max(size.width + 12, 24), height: size.height)
    }

    /// Turns the text being typed into an annotation. Returns false when nothing was being typed.
    @discardableResult
    private func commitTextField() -> Bool {
        guard let field = textField else { return false }
        let text = field.stringValue
        discardTextField()
        add(Annotation(kind: .text, points: [textOrigin], color: ToolStyle.color, width: ToolStyle.width, text: text))
        return true
    }

    private func discardTextField() {
        guard let field = textField else { return }
        textField = nil
        field.delegate = nil
        field.removeFromSuperview()
        window?.makeFirstResponder(self)
    }

    func controlTextDidChange(_ notification: Notification) {
        resizeTextField()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(insertNewline(_:)) || commandSelector == #selector(cancelOperation(_:)) {
            commitTextField()
            needsDisplay = true
            return true
        }
        return false
    }

    // MARK: - Annotations

    private func add(_ annotation: Annotation) {
        guard annotation.isVisible else { return }
        annotations.append(annotation)
        redoStack.removeAll()
        updateToolbarState()
        needsDisplay = true
    }

    @objc private func undo() {
        commitTextField()
        guard let last = annotations.popLast() else { return }
        redoStack.append(last)
        updateToolbarState()
        needsDisplay = true
    }

    @objc private func redo() {
        guard let next = redoStack.popLast() else { return }
        annotations.append(next)
        updateToolbarState()
        needsDisplay = true
    }

    private func constrained(_ point: CGPoint, from start: CGPoint, kind: Annotation.Kind) -> CGPoint {
        let dx = point.x - start.x, dy = point.y - start.y
        switch kind {
        case .line, .arrow:
            let step = CGFloat.pi / 4
            let angle = (atan2(dy, dx) / step).rounded() * step
            let length = hypot(dx, dy)
            return CGPoint(x: start.x + cos(angle) * length, y: start.y + sin(angle) * length)
        default:
            let side = max(abs(dx), abs(dy))
            return CGPoint(x: start.x + (dx < 0 ? -side : side), y: start.y + (dy < 0 ? -side : side))
        }
    }

    private func makePixelatedImage() -> CGImage? {
        let input = CIImage(cgImage: image)
        let filter = CIFilter.pixellate()
        filter.inputImage = input.clampedToExtent()
        filter.scale = Float(12 * scale)
        filter.center = .zero
        guard let output = filter.outputImage?.cropped(to: input.extent) else { return nil }
        return CIContext().createCGImage(output, from: input.extent)
    }

    // MARK: - Output

    /// The selected area at full pixel resolution, with or without the annotations on top.
    private func renderSelection(includeAnnotations: Bool = true) -> CGImage? {
        guard let selection, selection.width >= 1, selection.height >= 1 else { return nil }
        let pixelRect = CGRect(x: selection.minX * scale, y: (bounds.height - selection.maxY) * scale,
                               width: selection.width * scale, height: selection.height * scale).integral
        guard includeAnnotations, !annotations.isEmpty else { return image.cropping(to: pixelRect) }

        let width = Int(pixelRect.width), height = Int(pixelRect.height)
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: bitmapInfo)
            ?? CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                         space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: bitmapInfo) else { return nil }

        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -selection.minX, y: -selection.minY)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        context.draw(image, in: bounds)
        for annotation in annotations {
            annotation.draw(pixelated: { self.pixelatedImage }, imageBounds: bounds)
        }
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }

    @objc private func copyImage() {
        commitTextField()
        guard let image = renderSelection() else { return }
        session?.copy(image)
    }

    @objc private func saveImage() {
        commitTextField()
        guard let image = renderSelection() else { return }
        session?.save(image)
    }

    @objc private func recognizeText() {
        guard let image = renderSelection(includeAnnotations: false) else { return }
        discardTextField()
        session?.recognizeText(image)
    }

    @objc private func pickColor() {
        commitTextField()
        session?.isPickingColor = true
    }

    @objc private func close() {
        session?.cancel()
    }

    // MARK: - Toolbars

    private func buildToolbars() {
        for tool in Tool.allCases {
            let button = toolsBar.addButton(symbol: tool.symbolName, tooltip: tool.title,
                                            target: self, action: #selector(selectTool(_:)))
            button.tag = tool.rawValue
            toolButtons[tool] = button
        }
        toolsBar.addSeparator()
        fillButton = toolsBar.addButton(symbol: "square.fill", tooltip: "Fill shapes", target: self,
                                        action: #selector(toggleFill))
        colorButton = toolsBar.addButton(image: ToolStyle.swatch(ToolStyle.color),
                                         tooltip: "Color (scroll to change size)", target: self,
                                         action: #selector(toggleColors))

        for (index, entry) in ToolStyle.palette.enumerated() {
            let button = colorsBar.addButton(image: ToolStyle.swatch(entry.color), tooltip: entry.name,
                                             target: self, action: #selector(selectColor(_:)))
            button.tag = index
        }

        undoButton = actionsBar.addButton(symbol: "arrow.uturn.backward", tooltip: "Undo (⌘Z)",
                                          target: self, action: #selector(undo))
        redoButton = actionsBar.addButton(symbol: "arrow.uturn.forward", tooltip: "Redo (⇧⌘Z)",
                                          target: self, action: #selector(redo))
        actionsBar.addSeparator()
        actionsBar.addButton(symbol: "text.viewfinder", tooltip: "Copy text (OCR)",
                             target: self, action: #selector(recognizeText))
        actionsBar.addButton(symbol: "eyedropper", tooltip: "Copy color", target: self, action: #selector(pickColor))
        actionsBar.addSeparator()
        actionsBar.addButton(symbol: "square.and.arrow.down", tooltip: "Save (⌘S)",
                             target: self, action: #selector(saveImage))
        actionsBar.addButton(symbol: "doc.on.doc", tooltip: "Copy (⌘C or ↩)",
                             target: self, action: #selector(copyImage))
        actionsBar.addButton(symbol: "xmark", tooltip: "Close (esc)", target: self, action: #selector(close))

        for bar in [toolsBar, actionsBar, colorsBar] {
            bar.sizeToFit()
            bar.isHidden = true
            addSubview(bar)
        }
        updateToolbarState()
    }

    private func updateToolbarState() {
        for (tool, button) in toolButtons { button.isActive = tool == self.tool }
        fillButton.isActive = ToolStyle.filled
        colorButton.image = ToolStyle.swatch(ToolStyle.color)
        undoButton.isEnabled = !annotations.isEmpty
        redoButton.isEnabled = !redoStack.isEmpty
    }

    private func layoutToolbars() {
        let visible = selection != nil && !isCreatingSelection && session?.isPickingColor != true
        toolsBar.isHidden = !visible
        actionsBar.isHidden = !visible
        guard visible, let selection else {
            colorsBar.isHidden = true
            return
        }
        let gap: CGFloat = 8, margin: CGFloat = 4
        let tools = toolsBar.frame.size, actions = actionsBar.frame.size

        // Tools: to the right of the selection, else to the left, else inside.
        var toolsX = selection.maxX + gap
        if toolsX + tools.width > bounds.maxX - margin { toolsX = selection.minX - gap - tools.width }
        if toolsX < margin { toolsX = selection.maxX - tools.width - gap }
        var toolsY = selection.maxY - tools.height
        toolsY = min(max(toolsY, margin), bounds.maxY - tools.height - margin)
        toolsBar.setFrameOrigin(CGPoint(x: toolsX, y: toolsY))

        // Actions: below the selection, right-aligned; else above; else inside.
        var actionsX = selection.maxX - actions.width
        actionsX = min(max(actionsX, margin), bounds.maxX - actions.width - margin)
        var actionsY = selection.minY - gap - actions.height
        if actionsY < margin {
            actionsY = selection.maxY + gap
            if actionsY + actions.height > bounds.maxY - margin { actionsY = selection.minY + gap }
        }
        actionsBar.setFrameOrigin(CGPoint(x: actionsX, y: actionsY))

        if !colorsBar.isHidden { layoutColorsBar() }
    }

    private func layoutColorsBar() {
        let colors = colorsBar.frame.size
        let anchor = colorButton.convert(colorButton.bounds, to: self)
        var x = toolsBar.frame.maxX + 6
        if x + colors.width > bounds.maxX - 4 { x = toolsBar.frame.minX - 6 - colors.width }
        let y = min(max(anchor.maxY - colors.height + 4, 4), bounds.maxY - colors.height - 4)
        colorsBar.setFrameOrigin(CGPoint(x: x, y: y))
    }

    @objc private func selectTool(_ sender: NSButton) {
        guard let tool = Tool(rawValue: sender.tag) else { return }
        commitTextField()
        self.tool = tool
        updateToolbarState()
        needsDisplay = true
    }

    @objc private func toggleFill() {
        ToolStyle.filled.toggle()
        updateToolbarState()
    }

    @objc private func toggleColors() {
        colorsBar.isHidden.toggle()
        if !colorsBar.isHidden { layoutColorsBar() }
    }

    @objc private func selectColor(_ sender: NSButton) {
        ToolStyle.colorIndex = sender.tag
        textField?.textColor = ToolStyle.color
        colorsBar.isHidden = true
        updateToolbarState()
    }

    private func showHUD(_ message: String) {
        hudMessage = message
        hudWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.hudMessage = nil
            self?.needsDisplay = true
        }
        hudWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
        needsDisplay = true
    }

    // MARK: - Geometry

    private func clamped(_ point: CGPoint) -> CGPoint {
        CGPoint(x: min(max(point.x, 0), bounds.width), y: min(max(point.y, 0), bounds.height))
    }

    /// Whole points keep the selection on whole pixels.
    private func snapped(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x.rounded(), y: point.y.rounded())
    }

    /// Image pixel under a view point; image rows start at the top.
    private func pixelCoordinate(of point: CGPoint) -> (x: Int, y: Int) {
        (Int(point.x * scale), Int((bounds.height - point.y) * scale))
    }

    private func hexColor(atPixel pixel: (x: Int, y: Int)) -> String? {
        guard pixel.x >= 0, pixel.y >= 0, pixel.x < image.width, pixel.y < image.height,
              let single = image.cropping(to: CGRect(x: pixel.x, y: pixel.y, width: 1, height: 1)),
              let sRGB = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var rgba = [UInt8](repeating: 0, count: 4)
        let drawn = rgba.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                                          bytesPerRow: 4, space: sRGB,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(single, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard drawn else { return nil }
        return String(format: "#%02X%02X%02X", rgba[0], rgba[1], rgba[2])
    }

    private func point(of handle: Handle, in rect: CGRect) -> CGPoint {
        switch handle {
        case .topLeft: return CGPoint(x: rect.minX, y: rect.maxY)
        case .top: return CGPoint(x: rect.midX, y: rect.maxY)
        case .topRight: return CGPoint(x: rect.maxX, y: rect.maxY)
        case .right: return CGPoint(x: rect.maxX, y: rect.midY)
        case .bottomRight: return CGPoint(x: rect.maxX, y: rect.minY)
        case .bottom: return CGPoint(x: rect.midX, y: rect.minY)
        case .bottomLeft: return CGPoint(x: rect.minX, y: rect.minY)
        case .left: return CGPoint(x: rect.minX, y: rect.midY)
        }
    }

    /// Corners first, then edges anywhere along their length.
    private func handle(at point: CGPoint, in rect: CGRect) -> Handle? {
        let reach: CGFloat = 6
        for handle in [Handle.topLeft, .topRight, .bottomRight, .bottomLeft] {
            let center = self.point(of: handle, in: rect)
            if abs(center.x - point.x) <= reach && abs(center.y - point.y) <= reach { return handle }
        }
        let withinX = point.x > rect.minX && point.x < rect.maxX
        let withinY = point.y > rect.minY && point.y < rect.maxY
        if withinX && abs(point.y - rect.maxY) <= reach { return .top }
        if withinX && abs(point.y - rect.minY) <= reach { return .bottom }
        if withinY && abs(point.x - rect.minX) <= reach { return .left }
        if withinY && abs(point.x - rect.maxX) <= reach { return .right }
        return nil
    }

    private func resized(_ rect: CGRect, handle: Handle, to point: CGPoint) -> CGRect {
        var minX = rect.minX, maxX = rect.maxX, minY = rect.minY, maxY = rect.maxY
        switch handle {
        case .topLeft: minX = point.x; maxY = point.y
        case .top: maxY = point.y
        case .topRight: maxX = point.x; maxY = point.y
        case .right: maxX = point.x
        case .bottomRight: maxX = point.x; minY = point.y
        case .bottom: minY = point.y
        case .bottomLeft: minX = point.x; minY = point.y
        case .left: minX = point.x
        }
        return CGRect(x: min(minX, maxX), y: min(minY, maxY), width: abs(maxX - minX), height: abs(maxY - minY))
    }
}
