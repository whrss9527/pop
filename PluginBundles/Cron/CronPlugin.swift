import AppKit
@testable import Pop

/// 插件包「Cron 表达式」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopCronEntry)
final class CronEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [CronPlugin()]
    }
}

struct CronPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.cron, name: String(localized: "Cron 表达式"), symbol: "clock.arrow.circlepath",
                          summary: String(localized: "把 cron 表达式（比如 */15 9-17 * * 1-5）说成中文，列出接下来几次运行的时间"),
                          accepts: [.text], maxLength: 120, check: .custom(CustomContentCheck("cron") { CronExpression($0) != nil }))

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text, let cron = CronExpression(text) else { return .failure(String(localized: "不是有效的 cron 表达式")) }
        let calendar = Calendar.current
        let runs = cron.nextRuns(after: Date(), count: 5, calendar: calendar)
        let formatter = DateFormatter()
        formatter.locale = Localization.locale
        formatter.dateFormat = "yyyy-MM-dd HH:mm EEE"
        let rows = runs.enumerated().map { index, date in
            ResultCard.Row(label: String(localized: "第 \(index + 1) 次"), value: formatter.string(from: date))
        }
        return .card(ResultCard(title: String(localized: "Cron 表达式"), body: cron.summary,
                                detail: runs.isEmpty ? String(localized: "五年内都不会运行") : String(localized: "接下来几次（本机时区 \(calendar.timeZone.identifier)）"),
                                copyText: cron.summary, rows: rows))
    }
}
