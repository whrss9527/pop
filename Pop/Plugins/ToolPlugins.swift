import Foundation

// MARK: - 日期计算

struct DateSpanPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.dateSpan, name: "日期计算", symbol: "calendar.badge.clock",
                          summary: "选中两个日期（比如「2026-09-29 到 2026-12-25」），算出相差多少天、几周、几个月，其中有多少个工作日",
                          accepts: [.text], maxLength: 80, check: .twoDates)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text, let result = DateSpan.find(in: text) else {
            return .failure("需要两个日期，比如「2026-09-29 到 2026-12-25」")
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd EEE"
        return .card(ResultCard(title: "日期计算",
                                detail: "从 \(formatter.string(from: result.start)) 到 \(formatter.string(from: result.end))",
                                rows: DateSpan.rows(for: result)))
    }
}

// MARK: - 目录结构

struct FolderTreePlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.folderTree, name: "目录结构", symbol: "list.bullet.indent",
                          summary: "把选中文件夹里的目录结构写成树形或者 Markdown 列表，贴进文档、README 或者发给别人",
                          accepts: [.files], check: .folder)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let folder = content.files.first(where: { FolderTree.isFolder($0.path(percentEncoded: false)) }) else {
            return .failure("没有选中文件夹")
        }
        let result = await runInBackground { FolderTree.build(folder) }
        var detail = "\(result.folders) 个文件夹，\(result.files) 个文件；最多展开 3 层，隐藏文件不列出"
        if result.truncated {
            detail += "，太多了没有全部列出"
        }
        return .card(ResultCard(title: "目录结构", detail: detail, tabs: [
            ResultCard.Tab(title: "树形", text: result.tree),
            ResultCard.Tab(title: "Markdown 列表", text: result.markdown),
        ]))
    }
}

// MARK: - Markdown 目录

struct MarkdownTOCPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.markdownTOC, name: "Markdown 目录", symbol: "list.bullet.rectangle",
                          summary: "按选中的 Markdown 里的标题生成目录，点链接能跳到对应的标题（锚点和 GitHub 的写法一样）",
                          accepts: [.text], maxLength: 500_000, check: .markdownHeadings)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text else { return .failure("没有选中文字") }
        let headings = MarkdownTOC.headings(in: text)
        guard !headings.isEmpty else { return .failure("没有找到 # 开头的标题") }
        let toc = MarkdownTOC.toc(for: headings)
        return .card(ResultCard(title: "Markdown 目录", body: toc, detail: "\(headings.count) 个标题", monospaced: true, copyText: toc))
    }
}

// MARK: - 查找重复文件

struct DuplicatesPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.findDuplicates, name: "查找重复文件", symbol: "doc.on.doc",
                          summary: "在选中的文件夹里找出内容完全一样的文件，每组留一个，其余的移到废纸篓",
                          accepts: [.files], check: .folder)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        let folders = content.files.filter { FolderTree.isFolder($0.path(percentEncoded: false)) }
        guard !folders.isEmpty else { return .failure("没有选中文件夹") }
        return .findDuplicates(folders)
    }
}
