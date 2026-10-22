import AppKit
import UniformTypeIdentifiers

/// One capture from hotkey press to copy/save/cancel: an overlay per screen, at most one selection.
@MainActor
final class CaptureSession {
    private var windows: [OverlayWindow] = []
    private var views: [OverlayView] = []
    private let shots: [ScreenCapture.Shot]
    private let previousApp = NSWorkspace.shared.frontmostApplication
    private let onFinish: () -> Void

    /// Eyedropper mode spans every screen, so it lives here rather than in a single view.
    var isPickingColor = false {
        didSet { views.forEach { $0.pickingColorDidChange() } }
    }

    init(shots: [ScreenCapture.Shot], onFinish: @escaping () -> Void) {
        self.shots = shots
        self.onFinish = onFinish
    }

    func begin() {
        for shot in shots {
            let window = OverlayWindow(screen: shot.screen)
            let view = OverlayView(frame: NSRect(origin: .zero, size: shot.screen.frame.size),
                                   image: shot.image, session: self)
            window.contentView = view
            windows.append(window)
            views.append(view)
        }
        NSApp.activate(ignoringOtherApps: true)
        windows.forEach { $0.orderFrontRegardless() }

        let mouse = NSEvent.mouseLocation
        let keyWindow = windows.first { $0.frame.contains(mouse) } ?? windows.first
        keyWindow?.makeKeyAndOrderFront(nil)
        keyWindow?.makeFirstResponder(keyWindow?.contentView)
    }

    /// Only one screen can hold a selection; starting one elsewhere clears the others.
    func viewDidBeginSelection(_ view: OverlayView) {
        for other in views where other !== view { other.clearSelection() }
    }

    func copy(_ image: CGImage) {
        let rep = NSBitmapImageRep(cgImage: image)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let png = rep.representation(using: .png, properties: [:]) { pasteboard.setData(png, forType: .png) }
        if let tiff = rep.tiffRepresentation { pasteboard.setData(tiff, forType: .tiff) }
        finish()
        Toast.show("Copied to clipboard")
    }

    func save(_ image: CGImage) {
        windows.forEach { $0.orderOut(nil) }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = Self.defaultFileName()
        panel.directoryURL = Self.lastSaveDirectory
        NSApp.activate(ignoringOtherApps: true)

        guard panel.runModal() == .OK, let url = panel.url else {
            restoreWindows()
            return
        }
        do {
            guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
                throw CocoaError(.fileWriteUnknown)
            }
            try png.write(to: url)
            Self.lastSaveDirectory = url.deletingLastPathComponent()
            finish()
            Toast.show("Saved \(url.lastPathComponent)")
        } catch {
            NSAlert(error: error).runModal()
            restoreWindows()
        }
    }

    func recognizeText(_ image: CGImage) {
        finish()
        Task {
            let text = await TextRecognizer.recognize(image)
            if text.isEmpty {
                Toast.show("No text found")
            } else {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                Toast.show("Copied text")
            }
        }
    }

    func pickedColor(_ hex: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(hex, forType: .string)
        finish()
        Toast.show("Copied \(hex)")
    }

    func cancel() {
        finish()
    }

    private func restoreWindows() {
        windows.forEach { $0.orderFrontRegardless() }
        let window = views.first(where: { $0.hasSelection })?.window ?? windows.first
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(window?.contentView)
    }

    private func finish() {
        guard !windows.isEmpty else { return }
        windows.forEach { $0.orderOut(nil) }
        windows.forEach { $0.close() }
        windows = []
        views = []
        previousApp?.activate()
        onFinish()
    }

    // MARK: - Saving

    private static var lastSaveDirectory: URL? {
        get {
            if let path = UserDefaults.standard.string(forKey: "lastSaveDirectory") { return URL(fileURLWithPath: path) }
            return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        }
        set { UserDefaults.standard.set(newValue?.path, forKey: "lastSaveDirectory") }
    }

    /// "Kirpik 2026-10-22 at 14.05.33.png"
    private static func defaultFileName() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Kirpik \(formatter.string(from: Date())).png"
    }
}
