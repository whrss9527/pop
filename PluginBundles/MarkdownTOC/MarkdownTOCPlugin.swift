import AppKit
@testable import Pop

/// 插件包「Markdown 目录」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopMarkdownTOCEntry)
final class MarkdownTOCEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [MarkdownTOCPlugin()]
    }
}

struct MarkdownTOCPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.markdownTOC, name: String(localized: "Markdown 目录"), symbol: "list.bullet.rectangle",
                          summary: String(localized: "按选中的 Markdown 里的标题生成目录，点链接能跳到对应的标题（锚点和 GitHub 的写法一样）"),
                          accepts: [.text], maxLength: 500_000, check: .markdownHeadings)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text else { return .failure(String(localized: "没有选中文字")) }
        let headings = MarkdownTOC.headings(in: text)
        guard !headings.isEmpty else { return .failure(String(localized: "没有找到 # 开头的标题")) }
        let toc = MarkdownTOC.toc(for: headings)
        return .card(ResultCard(title: String(localized: "Markdown 目录"), body: toc, detail: String(localized: "\(headings.count) 个标题"), monospaced: true, copyText: toc))
    }
}
