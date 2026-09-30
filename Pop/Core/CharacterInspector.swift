import Foundation

/// 字符信息：每个字符的 Unicode 码点、名称、UTF-8 / UTF-16 编码；找出零宽空格这类看不见的字符。纯逻辑，方便测试。
enum CharacterInspector {
    /// 逐个列出的字符数上限（超过时只检查看不见的字符）
    static let maxListed = 20

    /// 看不见、但会让文字出问题的字符（从网页、聊天软件复制的文字里常见）
    static let invisibleNames: [UInt32: String] = [
        0x00A0: String(localized: "不换行空格"),
        0x00AD: String(localized: "软连字符"),
        0x034F: String(localized: "字形连接符"),
        0x061C: String(localized: "阿拉伯字母标记"),
        0x115F: String(localized: "韩文填充符"),
        0x1160: String(localized: "韩文填充符"),
        0x17B4: String(localized: "高棉文隐藏元音"),
        0x17B5: String(localized: "高棉文隐藏元音"),
        0x180E: String(localized: "蒙古文元音分隔符"),
        0x200B: String(localized: "零宽空格"),
        0x200C: String(localized: "零宽不连字"),
        0x200D: String(localized: "零宽连字"),
        0x200E: String(localized: "从左到右标记"),
        0x200F: String(localized: "从右到左标记"),
        0x2028: String(localized: "行分隔符"),
        0x2029: String(localized: "段分隔符"),
        0x202A: String(localized: "双向文字控制"),
        0x202B: String(localized: "双向文字控制"),
        0x202C: String(localized: "双向文字控制"),
        0x202D: String(localized: "双向文字控制"),
        0x202E: String(localized: "双向文字控制"),
        0x2060: String(localized: "字连接符"),
        0x2061: String(localized: "不可见运算符"),
        0x2062: String(localized: "不可见运算符"),
        0x2063: String(localized: "不可见运算符"),
        0x2064: String(localized: "不可见运算符"),
        0x2066: String(localized: "双向文字隔离"),
        0x2067: String(localized: "双向文字隔离"),
        0x2068: String(localized: "双向文字隔离"),
        0x2069: String(localized: "双向文字隔离"),
        0x3164: String(localized: "韩文填充符"),
        0xFEFF: "BOM",
        0xFFA0: String(localized: "韩文填充符"),
    ]

    /// 常见空白字符的叫法（名称栏里显示它，不然什么都看不见）
    private static let spaceNames: [UInt32: String] = [
        0x09: String(localized: "制表符"), 0x0A: String(localized: "换行"), 0x0D: String(localized: "回车"), 0x20: String(localized: "空格"), 0x3000: String(localized: "全角空格"),
    ]

    struct Found: Equatable {
        var scalar: Unicode.Scalar
        var name: String
        var count: Int
    }

    /// 文字里看不见的字符，按第一次出现的顺序；表情符号里用来连接的零宽连字不算
    static func invisibles(in text: String) -> [Found] {
        let scalars = Array(text.unicodeScalars)
        var result: [Found] = []
        for (index, scalar) in scalars.enumerated() where isInvisible(at: index, in: scalars) {
            if let existing = result.firstIndex(where: { $0.scalar == scalar }) {
                result[existing].count += 1
            } else {
                result.append(Found(scalar: scalar, name: invisibleNames[scalar.value] ?? scalarName(scalar), count: 1))
            }
        }
        return result
    }

    private static func isInvisible(at index: Int, in scalars: [Unicode.Scalar]) -> Bool {
        let scalar = scalars[index]
        guard invisibleNames[scalar.value] != nil else { return false }
        if scalar.value == 0x200D, index > 0, index + 1 < scalars.count,
           isEmojiLike(scalars[index - 1]), isEmojiLike(scalars[index + 1]) {
            return false
        }
        return true
    }

    private static func isEmojiLike(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value == 0xFE0F || (0x1F3FB...0x1F3FF).contains(scalar.value)
            || (scalar.value >= 0x2000 && scalar.properties.isEmoji)
    }

