import Foundation
import KeyboardShortcuts
import Carbon.HIToolbox
import AppKit

/// Parses shortcut strings like "ctrl+cmd+t" to KeyboardShortcuts.Shortcut and vice versa.
/// Used for migration from YAML config and for any legacy shortcut string handling.
struct ShortcutParser {
    /// Parse a string like "ctrl+cmd+t" into a KeyboardShortcuts.Shortcut
    static func parse(_ string: String) -> KeyboardShortcuts.Shortcut? {
        let parts = string.lowercased().split(separator: "+").map { String($0).trimmingCharacters(in: .whitespaces) }
        guard !parts.isEmpty else { return nil }

        var modifiers: NSEvent.ModifierFlags = []
        var keyString: String?

        for part in parts {
            switch part {
            case "cmd", "command", "⌘":
                modifiers.insert(.command)
            case "ctrl", "control", "⌃":
                modifiers.insert(.control)
            case "opt", "option", "alt", "⌥":
                modifiers.insert(.option)
            case "shift", "⇧":
                modifiers.insert(.shift)
            default:
                keyString = part
            }
        }

        guard let key = keyString, let keyCode = keyCodeForString(key) else {
            return nil
        }

        let shortcutKey = KeyboardShortcuts.Key(rawValue: Int(keyCode))
        return KeyboardShortcuts.Shortcut(shortcutKey, modifiers: modifiers)
    }

    /// Convert a KeyboardShortcuts.Shortcut to a string like "ctrl+cmd+t"
    static func toString(_ shortcut: KeyboardShortcuts.Shortcut) -> String {
        var parts: [String] = []

        if shortcut.modifiers.contains(.control) { parts.append("ctrl") }
        if shortcut.modifiers.contains(.option) { parts.append("opt") }
        if shortcut.modifiers.contains(.shift) { parts.append("shift") }
        if shortcut.modifiers.contains(.command) { parts.append("cmd") }

        if let key = shortcut.key, let keyString = stringForKeyCode(UInt16(key.rawValue)) {
            parts.append(keyString)
        }

        return parts.joined(separator: "+")
    }

    private static func keyCodeForString(_ string: String) -> UInt16? {
        let keyMap: [String: UInt16] = [
            "a": UInt16(kVK_ANSI_A), "b": UInt16(kVK_ANSI_B), "c": UInt16(kVK_ANSI_C),
            "d": UInt16(kVK_ANSI_D), "e": UInt16(kVK_ANSI_E), "f": UInt16(kVK_ANSI_F),
            "g": UInt16(kVK_ANSI_G), "h": UInt16(kVK_ANSI_H), "i": UInt16(kVK_ANSI_I),
            "j": UInt16(kVK_ANSI_J), "k": UInt16(kVK_ANSI_K), "l": UInt16(kVK_ANSI_L),
            "m": UInt16(kVK_ANSI_M), "n": UInt16(kVK_ANSI_N), "o": UInt16(kVK_ANSI_O),
            "p": UInt16(kVK_ANSI_P), "q": UInt16(kVK_ANSI_Q), "r": UInt16(kVK_ANSI_R),
            "s": UInt16(kVK_ANSI_S), "t": UInt16(kVK_ANSI_T), "u": UInt16(kVK_ANSI_U),
            "v": UInt16(kVK_ANSI_V), "w": UInt16(kVK_ANSI_W), "x": UInt16(kVK_ANSI_X),
            "y": UInt16(kVK_ANSI_Y), "z": UInt16(kVK_ANSI_Z),
            "0": UInt16(kVK_ANSI_0), "1": UInt16(kVK_ANSI_1), "2": UInt16(kVK_ANSI_2),
            "3": UInt16(kVK_ANSI_3), "4": UInt16(kVK_ANSI_4), "5": UInt16(kVK_ANSI_5),
            "6": UInt16(kVK_ANSI_6), "7": UInt16(kVK_ANSI_7), "8": UInt16(kVK_ANSI_8),
            "9": UInt16(kVK_ANSI_9),
            "space": UInt16(kVK_Space), "return": UInt16(kVK_Return), "enter": UInt16(kVK_Return),
            "tab": UInt16(kVK_Tab), "escape": UInt16(kVK_Escape), "esc": UInt16(kVK_Escape),
            "delete": UInt16(kVK_Delete), "backspace": UInt16(kVK_Delete),
            "up": UInt16(kVK_UpArrow), "down": UInt16(kVK_DownArrow),
            "left": UInt16(kVK_LeftArrow), "right": UInt16(kVK_RightArrow),
            "f1": UInt16(kVK_F1), "f2": UInt16(kVK_F2), "f3": UInt16(kVK_F3),
            "f4": UInt16(kVK_F4), "f5": UInt16(kVK_F5), "f6": UInt16(kVK_F6),
            "f7": UInt16(kVK_F7), "f8": UInt16(kVK_F8), "f9": UInt16(kVK_F9),
            "f10": UInt16(kVK_F10), "f11": UInt16(kVK_F11), "f12": UInt16(kVK_F12),
        ]
        return keyMap[string.lowercased()]
    }

