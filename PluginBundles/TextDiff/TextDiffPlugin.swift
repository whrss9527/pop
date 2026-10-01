import AppKit
@testable import Pop

/// 插件包「文本对比」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopTextDiffEntry)
final class TextDiffEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [TextDiffPlugin()]
    }
}

struct TextDiffPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.textDiff, name: String(localized: "文本对比"), symbol: "arrow.left.arrow.right.square",
                          summary: String(localized: "把选中的文字和剪贴板里的文字对比，标出删去和新增的地方"), accepts: [.text],
                          maxLength: Self.maxLength)
    static let maxLength = 300_000
    /// 剪贴板里的文字（测试时换掉）
    var clipboardText: @MainActor () -> String? = { NSPasteboard.general.string(forType: .string) }

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text else { return .failure(String(localized: "没有文字")) }
        // 选中的文字去掉了首尾的空白，剪贴板里的也一样处理，免得只差一个换行
        let copied = clipboardText()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !copied.isEmpty else {
            return .failure(String(localized: "剪贴板里没有文字。先复制一段文字，再选中另一段，用「文本对比」看两段有什么不同。"))
        }
        guard copied.count <= Self.maxLength else { return .failure(String(localized: "剪贴板里的文字太长了")) }
        let result = await runInBackground { TextDiff.compare(copied, text) }
        if result.isIdentical {
            return .done(toast: String(localized: "两段文字完全相同"))
        }
        return .card(ResultCard(title: String(localized: "文本对比"),
                                detail: String(localized: "剪贴板 → 选中的文字：删去 \(result.removedCount) 行，新增 \(result.addedCount) 行。红色是只在剪贴板里有的，绿色是只在选中的文字里有的。"),
                                copyText: result.unifiedText, diff: result))
    }
}
