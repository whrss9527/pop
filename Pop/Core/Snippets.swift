import Foundation

/// 常用短语：存好的一段文字，从圆盘或快捷键里选一条，粘贴到当前 App。
struct Snippet: Codable, Equatable, Identifiable {
    var id: String
    var title: String
    var text: String

    init(id: String = UUID().uuidString, title: String, text: String) {
        self.id = id
        self.title = title
        self.text = text
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.lenient(.id, default: UUID().uuidString)
        title = c.lenient(.title, default: "")
        text = try c.decode(String.self, forKey: .text)
    }

    /// 列表里显示的名字：没写标题时用内容的第一行
    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return text.split(whereSeparator: \.isNewline).first.map { String($0.prefix(40)) } ?? String(localized: "（空）")
    }

    /// 新装的 Pop 里带的两个例子，演示占位符怎么用
    static let examples = [
        Snippet(id: "example-date", title: String(localized: "今天的日期"), text: "{date}"),
        Snippet(id: "example-signature", title: String(localized: "邮件结尾"), text: String(localized: "祝好！\n\n{date}")),
    ]
}

/// 短语里的占位符，粘贴时换成当时的内容
enum SnippetExpander {
    struct Placeholder: Identifiable {
        let token: String
        let meaning: String

        var id: String { token }
    }

    static let placeholders = [
        Placeholder(token: "{date}", meaning: String(localized: "今天的日期，比如 2026-09-29")),
        Placeholder(token: "{time}", meaning: String(localized: "现在的时间，比如 14:30")),
        Placeholder(token: "{datetime}", meaning: String(localized: "日期和时间")),
        Placeholder(token: "{weekday}", meaning: String(localized: "星期几")),
        Placeholder(token: "{clipboard}", meaning: String(localized: "剪贴板里的文字")),
        Placeholder(token: "{selection}", meaning: String(localized: "唤起时选中的文字")),
    ]

    static func expand(_ text: String, date: Date = Date(), timeZone: TimeZone = .current,
                       clipboard: String? = nil, selection: String? = nil) -> String {
        guard text.contains("{") else { return text }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        func format(_ pattern: String) -> String {
            formatter.dateFormat = pattern
            return formatter.string(from: date)
        }
        let weekday = DateFormatter()
        weekday.locale = Locale(identifier: "zh_CN")
        weekday.timeZone = timeZone
        weekday.dateFormat = "EEEE"
        return text
            .replacingOccurrences(of: "{datetime}", with: format("yyyy-MM-dd HH:mm"))
            .replacingOccurrences(of: "{date}", with: format("yyyy-MM-dd"))
            .replacingOccurrences(of: "{time}", with: format("HH:mm"))
            .replacingOccurrences(of: "{weekday}", with: weekday.string(from: date))
            .replacingOccurrences(of: "{clipboard}", with: clipboard ?? "")
            .replacingOccurrences(of: "{selection}", with: selection ?? "")
    }
}
