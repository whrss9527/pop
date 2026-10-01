import AppKit
@testable import Pop

/// 插件包「整理文件夹」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopTidyFolderEntry)
final class TidyFolderEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [TidyFolderPlugin()]
    }

    @MainActor static func didLoad(_ host: PluginHost.Registrar) {
        // CI 截图：一个示例的「下载」文件夹按类型整理（只是预览，不碰真的文件）
        host.addDemoScene(PluginHost.DemoScene(name: "tidyFolder", after: "pdfPages", order: 1, delay: 1.4, hold: 0, show: { demo in
            let folder = FileManager.default.temporaryDirectory.appending(path: "pop-demo/下载", directoryHint: .isDirectory)
            let model = TidyFolderModel(folder: folder, items: TidyFolderPlugin.demoItems(in: folder), mode: .kind)
            demo.overlay.showCard(TidyFolderView(model: model, onReveal: {}, onClose: {}), anchor: demo.center)
            return demo.cardRegion
        }))
    }
}

struct TidyFolderPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.tidyFolder, name: String(localized: "整理文件夹"), symbol: "folder.badge.gearshape",
                          summary: String(localized: "把选中的文件夹（没选时是「下载」）第一层的文件按类型或者按月份归到子文件夹里，先看预览，整理完可以撤销"),
                          accepts: [])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        let folder = Self.folder(for: content.files)
        let loaded: Result<[FolderTidy.Item], FolderTidy.Failure> = await runInBackground {
            do {
                return .success(try FolderTidy.items(in: folder))
            } catch let failure as FolderTidy.Failure {
                return .failure(failure)
            } catch {
                return .failure(FolderTidy.Failure(message: error.localizedDescription))
            }
        }
        switch loaded {
        case .failure(let failure):
            return .failure(failure.message)
        case .success(let items):
            if FolderTidy.plan(items, in: folder, mode: .kind).moves.isEmpty {
                return .done(toast: String(localized: "「\(folder.lastPathComponent)」里没有要整理的文件"))
            }
            return .present(PluginPresentation { session in
                let model = TidyFolderModel(folder: folder, items: items)
                session.showCard(TidyFolderView(model: model, onReveal: {
                    if case .done(let done) = model.phase {
                        NSWorkspace.shared.activateFileViewerSelecting(Array(Set(done.moves.map { $0.to.deletingLastPathComponent() })))
                    } else {
                        NSWorkspace.shared.activateFileViewerSelecting([folder])
                    }
                    session.end()
                }, onClose: { session.end() }))
            })
        }
    }

    /// 整理哪个文件夹：选中了文件夹就是它，选中了文件就是文件所在的文件夹，什么都没选就是「下载」
    static func folder(for files: [URL]) -> URL {
        if let selected = files.first(where: { FolderTree.isFolder($0.path(percentEncoded: false)) }) {
            return selected
        }
        if let file = files.first {
            return file.deletingLastPathComponent()
        }
        return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: "Downloads", directoryHint: .isDirectory)
    }

    /// 演示用的「下载」文件夹里的东西（文件不存在，只用来算预览）
    static func demoItems(in folder: URL) -> [FolderTidy.Item] {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let names = ["发布会.mp4", "海边.heic", "截图 2026-09-30 10.12.03.png", "截图 2026-09-29 18.40.11.png", "季度报告.pdf", "合同.docx",
                     "预算.xlsx", "Pop-0.48.0.zip", "资料.rar", "安装器.dmg", "会议录音.m4a", "播客.mp3", "设计稿.sketch", "笔记.md"]
        var items = names.enumerated().map { index, name in
            FolderTidy.Item(url: folder.appending(path: name), isDirectory: false, added: now.addingTimeInterval(Double(-index) * 86_400 * 6))
        }
        // 子文件夹和没下载完的文件不动
        items.append(FolderTidy.Item(url: folder.appending(path: "项目", directoryHint: .isDirectory), isDirectory: true, added: now))
        items.append(FolderTidy.Item(url: folder.appending(path: "大文件.zip.crdownload"), isDirectory: false, added: now))
        return items
    }
}
