import AppKit
@testable import Pop

/// 插件包「转成 Markdown」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopToMarkdownEntry)
final class ToMarkdownEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [ToMarkdownPlugin()]
    }
}

struct ToMarkdownPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.toMarkdown, name: String(localized: "转成 Markdown"), symbol: "doc.plaintext",
                          summary: String(localized: "把网页、文档里选中的带格式文字转成 Markdown：标题、列表、链接、粗体、代码、表格"),
                          accepts: [.text], hidesOverlay: true)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        // 读选中内容时拿到的只是纯文字，这里带着格式重新拷贝一次（先收起浮窗，⌘C 才会发给原来的 App）
        guard let selection = await context.readRichSelection?() else {
            return .failure(String(localized: "没能拷贝选中的内容，确认文字还选着再试一次"))
        }
        guard let markdown = await runInBackground({ HTMLToMarkdown.convert(selection) }) else {
            return .failure(String(localized: "选中的内容没有带格式（标题、列表、链接这些），不用转换"))
        }
        return .card(ResultCard(title: String(localized: "转成 Markdown"), body: markdown, monospaced: true, copyText: markdown,
                                buttons: [CardButton(title: String(localized: "贴到屏幕"), action: .pinText(markdown))]))
    }
}
