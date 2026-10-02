import AppKit
@testable import Pop

/// 插件包「休息提醒」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopBreakReminderEntry)
final class BreakReminderEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [BreakReminderPlugin()]
    }

    @MainActor static func didLoad(_ host: PluginHost.Registrar) {
        // 开着的话，Pop 一启动就接着计时
        if !OverlayDemo.isEnabled {
            BreakReminder.shared.startIfEnabled()
        }
        // 上方的提醒、休息时盖住屏幕的那层：Pop 录屏时不录进去
        host.excludeFromRecording {
            BreakReminder.shared.windowNumbers
        }
        // CI 截图：开着，已经连续用了 32 分钟
        host.addDemoScene(PluginHost.DemoScene(name: "breakReminder", after: "pdfPages", order: 23, delay: 1.4, hold: 0, show: { demo in
            demo.overlay.showCard(BreakReminderView(model: BreakReminder.demo(), onClose: {}), anchor: demo.center)
            return demo.cardRegion
        }))
        // 屏幕上方的提醒：已经连续用了 47 分钟
        host.addDemoScene(PluginHost.DemoScene(name: "breakReminder-banner", after: "pdfPages", order: 24, delay: 1.4, show: { demo in
            let banner = BreakReminder.demo(phase: .reminder)
            BreakReminderEntry.demoBanner = banner
            // 提醒外面有一圈留给阴影的空白，截图时去掉一些
            return banner.showBannerForDemo(on: demo.screen).insetBy(dx: 8, dy: 8)
        }, hide: {
            BreakReminderEntry.demoBanner?.hideBannerForDemo()
            BreakReminderEntry.demoBanner = nil
        }))
    }

    /// 演示里屏幕上方的那个提醒
    @MainActor private static var demoBanner: BreakReminder?

    @MainActor static func willUninstall() {
        BreakReminder.shared.shutDown()
    }
}

struct BreakReminderPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.breakReminder, name: String(localized: "休息提醒"), symbol: "figure.walk",
                          summary: String(localized: "连续用电脑一段时间（比如 45 分钟）提醒你起来活动、看看远处；离开电脑一会儿就算休息过了，看视频、开会时不打扰。休息时可以盖住屏幕倒计时"),
                          accepts: [])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        let model = BreakReminder.shared
        return .present(PluginPresentation { session in
            session.showCard(BreakReminderView(model: model, onClose: { session.end() }))
        })
    }
}
