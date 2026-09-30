import Carbon
import CoreGraphics
import Foundation

/// 显示按键：把按下的组合键写成「⇧⌘4」「⌘Z ×3」。
/// 只显示带 ⌘、⌃ 的组合和回车、Esc、方向键这些特殊键；普通打字（字母、数字、只带 ⇧ 或 ⌥ 的符号）不显示，免得把输入的密码露出来。
enum Keystrokes {
    /// 特殊键：虚拟键码 → 符号
    static let specialKeys: [Int: String] = [
        36: "↩", 76: "⌤", 48: "⇥", 49: "␣", 51: "⌫", 117: "⌦", 53: "⎋",
        123: "←", 124: "→", 125: "↓", 126: "↑", 115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]

    /// 美式键盘上各个键的字符（读不到当前键盘布局时用）
    static let ansiKeys: [Int: String] = [
        0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H", 34: "I", 38: "J", 40: "K", 37: "L", 46: "M",
        45: "N", 31: "O", 35: "P", 12: "Q", 15: "R", 1: "S", 17: "T", 32: "U", 9: "V", 13: "W", 7: "X", 16: "Y", 6: "Z",
        29: "0", 18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9",
        27: "-", 24: "=", 33: "[", 30: "]", 42: "\\", 41: ";", 39: "'", 43: ",", 47: ".", 44: "/", 50: "`",
    ]

    /// 这一下按键要显示成什么；普通打字返回 nil。character 是这个键不按修饰键时打出的字符
    static func text(keyCode: Int, flags: CGEventFlags, character: String?) -> String? {
        let command = flags.contains(.maskCommand)
        let control = flags.contains(.maskControl)
        let option = flags.contains(.maskAlternate)
        let shift = flags.contains(.maskShift)
        let special = specialKeys[keyCode]
        // 不带 ⌘、⌃ 的字母数字是在打字（⌥ 能打出特殊字符），不显示
        guard special != nil || command || control else { return nil }
        // 不带修饰键的空格也是打字
        if keyCode == 49, !command, !control, !option { return nil }
        let typed = character.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0.uppercased() }
        guard let key = special ?? typed ?? ansiKeys[keyCode] else { return nil }
        var text = ""
        if control { text += "⌃" }
        if option { text += "⌥" }
        if shift { text += "⇧" }
        if command { text += "⌘" }
        return text + key
    }

    /// 屏幕上正显示的一个组合
    struct Display: Equatable {
        var text: String
        var count: Int
        var time: TimeInterval

        /// 连着按了几次同一个组合：「⌘Z ×3」
        var label: String { count > 1 ? "\(text) ×\(count)" : text }
    }

    /// 按下 text 以后显示什么：和上一个一样、隔得不久就加一次，不然换成新的
    static func next(after previous: Display?, text: String, at time: TimeInterval, repeatWindow: TimeInterval = 1.5) -> Display {
        if let previous, previous.text == text, time - previous.time <= repeatWindow {
            return Display(text: text, count: previous.count + 1, time: time)
        }
        return Display(text: text, count: 1, time: time)
    }

    /// 当前键盘布局下这个键不按修饰键时打出的字符（法语键盘上 A、Q 的位置和美式不一样）。
    /// 用能打英文的那个布局：俄文这类布局下按 ⌘ 组合键时，系统也是照它认的
    static func baseCharacter(keyCode: Int) -> String? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        return data.withUnsafeBytes { buffer -> String? in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
            var deadKeys: UInt32 = 0
            var length = 0
            var characters = [UniChar](repeating: 0, count: 4)
            let status = UCKeyTranslate(layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                        OptionBits(1 << kUCKeyTranslateNoDeadKeysBit), &deadKeys, characters.count, &length, &characters)
            guard status == noErr, length > 0 else { return nil }
            return String(utf16CodeUnits: characters, count: length)
        }
    }
}
