import Carbon
import AppKit

struct KeyCombo: Equatable {
    let keyCode: UInt16
    let modifiers: NSEvent.ModifierFlags

    var carbonKeyCode: UInt32 { UInt32(keyCode) }
    var carbonModifiers: UInt32 {
        var m: UInt32 = 0
        if modifiers.contains(.command) { m |= UInt32(cmdKey) }
        if modifiers.contains(.option)  { m |= UInt32(optionKey) }
        if modifiers.contains(.shift)   { m |= UInt32(shiftKey) }
        if modifiers.contains(.control) { m |= UInt32(controlKey) }
        return m
    }

    var displayString: String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("\u{2303}") }
        if modifiers.contains(.option)  { parts.append("\u{2325}") }
        if modifiers.contains(.shift)   { parts.append("\u{21E7}") }
        if modifiers.contains(.command) { parts.append("\u{2318}") }
        parts.append(keyName(for: keyCode))
        return parts.joined()
    }

    static func from(event: NSEvent) -> KeyCombo {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return KeyCombo(keyCode: event.keyCode, modifiers: flags)
    }

    func save() {
        UserDefaults.standard.set(Int(keyCode), forKey: "hotkeyKeyCode")
        UserDefaults.standard.set(Int(modifiers.rawValue), forKey: "hotkeyModifiers")
    }

    static func load() -> KeyCombo? {
        guard UserDefaults.standard.object(forKey: "hotkeyKeyCode") != nil else { return nil }
        let code = UserDefaults.standard.integer(forKey: "hotkeyKeyCode")
        let mods = UserDefaults.standard.integer(forKey: "hotkeyModifiers")
        return KeyCombo(keyCode: UInt16(code), modifiers: NSEvent.ModifierFlags(rawValue: UInt(mods)))
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: "hotkeyKeyCode")
        UserDefaults.standard.removeObject(forKey: "hotkeyModifiers")
    }
}

// Stored globally so the Carbon C callback can reach it
private var hotkeyCallback: (() -> Void)?

final class HotkeyManager {
    static let shared = HotkeyManager()
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    func register(combo: KeyCombo, handler: @escaping () -> Void) {
        unregister()
        hotkeyCallback = handler

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        // Install handler on the application target
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_: EventHandlerCallRef?, _: EventRef?, _: UnsafeMutableRawPointer?) -> OSStatus in
                hotkeyCallback?()
                return noErr
            },
            1,
            &eventType,
            nil,
            &handlerRef
        )
        let signature: FourCharCode = 0x434C5354  // "CLST"
        var hotKeyID = EventHotKeyID(signature: signature, id: 1)
        RegisterEventHotKey(
            combo.carbonKeyCode,
            combo.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            OptionBits(0),
            &hotKeyRef
        )
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let ref = handlerRef {
            RemoveEventHandler(ref)
            handlerRef = nil
        }
        hotkeyCallback = nil
    }
}

// MARK: - Key name lookup

private func keyName(for keyCode: UInt16) -> String {
    let names: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
        8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
        16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
        23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
        30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P",
        37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\",
        43: ",", 44: "/", 45: "N", 46: "M", 47: ".",
        49: "Space", 50: "`",
        36: "\u{21A9}", // Return
        48: "\u{21E5}", // Tab
        51: "\u{232B}", // Delete
        53: "Esc",
        96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8",
        101: "F9", 103: "F11", 105: "F13", 107: "F14",
        109: "F10", 111: "F12", 113: "F15",
        118: "F4", 119: "F2", 120: "F1", 122: "F16",
        123: "\u{2190}", 124: "\u{2192}", 125: "\u{2193}", 126: "\u{2191}",
    ]
    return names[keyCode] ?? "Key\(keyCode)"
}
