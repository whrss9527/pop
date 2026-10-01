import AppKit
@testable import Pop

/// 插件包「文字整理」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopTextCleanupEntry)
final class TextCleanupEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [TextCleanupPlugin()]
    }
}

struct TextCleanupPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.textCleanup, name: String(localized: "文字整理"), symbol: "text.alignleft",
                          summary: String(localized: "合并换行、去掉空行和多余空格、中英文之间加空格、全角转半角、简繁转换、拼音、按行排序去重"),
                          accepts: [.text], pattern: TextCleanup.applicablePattern, maxLength: 100_000)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text else { return .failure(String(localized: "没有文字")) }
        let rows = await runInBackground { TextCleanup.conversions(text) }
        guard !rows.isEmpty else { return .failure(String(localized: "这段文字没有需要整理的地方")) }
        return .card(ResultCard(title: String(localized: "文字整理"), rows: rows, rowsReplaceable: true, rowLineLimit: 2))
    }
}
