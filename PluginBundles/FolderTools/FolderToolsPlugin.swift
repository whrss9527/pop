import AppKit
@testable import Pop

/// 插件包「文件夹工具」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopFolderToolsEntry)
final class FolderToolsEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [DiskUsagePlugin(), DuplicatesPlugin(), FolderComparePlugin()]
    }

    @MainActor static func didLoad(_ host: PluginHost.Registrar) {
        // CI 截图：示例文件夹里有两组内容一样的文件
        host.addDemoScene(PluginHost.DemoScene(name: "duplicates", after: "vocabulary", delay: 1.4, hold: 0, show: { demo in
            guard let folder = OverlayDemo.sampleDuplicates() else { return nil }
            let duplicates = DuplicatesModel(roots: [folder])
            duplicates.start()
            demo.overlay.showCard(DuplicatesView(model: duplicates, onReveal: { _ in }, onClose: {}), anchor: demo.center)
            return demo.cardRegion
        }))
        // CI 截图：同一个示例文件夹，看每一项占了多少
        host.addDemoScene(PluginHost.DemoScene(name: "diskUsage", after: "pdfPages", delay: 1.4, hold: 0, show: { demo in
            guard let folder = OverlayDemo.sampleDuplicates() else { return nil }
            let usage = DiskUsageModel(root: folder)
            usage.start()
            demo.overlay.showCard(DiskUsageView(model: usage, onReveal: { _ in }, onClose: {}), anchor: demo.center)
            return demo.cardRegion
        }))
    }
}

struct DiskUsagePlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.diskUsage, name: String(localized: "占用空间"), symbol: "chart.bar.doc.horizontal",
                          summary: String(localized: "看选中的文件夹里哪些东西最占地方：按层级一层层点进去，或者直接列出最大的文件，不要的可以移到废纸篓"),
                          accepts: [.files], check: .folder)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let folder = content.files.first(where: { FolderTree.isFolder($0.path(percentEncoded: false)) }) else {
            return .failure(String(localized: "没有选中文件夹"))
        }
        return .present(PluginPresentation { session in
            // 后台扫描，扫完一层层点进去看，不要的移到废纸篓
            let model = DiskUsageModel(root: folder)
            session.showCard(DiskUsageView(model: model,
                                           onReveal: { urls in NSWorkspace.shared.activateFileViewerSelecting(urls) },
                                           onClose: { session.end() }))
        })
    }
}

struct DuplicatesPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.findDuplicates, name: String(localized: "查找重复文件"), symbol: "doc.on.doc",
                          summary: String(localized: "在选中的文件夹里找出内容完全一样的文件，每组留一个，其余的移到废纸篓"),
                          accepts: [.files], check: .folder)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        let folders = content.files.filter { FolderTree.isFolder($0.path(percentEncoded: false)) }
        guard !folders.isEmpty else { return .failure(String(localized: "没有选中文件夹")) }
        return .present(PluginPresentation { session in
            // 后台扫描，扫完可以每组只留一个
            let model = DuplicatesModel(roots: folders)
            session.showCard(DuplicatesView(model: model,
                                            onReveal: { urls in NSWorkspace.shared.activateFileViewerSelecting(urls) },
                                            onClose: { session.end() }))
        })
    }
}

struct FolderComparePlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.compareFolders, name: String(localized: "比较文件夹"), symbol: "rectangle.split.2x1",
                          summary: String(localized: "比较选中的两个文件夹：哪些文件只在一边有，哪些两边都有但内容不一样"),
                          accepts: [.files], check: .twoFolders)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        let folders = content.files.filter { FolderTree.isFolder($0.path(percentEncoded: false)) }
        guard folders.count == 2 else { return .failure(String(localized: "选中两个文件夹才能比较")) }
        let result = await runInBackground { FolderCompare.compare(folders[0], folders[1]) }
        return .card(FolderCompare.card(result))
    }
}
