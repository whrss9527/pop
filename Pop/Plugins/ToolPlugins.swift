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

// MARK: - 占用空间

struct DiskUsagePlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.diskUsage, name: "占用空间", symbol: "chart.bar.doc.horizontal",
                          summary: "看选中的文件夹里哪些东西最占地方：按层级一层层点进去，或者直接列出最大的文件，不要的可以移到废纸篓",
                          accepts: [.files], check: .folder)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let folder = content.files.first(where: { FolderTree.isFolder($0.path(percentEncoded: false)) }) else {
            return .failure("没有选中文件夹")
        }
        return .diskUsage(folder)
    }
}

// MARK: - 代码行数

struct CodeStatsPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.codeStats, name: "代码行数", symbol: "chevron.left.forwardslash.chevron.right",
                          summary: "按语言统计选中的文件夹里有多少个代码文件、多少行，可以复制成 Markdown 表格",
                          accepts: [.files], check: .folder)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        let folders = content.files.filter { FolderTree.isFolder($0.path(percentEncoded: false)) }
        guard !folders.isEmpty else { return .failure("没有选中文件夹") }
        let result = await runInBackground { CodeStats.scan(folders) }
        guard !result.languages.isEmpty else { return .failure("选中的文件夹里没有认得出的代码文件") }
        var detail = "\(result.files.formatted()) 个文件，\(result.lines.formatted()) 行（空行 \(result.blank.formatted()) 行）；"
            + "不算隐藏文件夹和 node_modules 这类依赖"
        if result.skipped > 0 {
            detail += "，跳过 \(result.skipped) 个太大或不是文字的文件"
        }
        if result.truncated {
            detail += "，只数了前 \(CodeStats.fileLimit.formatted()) 个"
        }
        let rows = result.languages.map { language in
            ResultCard.Row(label: language.name, value: "\(language.lines.formatted()) 行，\(language.files.formatted()) 个文件")
        }
        return .card(ResultCard(title: "代码行数", detail: detail, copyText: CodeStats.markdown(result), rows: rows))
    }
}

// MARK: - 比较文件夹

struct FolderComparePlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.compareFolders, name: "比较文件夹", symbol: "rectangle.split.2x1",
                          summary: "比较选中的两个文件夹：哪些文件只在一边有，哪些两边都有但内容不一样",
                          accepts: [.files], check: .twoFolders)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        let folders = content.files.filter { FolderTree.isFolder($0.path(percentEncoded: false)) }
        guard folders.count == 2 else { return .failure("选中两个文件夹才能比较") }
        let result = await runInBackground { FolderCompare.compare(folders[0], folders[1]) }
        return .card(FolderCompare.card(result))
    }
}
