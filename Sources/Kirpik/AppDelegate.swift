import AppKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var hotKey: HotKey?
    private var shortcut = Shortcut.loadCapture()
    private var session: CaptureSession?
    private var isStartingCapture = false
    private lazy var settings = makeSettingsWindow()

    private let captureItem = NSMenuItem(title: "Capture Area", action: #selector(captureFromMenu), keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        if !registerHotKey(shortcut) {
            // Someone else owns the saved shortcut; let the user pick another.
            settings.model.shortcutError = "\(shortcut.displayString) is already used by another app. Try a different one."
            settings.show()
        }

        // Turn on launch at login on first run (can be turned off in Settings).
        if !UserDefaults.standard.bool(forKey: "didSetupLoginItem") {
            UserDefaults.standard.set(true, forKey: "didSetupLoginItem")
            try? SMAppService.mainApp.register()
        }
    }

    // MARK: - Hotkey

    private func registerHotKey(_ shortcut: Shortcut) -> Bool {
        hotKey = nil
        let key = HotKey(shortcut: shortcut) { [weak self] in
            MainActor.assumeIsolated { self?.capture() }
        }
        guard key.isRegistered else { return false }
        hotKey = key
        updateCaptureItem()
        return true
    }

    private func makeSettingsWindow() -> SettingsWindowController {
        let model = SettingsModel(shortcut: shortcut)
        model.applyShortcut = { [weak self] newShortcut in
            guard let self else { return false }
            guard self.registerHotKey(newShortcut) else {
                _ = self.registerHotKey(self.shortcut)
                return false
            }
            self.shortcut = newShortcut
            Shortcut.saveCapture(newShortcut)
            return true
        }
        model.setRecording = { [weak self] recording in
            guard let self else { return }
            if recording {
                self.hotKey = nil
            } else {
                _ = self.registerHotKey(self.shortcut)
            }
        }
        return SettingsWindowController(model: model)
    }

    // MARK: - Capture

    private func capture() {
        guard session == nil, !isStartingCapture else { return }
        guard ScreenCapture.hasPermission else {
            handleMissingPermission()
            return
        }
        isStartingCapture = true
        Task { [weak self] in
            guard let self else { return }
            defer { self.isStartingCapture = false }
            do {
                let shots = try await ScreenCapture.captureAllScreens()
                guard !shots.isEmpty else { return }
                let session = CaptureSession(shots: shots) { [weak self] in self?.session = nil }
                self.session = session
                session.begin()
            } catch {
                NSApp.activate(ignoringOtherApps: true)
                NSAlert(error: error).runModal()
            }
        }
    }

    private func handleMissingPermission() {
        // The first request shows the system prompt and adds Kirpik to the list in System Settings.
        if !UserDefaults.standard.bool(forKey: "didRequestScreenCapture") {
            UserDefaults.standard.set(true, forKey: "didRequestScreenCapture")
            ScreenCapture.requestPermission()
            return
        }
        let alert = NSAlert()
        alert.messageText = "Kirpik needs Screen Recording permission"
        alert.informativeText = "Turn on Kirpik under Privacy & Security → Screen & System Audio Recording, then reopen Kirpik."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            ScreenCapture.openPermissionSettings()
        }
    }

    // MARK: - Menu bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        // The colored app icon, same as in the Dock and Finder.
        let icon = NSApp.applicationIconImage.copy() as! NSImage
        icon.size = NSSize(width: 18, height: 18)
        icon.accessibilityDescription = "Kirpik"
        statusItem.button?.image = icon

        let menu = NSMenu()
        captureItem.target = self
        menu.addItem(captureItem)
        menu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Kirpik", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
        updateCaptureItem()
    }

    private func updateCaptureItem() {
        if let equivalent = shortcut.menuKeyEquivalent {
            captureItem.keyEquivalent = equivalent.key
            captureItem.keyEquivalentModifierMask = equivalent.modifiers
        } else {
            captureItem.keyEquivalent = ""
        }
    }

    @objc private func captureFromMenu() {
        // Give the menu time to fade out so it isn't in the screenshot.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self.capture() }
    }

    @objc private func showSettings() {
        settings.show()
    }
}
