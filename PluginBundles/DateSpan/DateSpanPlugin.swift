import AppKit
@testable import Pop

/// 插件包「日期计算」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopDateSpanEntry)
final class DateSpanEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [DateSpanPlugin()]
    }
}

struct DateSpanPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.dateSpan, name: String(localized: "日期计算"), symbol: "calendar.badge.clock",
                          summary: String(localized: "选中两个日期（比如「2026-09-29 到 2026-12-25」），算出相差多少天、几周、几个月，其中有多少个工作日"),
                          accepts: [.text], maxLength: 80, check: .twoDates)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text, let result = DateSpan.find(in: text) else {
            return .failure(String(localized: "需要两个日期，比如「2026-09-29 到 2026-12-25」"))
        }
        let formatter = DateFormatter()
        formatter.locale = Localization.locale
        formatter.dateFormat = "yyyy-MM-dd EEE"
        return .card(ResultCard(title: String(localized: "日期计算"),
                                detail: String(localized: "从 \(formatter.string(from: result.start)) 到 \(formatter.string(from: result.end))"),
                                rows: DateSpan.rows(for: result)))
    }
}
