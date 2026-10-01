import Foundation

// MARK: - 日期计算

struct DateSpanPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.dateSpan, name: String(localized: "日期计算"), symbol: "calendar.badge.clock",
                          summary: String(localized: "选中两个日期（比如「2026-09-29 到 2026-12-25」），算出相差多少天、几周、几个月，其中有多少个工作日"),
                          accepts: [.text], maxLength: 80, check: .twoDates)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text, let result = DateSpan.find(in: text) else {
            return .failure(String(localized: "需要两个日期，比如「2026-09-29 到 2026-12-25」"))
        }
        let formatter = DateFormatter()
        formatter.locale = Localization.locale
        formatter.dateFormat = "yyyy-MM-dd EEE"
        return .card(ResultCard(title: String(localized: "日期计算"),
                                detail: String(localized: "从 \(formatter.string(from: result.start)) 到 \(formatter.string(from: result.end))"),
                                rows: DateSpan.rows(for: result)))
    }
}

// MARK: - 目录结构

struct FolderTreePlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.folderTree, name: String(localized: "目录结构"), symbol: "list.bullet.indent",
                          summary: String(localized: "把选中文件夹里的目录结构写成树形或者 Markdown 列表，贴进文档、README 或者发给别人"),
                          accepts: [.files], check: .folder)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let folder = content.files.first(where: { FolderTree.isFolder($0.path(percentEncoded: false)) }) else {
            return .failure(String(localized: "没有选中文件夹"))
        }
        let result = await runInBackground { FolderTree.build(folder) }
        var detail = String(localized: "\(result.folders) 个文件夹，\(result.files) 个文件；最多展开 3 层，隐藏文件不列出")
        if result.truncated {
            detail += String(localized: "，太多了没有全部列出")
        }
        return .card(ResultCard(title: String(localized: "目录结构"), detail: detail, tabs: [
            ResultCard.Tab(title: String(localized: "树形"), text: result.tree),
            ResultCard.Tab(title: String(localized: "Markdown 列表"), text: result.markdown),
        ]))
    }
}

// MARK: - Markdown 目录

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
