import AppKit
@testable import Pop

/// 插件包「长按 ⌘Q 退出」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopHoldToQuitEntry)
final class HoldToQuitEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [HoldToQuitPlugin()]
    }

    @MainActor static func didLoad(_ host: PluginHost.Registrar) {
        // 装上就开始拦（关掉过的话照旧关着）
        if !OverlayDemo.isEnabled {
            HoldToQuit.shared.startIfNeeded()
        }
        // CI 截图：卡片（开着，按住 1 秒，「终端」照旧一按就退出）
        host.addDemoScene(PluginHost.DemoScene(name: "holdToQuit", after: "pdfPages", order: 28, delay: 1.4, hold: 0, show: { demo in
            demo.overlay.showCard(HoldToQuitView(model: HoldToQuit.demo(), sourceApp: nil, onOpenPrivacy: {}, onClose: {}), anchor: demo.center)
            return demo.cardRegion
        }))
        // 屏幕中间的提示：按住 ⌘Q 按到一多半
        host.addDemoScene(PluginHost.DemoScene(name: "holdToQuit-prompt", after: "pdfPages", order: 29, delay: 1.4, show: { demo in
            // 提示在屏幕正中：先收起上一步的卡片，不然截出来提示压在卡片上
            demo.overlay.hide(animated: false)
            let model = HoldToQuit.demo()
            HoldToQuitEntry.demoModel = model
            let app = model.exceptionApp("com.apple.Safari")
            let shown = HoldToQuit.FrontApp(pid: 0, bundleID: app.bundleID, name: "Safari", icon: app.icon)
            // 提示外面有一圈留给阴影的空白，截图时去掉一些
            return model.showPromptForDemo(app: shown, progress: 0.65, on: demo.screen).insetBy(dx: 8, dy: 8)
        }, hide: {
            HoldToQuitEntry.demoModel?.hidePromptForDemo()
            HoldToQuitEntry.demoModel = nil
        }))
    }

    /// 演示里屏幕中间的那个提示
    @MainActor private static var demoModel: HoldToQuit?

    @MainActor static func willUninstall() {
        HoldToQuit.shared.shutDown()
    }
}

struct HoldToQuitPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.holdToQuit, name: String(localized: "长按 ⌘Q 退出"), symbol: "command",
                          summary: String(localized: "按住 ⌘Q 一会儿（或者连按两下）才退出 App，误按一下不会关掉整个 App；可以让有的 App 照旧一按就退出"),
                          accepts: [])

    static let privacyURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        let model = HoldToQuit.shared
        let source = context.sourcePID.flatMap { NSRunningApplication(processIdentifier: $0) }.map {
            HoldToQuit.FrontApp(pid: $0.processIdentifier, bundleID: $0.bundleIdentifier,
                                name: $0.localizedName ?? context.sourceAppName ?? "", icon: $0.icon)
        }
        return .present(PluginPresentation { session in
            session.showCard(HoldToQuitView(model: model, sourceApp: source,
                                            onOpenPrivacy: {
                                                if let url = Self.privacyURL {
                                                    session.perform(.open(url))
                                                }
                                            },
                                            onClose: { session.end() }))
        })
    }
}
