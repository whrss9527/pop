import Foundation

/// 按行处理：一列文字（每行一项）加引号和逗号、转 JSON 数组、加减序号、倒序、打乱；一行用逗号隔开的拆成多行。
/// 纯逻辑，方便测试。
enum LineTools {
    struct Items: Equatable {
        var values: [String]
        /// 原来就是一行一项（否则是一行里用分隔符隔开的）
        var fromLines: Bool
    }

    static let maxItems = 10_000

    /// 一行里能拆开的分隔符，按优先级排
    private static let separators = ["\t", "，", "、", "；", ";", "|", ","]

    static func items(_ text: String) -> Items? {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if lines.count >= 2 {
            return lines.count <= maxItems ? Items(values: lines, fromLines: true) : nil
        }
        guard let line = lines.first else { return nil }
        for separator in separators where line.contains(separator) {
            let values = line.components(separatedBy: separator)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            if values.count >= 2, values.count <= maxItems {
                return Items(values: values, fromLines: false)
            }
        }
        return nil
    }

    /// 圆盘里要不要显示：至少两项，每项都不太长（像是一列值，不是几段文章）
    static func isApplicable(_ text: String) -> Bool {
        guard let parsed = items(text) else { return false }
        return parsed.values.allSatisfy { $0.count <= 200 }
    }

    /// 「1. 」「2、」「(3)」「- 」「• 」这样的序号和项目符号；1.5、-5 这样的数不算
    private static let numbering = try! NSRegularExpression(pattern: #"^(?:\d+(?:[)、．]|\.(?!\d))|[(（]\d+[)）]|[-*]\s|[•·])\s*"#)
    private static let plainNumber = try! NSRegularExpression(pattern: #"^-?(?:0|[1-9]\d*)(?:\.\d+)?$"#)

    static func conversions(_ text: String) -> [ResultCard.Row] {
        guard let parsed = items(text) else { return [] }
        let values = parsed.values
        var rows: [ResultCard.Row] = []
        func add(_ label: String, _ value: String?) {
            guard let value, value != text.trimmingCharacters(in: .whitespacesAndNewlines),
                  !rows.contains(where: { $0.value == value }) else { return }
            rows.append(ResultCard.Row(label: label, value: value))
        }
        if !parsed.fromLines {
            add("拆成多行", values.joined(separator: "\n"))
        }
        add("逗号隔开", values.joined(separator: ", "))
        add("单引号", values.map { "'" + $0.replacingOccurrences(of: "'", with: "''") + "'" }.joined(separator: ", "))
        add("双引号", values.map(jsonString).joined(separator: ", "))
        let numeric = values.allSatisfy { plainNumber.firstMatch(in: $0, range: NSRange($0.startIndex..., in: $0)) != nil }
        add("JSON 数组", "[" + (numeric ? values : values.map(jsonString)).joined(separator: ", ") + "]")
        let stripped = values.map(removingNumbering)
        if stripped != values {
            add("去掉序号", stripped.joined(separator: "\n"))
        } else {
            add("加序号", values.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n"))
        }
        if let unquoted = removingQuotes(values) {
            add("去掉引号", unquoted.joined(separator: "\n"))
        }
        let separator = parsed.fromLines ? "\n" : ", "
        add("倒序", values.reversed().joined(separator: separator))
        if values.count > 2 {
            add("打乱顺序", values.shuffled().joined(separator: separator))
        }
        return rows
    }

    static func removingNumbering(_ value: String) -> String {
        numbering.stringByReplacingMatches(in: value, range: NSRange(value.startIndex..., in: value), withTemplate: "")
    }

    /// 每一项都用同一种引号包着时去掉引号
    static func removingQuotes(_ values: [String]) -> [String]? {
        let pairs: [(Character, Character)] = [("'", "'"), ("\"", "\""), ("“", "”"), ("`", "`")]
        for (open, close) in pairs where values.allSatisfy({ $0.count >= 2 && $0.first == open && $0.last == close }) {
            return values.map { String($0.dropFirst().dropLast()) }
        }
        return nil
    }

    static func jsonString(_ value: String) -> String {
        var result = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": result += "\\\""
            case "\\": result += "\\\\"
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            default:
                if scalar.value < 0x20 {
                    result += String(format: "\\u%04X", scalar.value)
                } else {
                    result.unicodeScalars.append(scalar)
                }
            }
        }
        return result + "\""
    }
}
