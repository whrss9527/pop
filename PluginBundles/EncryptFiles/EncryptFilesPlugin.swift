import AppKit
@testable import Pop

/// 插件包「加密打包」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopEncryptFilesEntry)
final class EncryptFilesEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [EncryptFilesPlugin()]
    }

    @MainActor static func didLoad(_ host: PluginHost.Registrar) {
        // CI 截图：填好名字和密码的样子（不真的做映像）
        host.addDemoScene(PluginHost.DemoScene(name: "encryptFiles", after: "pdfPages", order: 10, delay: 1.4, hold: 0, show: { demo in
            let folder = URL(fileURLWithPath: "/Users/Shared/合同扫描件", isDirectory: true)
            let model = EncryptFilesModel(items: [folder], size: 18_400_000, recycle: { _ in [] })
            model.password = "pop-2026"
            model.confirm = "pop-2026"
            demo.overlay.showCard(EncryptFilesView(model: model, onReveal: { _ in }, onClose: {}), anchor: demo.center)
            return demo.cardRegion
        }))
    }
}

struct EncryptFilesPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.encryptFiles, name: String(localized: "加密打包"), symbol: "lock.doc",
                          summary: String(localized: "把选中的文件和文件夹放进一个用密码加密（AES-256）的磁盘映像，在任何一台 Mac 上双击、输入密码就能打开；发给别人、存到 U 盘或者网盘前用"),
                          accepts: [.files])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        let items = content.files
        guard !items.isEmpty else {
            return .failure(String(localized: "没有选中文件"))
        }
        return .present(PluginPresentation { session in
            let model = EncryptFilesModel(items: items, recycle: { await Self.recycle($0) })
            session.showCard(EncryptFilesView(model: model, onReveal: { url in
                NSWorkspace.shared.activateFileViewerSelecting([url])
                session.end()
            }, onClose: { session.end() }))
            model.measure()
        })
    }

    /// 移到废纸篓（和在访达里删除一样，可以「放回原处」），返回移走了的
    @MainActor static func recycle(_ urls: [URL]) async -> [URL] {
        await withCheckedContinuation { continuation in
            NSWorkspace.shared.recycle(urls) { trashed, _ in
                continuation.resume(returning: Array(trashed.keys))
            }
        }
    }
}
