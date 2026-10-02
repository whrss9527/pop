import AppKit
@testable import Pop

/// 插件包「鼠标滚轮」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopMouseWheelEntry)
final class MouseWheelEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [MouseWheelPlugin()]
    }

    @MainActor static func didLoad(_ host: PluginHost.Registrar) {
        // 设过的话，Pop 一启动就接着生效
        if !OverlayDemo.isEnabled {
            MouseWheel.shared.startIfNeeded()
        }
        // CI 截图：上下反过来、两倍速（不拦 CI 机器的滚动事件）
        host.addDemoScene(PluginHost.DemoScene(name: "mouseWheel", after: "pdfPages", order: 27, delay: 1.4, hold: 0, show: { demo in
            demo.overlay.showCard(MouseWheelView(model: MouseWheel.demo(), onOpenPrivacy: {}, onClose: {}), anchor: demo.center)
            return demo.cardRegion
        }))
    }

    @MainActor static func willUninstall() {
        MouseWheel.shared.shutDown()
    }
}

struct MouseWheelPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.mouseWheel, name: String(localized: "鼠标滚轮"), symbol: "computermouse",
                          summary: String(localized: "把鼠标滚轮的方向反过来（触控板还是自然滚动），也可以让它滚得快一点；只改滚轮鼠标，触控板、妙控鼠标照旧"),
                          accepts: [])

    static let privacyURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        let model = MouseWheel.shared
        return .present(PluginPresentation { session in
            session.showCard(MouseWheelView(model: model,
                                            onOpenPrivacy: {
                                                if let url = Self.privacyURL {
                                                    session.perform(.open(url))
                                                }
                                            },
                                            onClose: { session.end() }))
        })
    }
}
