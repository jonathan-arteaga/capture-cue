import Carbon.HIToolbox
import Foundation

struct GlobalShortcut: Identifiable, Equatable, Codable {
    let action: GlobalShortcutAction
    let keyCode: UInt32
    let modifiers: UInt32

    var id: GlobalShortcutAction { action }

    var displayValue: String {
        ShortcutFormatter.displayValue(keyCode: keyCode, modifiers: modifiers)
    }

    var isUsableGlobalShortcut: Bool {
        keyCode > 0 && modifiers.intersection(with: ShortcutFormatter.requiredModifierMask) != 0
    }
}

enum GlobalShortcutAction: UInt32, CaseIterable, Identifiable, Codable {
    case captureArea = 1
    case captureFullScreen
    case captureWindow

    var id: UInt32 { rawValue }

    var title: String {
        switch self {
        case .captureArea:
            "Capture Area"
        case .captureFullScreen:
            "Capture All Displays"
        case .captureWindow:
            "Capture Window"
        }
    }

    var systemImage: String {
        switch self {
        case .captureArea:
            "camera.viewfinder"
        case .captureFullScreen:
            "macwindow"
        case .captureWindow:
            "macwindow.on.rectangle"
        }
    }

    var defaultShortcut: GlobalShortcut {
        let modifiers = UInt32(controlKey | optionKey | shiftKey)

        switch self {
        case .captureArea:
            return GlobalShortcut(action: self, keyCode: UInt32(kVK_ANSI_4), modifiers: modifiers)
        case .captureFullScreen:
            return GlobalShortcut(action: self, keyCode: UInt32(kVK_ANSI_3), modifiers: modifiers)
        case .captureWindow:
            return GlobalShortcut(action: self, keyCode: UInt32(kVK_ANSI_5), modifiers: modifiers)
        }
    }
}

struct GlobalShortcutRegistration: Equatable {
    let shortcut: GlobalShortcut
    let status: OSStatus

    var isRegistered: Bool {
        status == noErr
    }
}

enum ShortcutFormatter {
    static let requiredModifierMask = UInt32(cmdKey | controlKey | optionKey)
    static let supportedModifierMask = UInt32(cmdKey | controlKey | optionKey | shiftKey)

    static func displayValue(keyCode: UInt32, modifiers: UInt32) -> String {
        let key = keyLabel(for: keyCode)
        guard !key.isEmpty else { return "" }

        var prefix = ""
        if modifiers.contains(carbonModifier: controlKey) {
            prefix += "⌃"
        }
        if modifiers.contains(carbonModifier: optionKey) {
            prefix += "⌥"
        }
        if modifiers.contains(carbonModifier: shiftKey) {
            prefix += "⇧"
        }
        if modifiers.contains(carbonModifier: cmdKey) {
            prefix += "⌘"
        }

        return prefix + key
    }

    static func keyLabel(for keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_ANSI_A: "A"
        case kVK_ANSI_B: "B"
        case kVK_ANSI_C: "C"
        case kVK_ANSI_D: "D"
        case kVK_ANSI_E: "E"
        case kVK_ANSI_F: "F"
        case kVK_ANSI_G: "G"
        case kVK_ANSI_H: "H"
        case kVK_ANSI_I: "I"
        case kVK_ANSI_J: "J"
        case kVK_ANSI_K: "K"
        case kVK_ANSI_L: "L"
        case kVK_ANSI_M: "M"
        case kVK_ANSI_N: "N"
        case kVK_ANSI_O: "O"
        case kVK_ANSI_P: "P"
        case kVK_ANSI_Q: "Q"
        case kVK_ANSI_R: "R"
        case kVK_ANSI_S: "S"
        case kVK_ANSI_T: "T"
        case kVK_ANSI_U: "U"
        case kVK_ANSI_V: "V"
        case kVK_ANSI_W: "W"
        case kVK_ANSI_X: "X"
        case kVK_ANSI_Y: "Y"
        case kVK_ANSI_Z: "Z"
        case kVK_ANSI_0: "0"
        case kVK_ANSI_1: "1"
        case kVK_ANSI_2: "2"
        case kVK_ANSI_3: "3"
        case kVK_ANSI_4: "4"
        case kVK_ANSI_5: "5"
        case kVK_ANSI_6: "6"
        case kVK_ANSI_7: "7"
        case kVK_ANSI_8: "8"
        case kVK_ANSI_9: "9"
        case kVK_Space: "Space"
        case kVK_Return: "Return"
        case kVK_Tab: "Tab"
        case kVK_Escape: "Esc"
        case kVK_F1: "F1"
        case kVK_F2: "F2"
        case kVK_F3: "F3"
        case kVK_F4: "F4"
        case kVK_F5: "F5"
        case kVK_F6: "F6"
        case kVK_F7: "F7"
        case kVK_F8: "F8"
        case kVK_F9: "F9"
        case kVK_F10: "F10"
        case kVK_F11: "F11"
        case kVK_F12: "F12"
        default: ""
        }
    }
}

private extension UInt32 {
    func contains(carbonModifier: Int) -> Bool {
        self & UInt32(carbonModifier) != 0
    }

    func intersection(with mask: UInt32) -> UInt32 {
        self & mask
    }
}
