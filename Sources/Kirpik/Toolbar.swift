import AppKit

/// Dark floating button bar shown next to the selection.
final class Toolbar: NSVisualEffectView {
    private let stack = NSStackView()
    /// Called when the pointer enters (true) or leaves (false) one of the buttons.
    var onHover: ((ToolbarButton, Bool) -> Void)?

    var orientation: NSUserInterfaceLayoutOrientation { stack.orientation }

    init(orientation: NSUserInterfaceLayoutOrientation) {
        super.init(frame: .zero)
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        appearance = NSAppearance(named: .vibrantDark)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true

        stack.orientation = orientation
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @discardableResult
    func addButton(symbol: String, tooltip: String, target: AnyObject, action: Selector) -> ToolbarButton {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
            ?? NSImage(systemSymbolName: "questionmark", accessibilityDescription: tooltip)!
        return addButton(image: image, tooltip: tooltip, target: target, action: action)
    }

    @discardableResult
    func addButton(image: NSImage, tooltip: String, target: AnyObject, action: Selector) -> ToolbarButton {
        let button = ToolbarButton(image: image, target: target, action: action)
        button.tip = tooltip
        button.setAccessibilityLabel(tooltip)
        button.onHover = { [weak self] button, inside in self?.onHover?(button, inside) }
        stack.addArrangedSubview(button)
        return button
    }

    func addSeparator() {
        let line = NSBox()
        line.boxType = .separator
        stack.addArrangedSubview(line)
        if stack.orientation == .vertical {
            line.widthAnchor.constraint(equalToConstant: 20).isActive = true
        } else {
            line.heightAnchor.constraint(equalToConstant: 20).isActive = true
        }
    }

    func sizeToFit() {
        setFrameSize(fittingSize)
    }
}

final class ToolbarButton: NSButton {
    var tip = ""
    var onHover: ((ToolbarButton, Bool) -> Void)?
    private var hoverArea: NSTrackingArea?

    var isActive = false {
        didSet { layer?.backgroundColor = isActive ? NSColor.controlAccentColor.cgColor : nil }
    }

    convenience init(image: NSImage, target: AnyObject, action: Selector) {
        self.init(frame: .zero)
        self.image = image.withSymbolConfiguration(.init(pointSize: 14, weight: .medium)) ?? image
        self.target = target
        self.action = action
        isBordered = false
        imagePosition = .imageOnly
        contentTintColor = .white
        wantsLayer = true
        layer?.cornerRadius = 5
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 28).isActive = true
        heightAnchor.constraint(equalToConstant: 28).isActive = true
    }

    override var isEnabled: Bool {
        didSet { alphaValue = isEnabled ? 1 : 0.35 }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        onHover?(self, true)
    }

    override func mouseExited(with event: NSEvent) {
        onHover?(self, false)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }
}
