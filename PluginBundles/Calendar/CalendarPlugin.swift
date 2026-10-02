import AppKit
@testable import Pop

/// 插件包「日历」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopCalendarEntry)
final class CalendarEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [CalendarPlugin()]
    }

    @MainActor static func didLoad(_ host: PluginHost.Registrar) {
        // CI 截图：2026 年 10 月，今天是国庆节
        host.addDemoScene(PluginHost.DemoScene(name: "calendar", after: "pdfPages", order: 22, delay: 1.4, hold: 0, show: { demo in
            demo.overlay.showCard(CalendarView(model: CalendarPlugin.demoModel(), onClose: {}), anchor: demo.center)
            return demo.cardRegion
        }))
    }
}

struct CalendarPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.calendar, name: String(localized: "万年历"), symbol: "calendar",
                          summary: String(localized: "看一个月的日历，每天写着农历、节气和节日；选中「2026-10-01」「中秋节」「农历八月十五」这样的文字再用，直接翻到那一天，看是星期几、离今天几天"),
                          accepts: [], optionalContent: true)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        let model = CalendarModel(text: content.text)
        return .present(PluginPresentation { session in
            model.onCopy = { session.perform(.copy($0)) }
            session.showCard(CalendarView(model: model, onClose: { session.end() }),
                             keyHandler: { model.handleKey($0) })
        })
    }

    /// 演示用：北京时间 2026 年 10 月 1 日上午，一周从星期一开始，显示农历
    @MainActor static func demoModel() -> CalendarModel {
        CalendarModel(now: Date(timeIntervalSince1970: 1_790_820_000), timeZone: TimeZone(identifier: "Asia/Shanghai") ?? .current,
                      firstWeekday: 2, defaults: nil, showsLunar: true)
    }
}
