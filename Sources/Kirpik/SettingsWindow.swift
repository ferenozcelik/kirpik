import AppKit
import Carbon
import ServiceManagement
import SwiftUI

@MainActor
final class SettingsModel: ObservableObject {
    @Published var shortcut: Shortcut
    @Published var shortcutError: String?
    @Published var launchAtLogin = false
    @Published var hasScreenPermission = false

    /// Registers the new shortcut; returns false when the system refuses it.
    var applyShortcut: (Shortcut) -> Bool = { _ in false }
    /// The global hotkey is paused while recording so pressing it doesn't start a capture.
    var setRecording: (Bool) -> Void = { _ in }

    init(shortcut: Shortcut) {
        self.shortcut = shortcut
        refresh()
    }

    func refresh() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
        hasScreenPermission = ScreenCapture.hasPermission
    }

    func record(_ newShortcut: Shortcut) {
        if applyShortcut(newShortcut) {
            shortcut = newShortcut
            shortcutError = nil
        } else {
            shortcutError = "\(newShortcut.displayString) is already used by another app. Try a different one."
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSAlert(error: error).runModal()
        }
        refresh()
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section {
                LabeledContent("Capture shortcut") {
                    HStack {
                        ShortcutRecorder(model: model)
                            .frame(width: 150, height: 24)
                        Button("Reset") { model.record(.defaultCapture) }
                            .disabled(model.shortcut == .defaultCapture)
                    }
                }
                if let error = model.shortcutError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            Section {
                Toggle("Launch at login", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                ))
            }
            Section {
                LabeledContent("Screen Recording") {
                    if model.hasScreenPermission {
                        Label("Allowed", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("Open System Settings") { ScreenCapture.openPermissionSettings() }
                    }
                }
            } footer: {
                if !model.hasScreenPermission {
                    Text("Turn on Kirpik under Privacy & Security → Screen & System Audio Recording, then reopen Kirpik.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize()
    }
}

/// Click, then press the new key combination. Esc cancels.
struct ShortcutRecorder: NSViewRepresentable {
    @ObservedObject var model: SettingsModel

    func makeNSView(context: Context) -> ShortcutRecorderButton {
        let button = ShortcutRecorderButton(shortcut: model.shortcut)
        button.onRecord = { model.record($0) }
        button.onRecordingChange = { model.setRecording($0) }
        return button
    }

    func updateNSView(_ button: ShortcutRecorderButton, context: Context) {
        button.shortcut = model.shortcut
    }
}

final class ShortcutRecorderButton: NSButton {
    var shortcut: Shortcut { didSet { updateTitle() } }
    var onRecord: (Shortcut) -> Void = { _ in }
    var onRecordingChange: (Bool) -> Void = { _ in }
    private var monitor: Any?

    init(shortcut: Shortcut) {
        self.shortcut = shortcut
        super.init(frame: .zero)
        bezelStyle = .rounded
        target = self
        action = #selector(toggleRecording)
        updateTitle()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil { stopRecording() }
    }

    @objc private func toggleRecording() {
        monitor == nil ? startRecording() : stopRecording()
    }

    private func startRecording() {
        onRecordingChange(true)
        title = "Type shortcut…"
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if Int(event.keyCode) == kVK_Escape {
                self.stopRecording()
            } else if let shortcut = Shortcut(event: event) {
                self.stopRecording()
                self.onRecord(shortcut)
            } else {
                NSSound.beep()
            }
            return nil
        }
    }

    private func stopRecording() {
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
        updateTitle()
        onRecordingChange(false)
    }

    private func updateTitle() {
        if monitor == nil { title = shortcut.displayString }
    }
}

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    let model: SettingsModel

    init(model: SettingsModel) {
        self.model = model
        let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: model)))
        window.title = "Kirpik Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show() {
        model.refresh()
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        model.refresh()
    }
}
