import AppKit
import UniformTypeIdentifiers
@testable import Pop

/// 插件包「App 信息」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopAppInfoEntry)
final class AppInfoEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [AppInfoPlugin()]
    }

    @MainActor static func didLoad(_ host: PluginHost.Registrar) {
        // CI 截图：一个示例 App 的信息（不读真的 App）
        host.addDemoScene(PluginHost.DemoScene(name: "appInfo", after: "pdfPages", order: 5, delay: 1.4, hold: 0, show: { demo in
            let model = AppInfoModel(report: AppInfoPlugin.demoReport(), icon: NSWorkspace.shared.icon(for: .applicationBundle), size: 412_000_000)
            demo.overlay.showCard(AppInfoView(model: model, onCopy: {}, onReveal: {}, onClose: {}), anchor: demo.center)
            return demo.cardRegion
        }))
    }
}

struct AppInfoPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.appInfo, name: String(localized: "App 信息"), symbol: "info.square",
                          summary: String(localized: "看选中的 App 是给哪种芯片做的、谁签的名、有没有公证、在不在沙盒里、会要哪些权限、用什么做的、从哪下载的，可以复制下来"),
                          accepts: [.files], check: .custom(CustomContentCheck("appInfoBundle") { subject in
                              subject.split(separator: "\n").contains { $0.hasSuffix(".app") || $0.hasSuffix(".app/") }
                          }))

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let url = content.files.first(where: { $0.pathExtension.lowercased() == "app" }) else {
            return .failure(String(localized: "没有选中 App"))
        }
        let inspected: Result<AppInspector.Report, AppInspector.Failure> = await runInBackground {
            do {
                return .success(try AppInspector.inspect(url))
            } catch let failure as AppInspector.Failure {
                return .failure(failure)
            } catch {
                return .failure(AppInspector.Failure(message: error.localizedDescription))
            }
        }
        switch inspected {
        case .failure(let failure):
            return .failure(failure.message)
        case .success(let report):
            return .present(PluginPresentation { session in
                let model = AppInfoModel(report: report, icon: NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false)))
                session.showCard(AppInfoView(model: model, onCopy: {
                    session.perform(.copy(model.text))
                }, onReveal: {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                    session.end()
                }, onClose: { session.end() }))
                model.measure()
            })
        }
    }

    /// 演示用：一个用 Electron 做的、从网上下载的示例 App
    static func demoReport() -> AppInspector.Report {
        AppInspector.Report(url: URL(fileURLWithPath: "/Applications/Sketchpad.app", isDirectory: true), name: "Sketchpad",
                            bundleID: "com.example.sketchpad", version: "3.2.1（321）", architecture: .universal, minimumSystem: "macOS 12.0",
                            signature: .developerID("Example Studio"), teamID: "ABCDE12345", notarized: true, sandboxed: false, hardenedRuntime: true,
                            technologies: ["Electron", String(localized: "Sparkle 自动更新")],
                            permissions: [AppInspector.Permission(name: String(localized: "摄像头"), reason: "Sketchpad uses the camera to scan sketches."),
                                          AppInspector.Permission(name: String(localized: "麦克风"), reason: "Record voice notes."),
                                          AppInspector.Permission(name: String(localized: "下载文件夹"), reason: "Export drawings.")],
                            urlSchemes: ["sketchpad://"], fromAppStore: false, downloadedBy: "Safari")
    }
}