    private static func stringForKeyCode(_ keyCode: UInt16) -> String? {
        let keyMap: [UInt16: String] = [
            UInt16(kVK_ANSI_A): "a", UInt16(kVK_ANSI_B): "b", UInt16(kVK_ANSI_C): "c",
            UInt16(kVK_ANSI_D): "d", UInt16(kVK_ANSI_E): "e", UInt16(kVK_ANSI_F): "f",
            UInt16(kVK_ANSI_G): "g", UInt16(kVK_ANSI_H): "h", UInt16(kVK_ANSI_I): "i",
            UInt16(kVK_ANSI_J): "j", UInt16(kVK_ANSI_K): "k", UInt16(kVK_ANSI_L): "l",
            UInt16(kVK_ANSI_M): "m", UInt16(kVK_ANSI_N): "n", UInt16(kVK_ANSI_O): "o",
            UInt16(kVK_ANSI_P): "p", UInt16(kVK_ANSI_Q): "q", UInt16(kVK_ANSI_R): "r",
            UInt16(kVK_ANSI_S): "s", UInt16(kVK_ANSI_T): "t", UInt16(kVK_ANSI_U): "u",
            UInt16(kVK_ANSI_V): "v", UInt16(kVK_ANSI_W): "w", UInt16(kVK_ANSI_X): "x",
            UInt16(kVK_ANSI_Y): "y", UInt16(kVK_ANSI_Z): "z",
            UInt16(kVK_ANSI_0): "0", UInt16(kVK_ANSI_1): "1", UInt16(kVK_ANSI_2): "2",
            UInt16(kVK_ANSI_3): "3", UInt16(kVK_ANSI_4): "4", UInt16(kVK_ANSI_5): "5",
            UInt16(kVK_ANSI_6): "6", UInt16(kVK_ANSI_7): "7", UInt16(kVK_ANSI_8): "8",
            UInt16(kVK_ANSI_9): "9",
            UInt16(kVK_Space): "space", UInt16(kVK_Return): "return",
            UInt16(kVK_Tab): "tab", UInt16(kVK_Escape): "escape",
            UInt16(kVK_Delete): "delete",
            UInt16(kVK_UpArrow): "up", UInt16(kVK_DownArrow): "down",
            UInt16(kVK_LeftArrow): "left", UInt16(kVK_RightArrow): "right",
            UInt16(kVK_F1): "f1", UInt16(kVK_F2): "f2", UInt16(kVK_F3): "f3",
            UInt16(kVK_F4): "f4", UInt16(kVK_F5): "f5", UInt16(kVK_F6): "f6",
            UInt16(kVK_F7): "f7", UInt16(kVK_F8): "f8", UInt16(kVK_F9): "f9",
            UInt16(kVK_F10): "f10", UInt16(kVK_F11): "f11", UInt16(kVK_F12): "f12",
        ]
        return keyMap[keyCode]
    }
}
