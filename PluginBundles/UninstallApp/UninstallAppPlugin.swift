import AppKit
import UniformTypeIdentifiers
@testable import Pop

/// 插件包「卸载 App」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopUninstallAppEntry)
final class UninstallAppEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [UninstallAppPlugin()]
    }

    @MainActor static func didLoad(_ host: PluginHost.Registrar) {
        // CI 截图：一个示例 App 和它留下的文件（路径和大小都是示例，不碰真的文件）
        host.addDemoScene(PluginHost.DemoScene(name: "uninstallApp", after: "pdfPages", order: 2, delay: 1.4, hold: 0, show: { demo in
            let (app, items, sizes) = UninstallAppPlugin.demo()
            let model = UninstallAppModel(app: app, icon: NSWorkspace.shared.icon(for: .applicationBundle), items: items, sizes: sizes,
                                          isRunning: { false }, quit: {}, recycle: { _ in [] })
            demo.overlay.showCard(UninstallAppView(model: model, onReveal: { _ in }, onOpenTrash: {}, onClose: {}), anchor: demo.center)
            return demo.cardRegion
        }))
    }
}

struct UninstallAppPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.uninstallApp, name: String(localized: "卸载 App"), symbol: "trash.square",
                          summary: String(localized: "卸载选中的 App：连同它在「资源库」里留下的设置、缓存、容器一起找出来，看清各占多大，再一起移到废纸篓；只勾留下的文件，就是把 App 恢复成刚装好的样子"),
                          accepts: [.files], check: .custom(CustomContentCheck("appBundle") { subject in
                              subject.split(separator: "\n").contains { $0.hasSuffix(".app") || $0.hasSuffix(".app/") }
                          }))

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let url = content.files.first(where: { $0.pathExtension.lowercased() == "app" }) else {
            return .failure(String(localized: "没有选中 App"))
        }
        let loaded: Result<(AppUninstaller.App, [AppUninstaller.Item]), AppUninstaller.Failure> = await runInBackground {
            do {
                let app = try AppUninstaller.app(at: url)
                return .success((app, AppUninstaller.scan(app)))
            } catch let failure as AppUninstaller.Failure {
                return .failure(failure)
            } catch {
                return .failure(AppUninstaller.Failure(message: error.localizedDescription))
            }
        }
        guard case .success(let (app, items)) = loaded else {
            if case .failure(let failure) = loaded { return .failure(failure.message) }
            return .failure(String(localized: "没有选中 App"))
        }
        if app.isApple {
            return .failure(String(localized: "「\(app.name)」是系统自带的 App，不能卸载"))
        }
        if let own = Bundle.main.bundleIdentifier, app.bundleID == own {
            return .failure(String(localized: "Pop 不能卸载自己：退出 Pop 以后把它拖到废纸篓就行"))
        }
        let instances = { app.bundleID.map { NSRunningApplication.runningApplications(withBundleIdentifier: $0) }?.filter { !$0.isTerminated } ?? [] }
        return .present(PluginPresentation { session in
            let model = UninstallAppModel(app: app, icon: NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false)), items: items,
                                          isRunning: { !instances().isEmpty },
                                          quit: { for instance in instances() { _ = instance.terminate() } },
                                          recycle: { await Self.recycle($0) })
            session.showCard(UninstallAppView(model: model,
                                              onReveal: { NSWorkspace.shared.activateFileViewerSelecting([$0]) },
                                              onOpenTrash: {
                                                  let trash = FileManager.default.urls(for: .trashDirectory, in: .userDomainMask).first
                                                  if let trash { NSWorkspace.shared.open(trash) }
                                                  session.end()
                                              },
                                              onClose: { session.end() }))
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

    /// 演示用：一个示例 App 和它在「资源库」里留下的文件
    static func demo() -> (AppUninstaller.App, [AppUninstaller.Item], [URL: UInt64]) {
        let library = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library", directoryHint: .isDirectory)
        let app = AppUninstaller.App(url: URL(fileURLWithPath: "/Applications/Sketchpad.app", isDirectory: true), name: "Sketchpad",
                                     bundleID: "com.example.sketchpad", version: "3.2.1", executable: "Sketchpad",
                                     relatedIDs: ["com.example.sketchpad", "com.example.sketchpad.share"],
                                     groups: ["ABCDE12345.com.example.sketchpad"], teamID: "ABCDE12345")
        let entries: [(String?, AppUninstaller.Place, AppUninstaller.Doubt?, UInt64)] = [
            (nil, .app, nil, 412_000_000),
            ("Application Support/Sketchpad", .support, nil, 1_280_000_000),
            ("Caches/com.example.sketchpad", .caches, nil, 356_000_000),
            ("Preferences/com.example.sketchpad.plist", .preferences, nil, 12_000),
            ("Containers/com.example.sketchpad.share", .containers, nil, 2_400_000),
            ("Group Containers/ABCDE12345.com.example.sketchpad", .groupContainers, .shared, 48_000_000),
            ("Saved Application State/com.example.sketchpad.savedState", .savedState, nil, 96_000),
            ("HTTPStorages/com.example.sketchpad", .caches, nil, 640_000),
            ("Logs/Sketchpad", .logs, nil, 3_100_000),
        ]
        var items: [AppUninstaller.Item] = []
        var sizes: [URL: UInt64] = [:]
        for (path, place, doubt, size) in entries {
            let url = path.map { library.appending(path: $0) } ?? app.url
            items.append(AppUninstaller.Item(url: url, place: place, doubt: doubt))
            sizes[url] = size
        }
        return (app, items, sizes)
    }
}
