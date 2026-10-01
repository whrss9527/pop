import Foundation
@testable import Pop

/// 正则测试：在一段文字里试正则表达式，列出每处匹配和分组，也可以试替换。纯逻辑，方便测试。
enum RegexTester {
    struct Options: Equatable {
        var ignoreCase = false
        /// ^ $ 匹配每一行的开头结尾
        var multiline = true
        /// . 也匹配换行
        var dotAll = false

        var regexOptions: NSRegularExpression.Options {
            var options: NSRegularExpression.Options = []
            if ignoreCase { options.insert(.caseInsensitive) }
            if multiline { options.insert(.anchorsMatchLines) }
            if dotAll { options.insert(.dotMatchesLineSeparators) }
            return options
        }
    }

    struct Match: Equatable {
        var range: NSRange
        var text: String
        /// 每个分组匹配到的文字；没参与匹配的分组是 nil
        var groups: [String?]
        /// 命名分组（?<name>…）的名字，和 groups 一一对应；没起名字的是 nil
        var groupNames: [String?]
    }

    struct Result: Equatable {
        var matches: [Match] = []
        /// 匹配太多只列出前面的
        var truncated = false
        /// 表达式写错了，或者匹配太久被停下
        var error: String?
    }

    static let maxMatches = 1000
    /// 一次匹配最多跑这么久（防止写出回溯爆炸的表达式卡住）
    static let timeLimit: TimeInterval = 1.5

    static func run(_ pattern: String, on text: String, options: Options = Options()) -> Result {
        guard !pattern.isEmpty else { return Result() }
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options.regexOptions) else {
            return Result(error: String(localized: "表达式写得不对：括号、方括号是否成对，转义是否完整？"))
        }
        let names = groupNames(in: pattern, count: regex.numberOfCaptureGroups)
        let string = text as NSString
        var result = Result()
        let started = Date()
        regex.enumerateMatches(in: text, options: [.reportProgress], range: NSRange(location: 0, length: string.length)) { match, _, stop in
            if Date().timeIntervalSince(started) > timeLimit {
                result.error = String(localized: "匹配太久被停下了，表达式里可能有嵌套的重复（比如 (a+)+）")
                stop.pointee = true
                return
            }
            guard let match else { return }
            guard result.matches.count < maxMatches else {
                result.truncated = true
                stop.pointee = true
                return
            }
            let groups: [String?] = (0..<regex.numberOfCaptureGroups).map { index in
                let range = match.range(at: index + 1)
                return range.location == NSNotFound ? nil : string.substring(with: range)
            }
            result.matches.append(Match(range: match.range, text: string.substring(with: match.range), groups: groups,
                                        groupNames: names))
        }
        return result
    }

    /// 替换结果；$1 引用第一个分组，$0 是整个匹配。表达式有误时返回 nil
    static func replace(_ pattern: String, with template: String, in text: String, options: Options = Options()) -> String? {
        guard !pattern.isEmpty,
              let regex = try? NSRegularExpression(pattern: pattern, options: options.regexOptions) else { return nil }
        return regex.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length),
                                              withTemplate: template)
    }

    /// 按左括号出现的顺序找出每个分组的名字：(?<year>…) 是 year，(…) 没有名字，(?:…) (?=…) 这些不算分组
    static func groupNames(in pattern: String, count: Int) -> [String?] {
        var names: [String?] = []
        let characters = Array(pattern)
        var index = 0
        var inClass = false
        while index < characters.count {
            let character = characters[index]
            if character == "\\" {
                index += 2
                continue
            }
            if inClass {
                if character == "]" { inClass = false }
            } else if character == "[" {
                inClass = true
            } else if character == "(" {
                if index + 1 < characters.count, characters[index + 1] == "?" {
                    // (?<name>…) 和 (?P<name>…)，(?<= 和 (?<! 是断言
                    var start = index + 2
                    if start < characters.count, characters[start] == "P" { start += 1 }
                    if start < characters.count, characters[start] == "<",
                       start + 1 < characters.count, characters[start + 1] != "=", characters[start + 1] != "!",
                       let end = characters[(start + 1)...].firstIndex(of: ">") {
                        names.append(String(characters[(start + 1)..<end]))
                    }
                } else {
                    names.append(nil)
                }
            }
            index += 1
        }
        // 数不对（比如遇到没见过的写法）时不显示名字
        return names.count == count ? names : Array(repeating: nil, count: count)
    }

    struct Preset: Identifiable {
        var title: String
        var pattern: String

        var id: String { title }
    }

    /// 常用的表达式，卡片上的「常用」菜单
    static let presets: [Preset] = [
        Preset(title: String(localized: "数字"), pattern: #"-?\d+(?:\.\d+)?"#),
        Preset(title: String(localized: "中文"), pattern: #"\p{Han}+"#),
        Preset(title: String(localized: "英文单词"), pattern: #"\b[A-Za-z]+(?:'[A-Za-z]+)?\b"#),
        Preset(title: String(localized: "邮箱"), pattern: #"[\w.%+-]+@[\w-]+(?:\.[\w-]+)+"#),
        Preset(title: String(localized: "手机号"), pattern: #"(?<!\d)1[3-9]\d{9}(?!\d)"#),
        Preset(title: String(localized: "网址"), pattern: #"https?://[^\s"'<>，。）]+"#),
        Preset(title: String(localized: "IP 地址"), pattern: #"\b(?:\d{1,3}\.){3}\d{1,3}\b"#),
        Preset(title: String(localized: "日期"), pattern: #"(?<year>\d{4})[-/.](?<month>\d{1,2})[-/.](?<day>\d{1,2})"#),
        Preset(title: String(localized: "空行"), pattern: #"^[ \t]*$\n?"#),
        Preset(title: String(localized: "行首尾空白"), pattern: #"^[ \t]+|[ \t]+$"#),
    ]

    /// 匹配列表里的一行：「2026-09-29 · year = 2026 · $2 = 09」
    static func describe(_ match: Match) -> String {
        var parts = [match.text.isEmpty ? String(localized: "（空）") : match.text]
        for (offset, group) in match.groups.enumerated() {
            let name = match.groupNames.indices.contains(offset) ? match.groupNames[offset] : nil
            parts.append("\(name ?? "$\(offset + 1)") = \(group ?? String(localized: "（未参与）"))")
        }
        return parts.joined(separator: " · ")
    }
}
