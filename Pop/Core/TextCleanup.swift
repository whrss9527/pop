import Foundation

/// 文字整理：合并换行、去空行、去多余空格、中英文之间加空格、全角转半角、简繁转换、拼音、按行排序去重。
/// 纯逻辑，方便测试。
enum TextCleanup {
    /// 至少有一种整理方式会让文字变样时才出现在圆盘上：有换行、连续空白、汉字或者全角字母数字。
    static let applicablePattern = #"\n|[ \t\x{00A0}\x{3000}]{2}|\p{Han}|[\x{FF10}-\x{FF19}\x{FF21}-\x{FF3A}\x{FF41}-\x{FF5A}]"#

    /// 只列出会让文字变样的整理方式
    static func conversions(_ text: String) -> [ResultCard.Row] {
        var rows: [ResultCard.Row] = []
        func add(_ label: String, _ value: String?) {
            guard let value, !value.isEmpty, value != text, !rows.contains(where: { $0.value == value }) else { return }
            rows.append(ResultCard.Row(label: label, value: value))
        }
        add("合并换行", joinLines(text))
        add("去掉空行", removeBlankLines(text))
        add("去多余空格", collapseSpaces(text))
        add("中英文空格", spaceBetweenCJKAndLatin(text))
        add("全角转半角", halfWidth(text))
        if ScriptProfile(text).han > 0 {
            add("转为繁体", text.applyingTransform(StringTransform(rawValue: "Hans-Hant"), reverse: false))
            add("转为简体", text.applyingTransform(StringTransform(rawValue: "Hant-Hans"), reverse: false))
            if text.count <= 2000, let pinyin = pinyin(text) {
                add("拼音", pinyin)
                add("无调拼音", stripTones(pinyin))
            }
        }
        add("按行排序", sortLines(text))
        add("按行去重", uniqueLines(text))
        return rows
    }

    // MARK: - 换行和空白

    /// 把段落里被硬换行切开的句子接起来（从 PDF 里复制的文字常见）。空行分开的段落仍然分开。
    /// 英文行尾的连字符（sen-\ntence）去掉后接上；中文、日文接的时候不加空格。
    static func joinLines(_ text: String) -> String? {
        let lines = normalizedLines(text)
        guard lines.count > 1 else { return nil }
        var paragraphs: [String] = []
        var current = ""
        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                if !current.isEmpty {
                    paragraphs.append(current)
                    current = ""
                }
                continue
            }
            guard let last = current.last, let first = line.first else {
                current = line
                continue
            }
            if last == "-", first.isLowercase, current.dropLast().last?.isLetter == true {
                current.removeLast()
                current += line
            } else if isCJK(last) || isCJK(first) {
                current += line
            } else {
                current += " " + line
            }
        }
        if !current.isEmpty {
            paragraphs.append(current)
        }
        return paragraphs.joined(separator: "\n\n")
    }

    static func removeBlankLines(_ text: String) -> String? {
        let lines = normalizedLines(text)
        guard lines.count > 1 else { return nil }
        return lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.joined(separator: "\n")
    }

    /// 连续的空格、制表符（包括不换行空格和全角空格）并成一个，去掉每行首尾的空白
    static func collapseSpaces(_ text: String) -> String {
        normalizedLines(text).map { line in
            line.split(whereSeparator: isHorizontalSpace).joined(separator: " ")
        }.joined(separator: "\n")
    }

    // MARK: - 中英文

    /// 汉字、假名和英文字母、数字挨着时中间加一个空格：用React写 → 用 React 写
    static func spaceBetweenCJKAndLatin(_ text: String) -> String {
        var result = ""
        var previous: Character?
        for character in text {
            if let previous,
               (isHanOrKana(previous) && isLatinOrDigit(character)) || (isLatinOrDigit(previous) && isHanOrKana(character)) {
                result.append(" ")
            }
            result.append(character)
            previous = character
        }
        return result
    }

    /// 全角的字母、数字和空格换成半角：ＡＢＣ１２３ → ABC123。全角标点（，。！？）保持不变。
    static func halfWidth(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0xFF10...0xFF19, 0xFF21...0xFF3A, 0xFF41...0xFF5A:
                scalars.append(Unicode.Scalar(scalar.value - 0xFEE0) ?? scalar)
            case 0x3000:
                scalars.append(" ")
            default:
                scalars.append(scalar)
            }
        }
        return String(scalars)
    }

    /// 汉字转拼音（带声调），音节之间用空格分开
    static func pinyin(_ text: String) -> String? {
        text.applyingTransform(.mandarinToLatin, reverse: false)
    }

    /// 去掉拼音的声调符号，保留 ü
    static func stripTones(_ text: String) -> String {
        let toneMarks: Set<UInt32> = [0x0300, 0x0301, 0x0304, 0x030C]
        let scalars = text.decomposedStringWithCanonicalMapping.unicodeScalars.filter { !toneMarks.contains($0.value) }
        return String(String.UnicodeScalarView(scalars)).precomposedStringWithCanonicalMapping
    }

    // MARK: - 按行

    static func sortLines(_ text: String) -> String? {
        let lines = normalizedLines(text)
        guard lines.filter({ !$0.isEmpty }).count > 1 else { return nil }
        return lines.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.joined(separator: "\n")
    }

    static func uniqueLines(_ text: String) -> String? {
        let lines = normalizedLines(text)
        guard lines.count > 1 else { return nil }
        var seen = Set<String>()
        return lines.filter { seen.insert($0).inserted }.joined(separator: "\n")
    }

    // MARK: - 字符分类

    private static func normalizedLines(_ text: String) -> [String] {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
    }

    private static func isHorizontalSpace(_ character: Character) -> Bool {
        character == " " || character == "\t" || character == "\u{00A0}" || character == "\u{3000}"
    }

    /// 汉字、假名、中日文标点和全角字符：这些字符前后接行时不加空格。谚文按词分行，不算在内。
    static func isCJK(_ character: Character) -> Bool {
        guard let value = character.unicodeScalars.first?.value else { return false }
        switch value {
        case 0x2E80...0x303F, 0x3040...0x30FF, 0x31F0...0x31FF, 0x3400...0x4DBF, 0x4E00...0x9FFF,
             0xF900...0xFAFF, 0xFE30...0xFE4F, 0xFF00...0xFFEF, 0x20000...0x2FFFF:
            return true
        default:
            return false
        }
    }

    private static func isHanOrKana(_ character: Character) -> Bool {
        guard let value = character.unicodeScalars.first?.value else { return false }
        switch value {
        case 0x3040...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x20000...0x2FFFF:
            return true
        default:
            return false
        }
    }

    private static func isLatinOrDigit(_ character: Character) -> Bool {
        character.isASCII && (character.isLetter || character.isNumber)
    }
}
