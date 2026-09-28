import Foundation

/// Unix 时间戳识别与格式化。
enum TimestampConverter {
    /// 10 位（秒）或 13 位（毫秒）纯数字，且落在 2001-09-09 ~ 2100-01-01 之间才认为是时间戳。
    static func date(from text: String) -> Date? {
        guard text.count == 10 || text.count == 13,
              text.allSatisfy({ $0.isASCII && $0.isNumber }),
              let value = Double(text) else { return nil }
        let seconds = text.count == 13 ? value / 1000 : value
        guard seconds >= 1_000_000_000, seconds < 4_102_444_800 else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    static func localString(_ date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }

    static func isoString(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}

enum JSONFormatter {
    static func isJSON(_ text: String) -> Bool {
        parse(text) != nil
    }

    static func prettyPrinted(_ text: String) -> String? {
        guard let object = parse(text),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private static func parse(_ text: String) -> Any? {
        guard let first = text.first, let last = text.last,
              (first == "{" && last == "}") || (first == "[" && last == "]"),
              let data = text.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }
}

/// 文本的文字系统构成，用来区分中文和外文。
struct ScriptProfile: Equatable {
    var han = 0
    var kana = 0
    var hangul = 0
    /// 其他字母文字（拉丁、西里尔等）组成的单词数
    var otherWords = 0

    init(_ text: String) {
        var inWord = false
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x4E00...0x9FFF, 0x3400...0x4DBF, 0x20000...0x2A6DF, 0xF900...0xFAFF:
                han += 1
                inWord = false
            case 0x3040...0x30FF:
                kana += 1
                inWord = false
            case 0xAC00...0xD7AF, 0x1100...0x11FF:
                hangul += 1
                inWord = false
            default:
                if scalar.properties.isAlphabetic {
                    if !inWord { otherWords += 1 }
                    inWord = true
                } else {
                    inWord = false
                }
            }
        }
    }

    /// 以中文为主：有汉字、没有假名/谚文，并且汉字数不少于其他文字的单词数
    /// （这样「用 React 写个组件」这种中英混排仍算中文）。
    var isChinese: Bool {
        han > 0 && kana == 0 && hangul == 0 && han >= otherWords
    }

    var hasLetters: Bool {
        han + kana + hangul + otherWords > 0
    }
}
