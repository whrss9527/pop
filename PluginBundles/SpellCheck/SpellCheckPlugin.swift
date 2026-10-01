import AppKit
@testable import Pop

/// 插件包「拼写检查」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopSpellCheckEntry)
final class SpellCheckEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [SpellCheckPlugin()]
    }
}

struct SpellCheckPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.spellCheck, name: String(localized: "拼写检查"), symbol: "text.badge.checkmark",
                          summary: String(localized: "找出外文里拼错的词，给出改法，可以直接换成改好的文字（系统自带的拼写检查，离线）"),
                          accepts: [.foreignText], maxLength: 20_000)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text else { return .failure(String(localized: "没有文字")) }
        let issues = SpellCheck.issues(in: text, language: SpellCheck.supportedLanguage(content.language))
        guard !issues.isEmpty else { return .done(toast: String(localized: "没有发现拼写错误")) }
        let rows = issues.map { issue in
            ResultCard.Row(label: issue.word,
                           value: issue.suggestions.isEmpty ? String(localized: "（没有建议）") : issue.suggestions.joined(separator: " / "))
        }
        let corrected = SpellCheck.corrected(text, issues: issues)
        let changed = corrected != text
        return .card(ResultCard(title: String(localized: "拼写检查"), body: changed ? corrected : "",
                                detail: changed ? String(localized: "发现 \(issues.count) 处拼写问题；上面是按第一个建议改好的文字")
                                    : String(localized: "发现 \(issues.count) 处可能拼错的词，没有找到改法"),
                                copyText: changed ? corrected : nil, replaceText: changed ? corrected : nil, rows: rows))
    }
}
