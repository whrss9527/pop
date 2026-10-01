import AppKit
@testable import Pop

/// 插件包「突出显示指针」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopPointerHighlightEntry)
final class PointerHighlightEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [PointerHighlightPlugin()]
    }

    @MainActor static func didLoad(_ host: PluginHost.Registrar) {
        // CI 截图：光圈停在屏幕中间，泛起一圈波纹
        host.addDemoScene(PluginHost.DemoScene(name: "pointerHighlight", after: "scrollCapture", order: 3, show: { demo in
            let screen = demo.screen
            let visible = screen.visibleFrame
            let point = CGPoint(x: visible.midX.rounded(), y: visible.midY.rounded())
            PointerHighlight.shared.showForDemo(at: point)
            return PointerHighlight.frame(around: point).insetBy(dx: -40, dy: -40)
        }, hide: {
            PointerHighlight.shared.stop()
        }))
    }

    @MainActor static func willUninstall() {
        PointerHighlight.shared.stop()
    }
}

struct PointerHighlightPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.pointerHighlight, name: String(localized: "突出显示指针"), symbol: "cursorarrow.rays",
                          summary: String(localized: "演示、录教程时在指针周围加一圈黄色光圈，按下鼠标时泛起波纹，让人一眼看到指针在哪；再用一次关闭"),
                          accepts: [])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        let highlight = PointerHighlight.shared
        if highlight.isActive {
            highlight.stop()
            return .done(toast: String(localized: "不再突出显示指针"))
        }
        highlight.start()
        return .done(toast: String(localized: "指针周围加上了光圈，再用一次就关闭"))
    }
}