    /// 去掉看不见的字符：不换行空格换成普通空格，行、段分隔符换成换行，其余直接删掉
    static func removingInvisibles(_ text: String) -> String {
        let scalars = Array(text.unicodeScalars)
        var result = String.UnicodeScalarView()
        for (index, scalar) in scalars.enumerated() {
            guard isInvisible(at: index, in: scalars) else {
                result.append(scalar)
                continue
            }
            switch scalar.value {
            case 0x00A0: result.append(" ")
            case 0x2028, 0x2029: result.append("\n")
            default: continue
            }
        }
        return String(result)
    }

    static func scalarName(_ scalar: Unicode.Scalar) -> String {
        scalar.properties.name ?? scalar.properties.nameAlias ?? String(localized: "（没有名称）")
    }

    static func codePoint(_ scalar: Unicode.Scalar) -> String {
        String(format: "U+%04X", scalar.value)
    }

    /// 一个字（可能由几个码点组成，比如带肤色的表情）的说明
    static func describe(_ character: Character) -> String {
        let scalars = Array(character.unicodeScalars)
        let points = scalars.map(codePoint).joined(separator: " ")
        let names = scalars.map { scalar in invisibleNames[scalar.value] ?? scalarName(scalar) }.joined(separator: " + ")
        let utf8 = String(character).utf8.map { String(format: "%02X", $0) }.joined(separator: " ")
        var lines = ["\(points) · \(names)", "UTF-8 \(utf8)"]
        if scalars.contains(where: { $0.value > 0xFFFF }) {
            let utf16 = String(character).utf16.map { String(format: "%04X", $0) }.joined(separator: " ")
            lines[1] += " · UTF-16 \(utf16)"
        }
        return lines.joined(separator: "\n")
    }

    /// 名称栏：看不见的字符写出叫法，其他的就是字符本身
    static func label(_ character: Character) -> String {
        let scalars = character.unicodeScalars
        if scalars.count == 1, let scalar = scalars.first {
            if let name = spaceNames[scalar.value] ?? invisibleNames[scalar.value] { return name }
            if scalar.properties.generalCategory == .control || scalar.properties.generalCategory == .format {
                return codePoint(scalar)
            }
        }
        return String(character)
    }

    /// 圆盘里要不要显示：字不多（逐个看），或者里面有看不见的字符
    static func isApplicable(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return trimmed.count <= maxListed || !invisibles(in: text).isEmpty
    }

    static func card(for text: String) -> ResultCard {
        let found = invisibles(in: text)
        var rows: [ResultCard.Row] = []
        var seen = Set<Character>()
        let listed = text.count <= maxListed
        if listed {
            for character in text where seen.insert(character).inserted {
                // 名称栏重复时（比如两种双向控制字符）加上码点区分
                var name = Self.label(character)
                if rows.contains(where: { $0.label == name }) {
                    name += " " + character.unicodeScalars.map(codePoint).joined(separator: " ")
                }
                rows.append(ResultCard.Row(label: name, value: describe(character)))
            }
        } else {
            for item in found {
                rows.append(ResultCard.Row(label: "\(item.name) \(codePoint(item.scalar))",
                                           value: String(localized: "\(codePoint(item.scalar)) · \(scalarName(item.scalar)) · \(item.count) 处")))
            }
        }
        var buttons: [CardButton] = []
        var detail: String?
        if !found.isEmpty {
            let total = found.reduce(0) { $0 + $1.count }
            let kinds = found.map { "\($0.name) ×\($0.count)" }.joined(separator: "、")
            detail = String(localized: "有 \(total) 个看不见的字符：\(kinds)")
            let cleaned = removingInvisibles(text)
            buttons.append(CardButton(title: String(localized: "去掉后替换原文"), action: .replace(cleaned)))
            buttons.append(CardButton(title: String(localized: "去掉后复制"), action: .copy(cleaned)))
        } else if !listed {
            detail = String(localized: "没有看不见的字符")
        }
        if listed {
            let points = text.unicodeScalars.map(codePoint).joined(separator: " ")
            buttons.insert(CardButton(title: String(localized: "复制码点"), action: .copy(points)), at: 0)
        }
        return ResultCard(title: String(localized: "字符信息"), detail: detail, rows: rows, rowLineLimit: 3, buttons: buttons)
    }
}
