import AppKit
@testable import Pop

/// 插件包「Markdown 富文本」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopMarkdownEntry)
final class MarkdownEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [MarkdownPreviewPlugin(), MarkdownCopyPlugin()]
    }
}

struct MarkdownPreviewPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.markdownPreview, name: String(localized: "Markdown 预览"), symbol: "doc.text.magnifyingglass",
                          summary: String(localized: "把选中的 Markdown 显示成排好版的样子（标题、列表、粗体、代码……），可以复制为富文本"),
                          accepts: [.text], pattern: MarkdownRichText.pattern)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text, MarkdownRichText.render(text) != nil else {
            return .failure(String(localized: "没能解析这段 Markdown"))
        }
        return .card(ResultCard(title: String(localized: "Markdown 预览"), markdown: text,
                                buttons: [CardButton(title: String(localized: "复制为富文本"), action: .copyRichText(text))]))
    }
}

struct MarkdownCopyPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.markdownCopy, name: String(localized: "复制为富文本"), symbol: "doc.richtext",
                          summary: String(localized: "把选中的 Markdown 转成带格式的文字复制下来（标题、粗体、列表、链接……），粘贴到文稿、邮件、备忘录里保留格式"),
                          accepts: [.text], pattern: MarkdownRichText.pattern)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text, let rich = MarkdownRichText.render(text) else {
            return .failure(String(localized: "没能转换这段 Markdown"))
        }
        MarkdownRichText.copy(rich)
        return .done(toast: String(localized: "已复制为富文本"))
    }
}
