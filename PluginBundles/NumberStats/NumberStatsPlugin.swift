import AppKit
@testable import Pop

/// 插件包「数字统计」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopNumberStatsEntry)
final class NumberStatsEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [NumberStatsPlugin()]
    }
}

struct NumberStatsPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.numberStats, name: String(localized: "数字统计"), symbol: "sum",
                          summary: String(localized: "选中一列或一串数字，算出合计、平均、中位数、最大、最小"), accepts: [.text],
                          maxLength: 100_000, check: .custom(CustomContentCheck("numberList") { NumberStats.parse($0) != nil }))

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text, let summary = await runInBackground({ NumberStats.parse(text) }) else {
            return .failure(String(localized: "需要至少两个数：一列（每行一个，前面可以有文字），或者一行用逗号、空格隔开"))
        }
        return .card(ResultCard(title: String(localized: "数字统计"), detail: String(localized: "共 \(summary.count) 个数"), rows: summary.rows))
    }
}
