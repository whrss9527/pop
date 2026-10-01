import AppKit
@testable import Pop

/// 插件包「批量重命名」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopBatchRenameEntry)
final class BatchRenameEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [BatchRenamePlugin()]
    }

    @MainActor static func didLoad(_ host: PluginHost.Registrar) {
        // CI 截图：几个示例文件按编号改名的预览
        host.addDemoScene(PluginHost.DemoScene(name: "rename", after: "photo", delay: 1.4, hold: 0, show: { demo in
            let renaming = RenameModel(files: OverlayDemo.sampleFiles())
            renaming.rule.name = "发布素材"
            demo.overlay.showCard(RenameCardView(model: renaming, onReveal: { _ in }, onClose: {}), anchor: demo.center)
            return demo.cardRegion
        }))
    }
}

struct BatchRenamePlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.batchRename, name: String(localized: "批量重命名"), symbol: "rectangle.and.pencil.and.ellipsis",
                          summary: String(localized: "给选中的文件统一改名：编号、替换文字、加前后缀、按照片的拍摄时间、改大小写，先看预览再改，改完可以撤销"),
                          accepts: [.files])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        let files = content.files
        guard !files.isEmpty else { return .failure(String(localized: "没有选中文件")) }
        return .present(PluginPresentation { session in
            // 按规则预览新名字，改完可以撤销
            let model = RenameModel(files: files)
            session.showCard(RenameCardView(model: model,
                                            onReveal: { urls in
                                                NSWorkspace.shared.activateFileViewerSelecting(urls)
                                                session.end()
                                            },
                                            onClose: { session.end() }))
        })
    }
}
