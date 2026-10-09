import AppKit
import Carbon.HIToolbox
import Combine

/// 一个全局快捷键：Carbon 键码 + 修饰键（cmdKey、optionKey、controlKey、shiftKey 的组合）。
struct KeyCombo: Codable, Equatable, Hashable {
    var keyCode: UInt32
    var modifiers: UInt32

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// 从按键事件得到快捷键。至少要带 ⌘、⌥、⌃ 中的一个（F1–F20 可以单独用）；只按了修饰键时返回 nil。
    init?(event: NSEvent) {
        self.init(keyCode: UInt32(event.keyCode), flags: event.modifierFlags)
    }

    init?(keyCode: UInt32, flags: NSEvent.ModifierFlags) {
        let flags = flags.intersection(.deviceIndependentFlagsMask)
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        guard !Self.modifierKeyCodes.contains(Int(keyCode)) else { return nil }
        let hasPrimaryModifier = modifiers & UInt32(cmdKey | optionKey | controlKey) != 0
        guard hasPrimaryModifier || Self.functionKeys[Int(keyCode)] != nil else { return nil }
        self.init(keyCode: keyCode, modifiers: modifiers)
    }

    /// 显示用：⌃⌥⇧⌘ 加按键，比如 ⌥⌘T
    var display: String {
        var result = ""
        if modifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { result += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { result += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { result += "⌘" }
        return result + Self.keyName(keyCode)
    }

    var isOptionOnly: Bool {
        modifiers & UInt32(cmdKey | optionKey | controlKey) == UInt32(optionKey)
    }

    static func keyName(_ keyCode: UInt32) -> String {
        let code = Int(keyCode)
        if let name = functionKeys[code] ?? specialKeys[code] ?? characterKeys[code] {
            return name
        }
        return "#\(code)"
    }

    private static let modifierKeyCodes: Set<Int> = [
        kVK_Command, kVK_RightCommand, kVK_Shift, kVK_RightShift, kVK_Option, kVK_RightOption,
        kVK_Control, kVK_RightControl, kVK_CapsLock, kVK_Function,
    ]

    private static let functionKeys: [Int: String] = [
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7",
        kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12", kVK_F13: "F13",
        kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18", kVK_F19: "F19",
        kVK_F20: "F20",
    ]

    private static let specialKeys: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_Escape: "⎋", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟", kVK_ANSI_KeypadEnter: "⌤",
    ]

    /// 按美式键盘布局的字符显示
    private static let characterKeys: [Int: String] = [
        kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D", kVK_ANSI_E: "E", kVK_ANSI_F: "F",
        kVK_ANSI_G: "G", kVK_ANSI_H: "H", kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L",
        kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O", kVK_ANSI_P: "P", kVK_ANSI_Q: "Q", kVK_ANSI_R: "R",
        kVK_ANSI_S: "S", kVK_ANSI_T: "T", kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
        kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z",
        kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3", kVK_ANSI_4: "4",
        kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8", kVK_ANSI_9: "9",
        kVK_ANSI_Minus: "-", kVK_ANSI_Equal: "=", kVK_ANSI_LeftBracket: "[", kVK_ANSI_RightBracket: "]",
        kVK_ANSI_Backslash: "\\", kVK_ANSI_Semicolon: ";", kVK_ANSI_Quote: "'", kVK_ANSI_Comma: ",",
        kVK_ANSI_Period: ".", kVK_ANSI_Slash: "/", kVK_ANSI_Grave: "`",
    ]
}

enum ShortcutTarget: Equatable {
    case ring
    case clipboard
    case plugin(String)
}

/// 给某个功能设置的全局快捷键
struct PluginHotKey: Codable, Equatable, Identifiable {
    var pluginID: String
    var key: KeyCombo

    var id: String { pluginID }
}

/// 同时只允许一个控件录入；先更新所有者再通知，旧控件退出时不能结束新控件的录入。
@MainActor
final class ShortcutRecordingState {
    static let shared = ShortcutRecordingState()
    private(set) var activeID: UUID?
    let changes = PassthroughSubject<UUID?, Never>()

    func begin(_ id: UUID) {
        activeID = id
        changes.send(id)
    }

    func end(_ id: UUID) {
        guard activeID == id else { return }
        activeID = nil
        changes.send(nil)
    }
}
