import AppKit
@testable import Pop

/// 插件包「退出 App」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopQuitAppsEntry)
final class QuitAppsEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [QuitAppsPlugin()]
    }

    @MainActor static func didLoad(_ host: PluginHost.Registrar) {
        // CI 截图：几个系统自带的 App 和示例的内存占用，退出不会真的退出
        host.addDemoScene(PluginHost.DemoScene(name: "quitApps", after: "textImage", order: 1, delay: 1.4, hold: 0, show: { demo in
            let model = QuitAppsModel(rows: QuitAppsPlugin.demoRows(), front: 1, terminate: { _, _ in true }, isRunning: { _ in true })
            demo.overlay.showCard(QuitAppsView(model: model, onClose: {}), anchor: demo.center)
            return demo.cardRegion
        }))
    }
}

struct QuitAppsPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.quitApps, name: String(localized: "退出 App"), symbol: "xmark.app",
                          summary: String(localized: "列出正在运行的 App 和各占多少内存，一键退出，没有响应的强制退出；也能一下退出其他所有 App，开会、演示前清清场"),
                          accepts: [])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        let own = ProcessInfo.processInfo.processIdentifier
        let apps = NSWorkspace.shared.runningApplications.filter { app in
            app.activationPolicy == .regular && !app.isTerminated && app.processIdentifier != own
                && !RunningApps.hidden.contains(app.bundleIdentifier ?? "")
        }
        let basics = apps.map { app in
            RunningApps.Entry(pid: app.processIdentifier, name: app.localizedName ?? app.bundleIdentifier ?? "\(app.processIdentifier)",
                              bundleID: app.bundleIdentifier, memory: nil)
        }
        // 读内存要一个个问系统，放到后台
        let entries = await runInBackground {
            RunningApps.sorted(basics.map { entry in
                var entry = entry
                entry.memory = RunningApps.memory(of: entry.pid)
                return entry
            })
        }
        let byPID = Dictionary(apps.map { ($0.processIdentifier, $0) }, uniquingKeysWith: { first, _ in first })
        let rows = entries.map { QuitAppsModel.Row(entry: $0, icon: byPID[$0.pid]?.icon) }
        return .present(PluginPresentation { session in
            let model = QuitAppsModel(rows: rows, front: context.sourcePID, terminate: { pid, force in
                guard let app = byPID[pid], !app.isTerminated else { return false }
                return force ? app.forceTerminate() : app.terminate()
            }, isRunning: { pid in
                byPID[pid].map { !$0.isTerminated } ?? false
            })
            session.showCard(QuitAppsView(model: model, onClose: { session.end() }))
        })
    }

    /// 演示用的列表：系统自带的几个 App（图标从系统里取），内存是示例数据
    @MainActor static func demoRows() -> [QuitAppsModel.Row] {
        let samples: [(String, String, UInt64)] = [
            ("com.apple.dt.Xcode", "Xcode", 2_350_000_000),
            ("com.apple.Safari", "Safari 浏览器", 1_240_000_000),
            ("com.apple.Music", "音乐", 412_000_000),
            ("com.apple.mail", "邮件", 286_000_000),
            ("com.apple.Notes", "备忘录", 158_000_000),
            ("com.apple.Preview", "预览", 96_000_000),
        ]
        return samples.enumerated().map { index, sample in
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: sample.0)
            return QuitAppsModel.Row(entry: RunningApps.Entry(pid: pid_t(index + 1), name: sample.1, bundleID: sample.0, memory: sample.2),
                                     icon: url.map { NSWorkspace.shared.icon(forFile: $0.path(percentEncoded: false)) })
        }
    }
}
