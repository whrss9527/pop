import AppKit
@testable import Pop

/// 用系统自带的拼写检查（离线）找出外文里拼错的词，给出改法。
enum SpellCheck {
    struct Issue: Equatable {
        var word: String
        var range: NSRange
        var suggestions: [String]
    }

    /// 最多报这么多个，太多了卡片放不下
    static let limit = 30

    /// language 为 nil 时用系统设置里的语言（通常是自动判断）
    @MainActor
    static func issues(in text: String, language: String?) -> [Issue] {
        let checker = NSSpellChecker.shared
        let tag = NSSpellChecker.uniqueSpellDocumentTag()
        defer { checker.closeSpellDocument(withTag: tag) }
        let string = text as NSString
        var issues: [Issue] = []
        var start = 0
        while start < string.length, issues.count < limit {
            let range = checker.checkSpelling(of: text, startingAt: start, language: language, wrap: false,
                                              inSpellDocumentWithTag: tag, wordCount: nil)
            guard range.location != NSNotFound, range.length > 0, range.location >= start else { break }
            let guesses = checker.guesses(forWordRange: range, in: text, language: language, inSpellDocumentWithTag: tag) ?? []
            issues.append(Issue(word: string.substring(with: range), range: range, suggestions: Array(guesses.prefix(4))))
            start = range.location + range.length
        }
        return issues
    }

    /// 系统拼写检查支持这种语言时返回它（en、fr、de……），否则 nil
    @MainActor
    static func supportedLanguage(_ language: String?) -> String? {
        guard let language else { return nil }
        let available = NSSpellChecker.shared.availableLanguages
        if available.contains(language) { return language }
        let base = String(language.prefix(while: { $0 != "-" && $0 != "_" }))
        return available.contains(base) ? base : nil
    }

    /// 每个拼错的词换成第一个建议（没有建议的不动）
    static func corrected(_ text: String, issues: [Issue]) -> String {
        let result = NSMutableString(string: text)
        for issue in issues.sorted(by: { $0.range.location > $1.range.location }) {
            guard let first = issue.suggestions.first, NSMaxRange(issue.range) <= result.length else { continue }
            result.replaceCharacters(in: issue.range, with: first)
        }
        return result as String
    }
}
