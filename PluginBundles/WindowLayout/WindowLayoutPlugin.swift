import AppKit
@testable import Pop

/// 插件包「窗口布局」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopWindowLayoutEntry)
final class WindowLayoutEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [WindowLayoutPlugin()]
    }

    @MainActor static func didLoad(_ host: PluginHost.Registrar) {
        // CI 截图：窗口布局卡片
        host.addDemoScene(PluginHost.DemoScene(name: "layout", after: "ai", delay: 1.4, hold: 0, show: { demo in
            demo.overlay.showCard(WindowLayoutCardView(hasMultipleDisplays: false, onChoose: { _ in }, onClose: {}), anchor: demo.center)
            return demo.cardRegion
        }))
    }
}

struct WindowLayoutPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.windowLayout, name: String(localized: "窗口布局"), symbol: "rectangle.split.2x1",
                          summary: String(localized: "把当前窗口放到屏幕的左半边、右半边、三分之一、最大化、居中，或者移到另一个显示器"), accepts: [])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        let pid = context.sourcePID
        return .present(PluginPresentation { session in
            // 选一个位置，把唤起时前台 App 的窗口放过去
            let choose: (WindowLayout) -> Void = { layout in
                Self.arrange(layout, pid: pid, session: session)
            }
            session.showCard(WindowLayoutCardView(hasMultipleDisplays: NSScreen.screens.count > 1, onChoose: choose,
                                                  onClose: { session.end() }),
                             keyHandler: { event in
                                 guard let layout = WindowLayoutCardView.layout(for: event) else { return false }
                                 choose(layout)
                                 return true
                             })
        })
    }

    /// 先收起浮窗再挪窗口；挪不了时在唤起的位置说一声
    @MainActor static func arrange(_ layout: WindowLayout, pid: pid_t?, session: PluginSession) {
        guard session.isCurrent else { return }
        session.end()
        guard let pid else { return }
        Task { @MainActor in
            if let problem = await WindowMover.apply(layout, pid: pid) {
                session.finish(toast: problem)
            }
        }
    }
}
