# Kirpik

Menu bar screenshot app for macOS 14+: area capture (⌘⇧9 by default), annotations, copy/save, OCR and a color picker. Swift Package, AppKit, no Xcode project.

## Build

- `swift build` to check that it compiles (must pass before committing).
- `./build.sh` builds `build/Kirpik.app`; `./build.sh --install` installs to /Applications and launches it.
- Ad-hoc signed (`codesign --sign -`). Never sign with the Apple Development certificate. Screen Recording permission must be granted again after each rebuild.

## Code

- Everything is in `Sources/Kirpik/`: `CaptureSession` / `OverlayWindow` / `OverlayView` (selection and drawing), `Annotation` + `ToolStyle` (tools), `Toolbar`, `TextRecognizer` (OCR), `HotKey` + `Shortcut` (global shortcut, Carbon), `SettingsWindow`.
- English UI text and English file names.
- OCR and the color picker are toolbar buttons, not separate shortcuts. ⌘S always opens a save panel.
- Keep the app minimal: don't add features beyond the ones in README without being asked. Don't name other screenshot apps in repo content.

## Git

Base branch `dev`, remote `origin`. `dev` → `main` is the release step.
