import AppKit
import Carbon.HIToolbox
import SwiftUI

struct ShortcutRecorderView: NSViewRepresentable {
    let shortcut: GlobalShortcut
    let onRecord: (GlobalShortcut) -> Void

    func makeNSView(context: Context) -> ShortcutRecorderButton {
        let button = ShortcutRecorderButton()
        button.shortcut = shortcut
        button.onRecord = onRecord
        button.updateTitle()
        return button
    }

    func updateNSView(_ nsView: ShortcutRecorderButton, context: Context) {
        nsView.shortcut = shortcut
        nsView.onRecord = onRecord
        nsView.updateTitle()
    }
}

final class ShortcutRecorderButton: NSButton {
    var shortcut: GlobalShortcut?
    var onRecord: ((GlobalShortcut) -> Void)?
    private var isRecording = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        isRecording = true
        updateTitle()
    }

    override func keyDown(with event: NSEvent) {
        guard let shortcut else { return }

        if Int(event.keyCode) == kVK_Escape {
            isRecording = false
            updateTitle()
            return
        }

        let keyCode = UInt32(event.keyCode)
        guard !ShortcutFormatter.keyLabel(for: keyCode).isEmpty else {
            NSSound.beep()
            return
        }

        let recorded = GlobalShortcut(
            action: shortcut.action,
            keyCode: keyCode,
            modifiers: event.carbonModifiers
        )
        onRecord?(recorded)
        isRecording = false
        updateTitle()
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        updateTitle()
        return super.resignFirstResponder()
    }

    func updateTitle() {
        title = isRecording ? "Type shortcut" : (shortcut?.displayValue ?? "")
        toolTip = isRecording ? "Press a shortcut, or Esc to cancel" : "Click to edit shortcut"
    }

    private func setup() {
        bezelStyle = .rounded
        controlSize = .small
        font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        setButtonType(.momentaryPushIn)
    }
}

private extension NSEvent {
    var carbonModifiers: UInt32 {
        let flags = modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: UInt32 = 0

        if flags.contains(.control) {
            modifiers |= UInt32(controlKey)
        }
        if flags.contains(.option) {
            modifiers |= UInt32(optionKey)
        }
        if flags.contains(.shift) {
            modifiers |= UInt32(shiftKey)
        }
        if flags.contains(.command) {
            modifiers |= UInt32(cmdKey)
        }

        return modifiers & ShortcutFormatter.supportedModifierMask
    }
}
