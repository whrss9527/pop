import Foundation

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
