import AppKit
@testable import Pop

extension Bundle {
    /// 定时睡眠插件包自己：单独发布的插件包，界面文字查它自己带的翻译（en.lproj、zh-Hans.lproj）
    static let sleepTimer = Bundle(for: SleepTimerEntry.self)
}

/// 插件包「定时睡眠」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopSleepTimerEntry)
final class SleepTimerEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [SleepTimerPlugin()]
    }

    @MainActor static func didLoad(_ host: PluginHost.Registrar) {
        // 上次调小了的音量调回去；还没到点的接着等
        if !OverlayDemo.isEnabled {
            SleepTimer.shared.startIfNeeded()
        }
        // CI 截图：还剩 28 分钟 41 秒睡眠
        host.addDemoScene(PluginHost.DemoScene(name: "sleepTimer", after: "pdfPages", order: 49, delay: 1.4, hold: 0, show: { demo in
            demo.overlay.showCard(SleepTimerView(model: SleepTimer.demo(remaining: 28 * 60 + 41), onClose: {}), anchor: demo.center)
            return demo.cardRegion
        }))
        // 还没定：选了睡眠，上次选的是 30 分钟
        host.addDemoScene(PluginHost.DemoScene(name: "sleepTimer-setup", after: "pdfPages", order: 49, delay: 1.4, hold: 0, show: { demo in
            demo.overlay.showCard(SleepTimerView(model: SleepTimer.demo(remaining: nil), onClose: {}), anchor: demo.center)
            return demo.cardRegion
        }))
        // 最后一分钟屏幕上方的提示
        host.addDemoScene(PluginHost.DemoScene(name: "sleepTimer-banner", after: "pdfPages", order: 49, delay: 1.4, show: { demo in
            let model = SleepTimer.demo(remaining: 42)
            SleepTimerEntry.demoModel = model
            return model.showBannerForDemo(on: demo.screen).insetBy(dx: 8, dy: 8)
        }, hide: {
            SleepTimerEntry.demoModel?.hideBannerForDemo()
            SleepTimerEntry.demoModel = nil
        }))
    }

    /// 演示里屏幕上方的那个提示
    @MainActor private static var demoModel: SleepTimer?

    @MainActor static func willUninstall() {
        SleepTimer.shared.shutDown()
    }
}

struct SleepTimerPlugin: PopPlugin {
    /// 功能 ID：单独发布的插件包用自己的常量，不写进 Pop 的 BuiltinPluginID
    static let id = "sleepTimer"

    let info = PluginInfo(id: Self.id, name: String(localized: "定时睡眠", bundle: .sleepTimer), symbol: "moon.zzz",
                          summary: String(localized: "过一会儿（15 分钟到 2 小时）或者到几点让 Mac 睡眠、熄屏、锁屏或者关机；最后一分钟在屏幕上方提示，可以推迟、取消，睡眠、关机前慢慢把音量调小", bundle: .sleepTimer),
                          accepts: [])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        let model = SleepTimer.shared
        model.cardAppeared()
        return .present(PluginPresentation { session in
            session.showCard(SleepTimerView(model: model, onClose: { session.end() }))
        })
    }
}

// MARK: - 演示

extension SleepTimer {
    /// 演示用：晚上 11 点（系统的时区）；remaining 是离睡眠还有几秒，nil 是还没定
    static func demo(remaining: TimeInterval?) -> SleepTimer {
        let suite = "PopSleepTimerDemo"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        let now = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 10, day: 9, hour: 23, minute: 1, second: 19)) ?? Date()
        let environment = Environment(perform: { _ in nil }, checkPermission: { nil }, volume: { 0.6 }, setVolume: { _ in }, notify: { _, _ in },
                                      now: { now }, calendar: Calendar(identifier: .gregorian))
        let model = SleepTimer(defaults: defaults, environment: environment, isLive: false)
        if let remaining {
            model.setDemoState(pending: Pending(deadline: now.addingTimeInterval(remaining), action: .sleep), warning: remaining <= warningSeconds)
        }
        return model
    }
}
