import AppKit
@testable import Pop

/// 插件包「按行处理」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopLineToolsEntry)
final class LineToolsEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [LineToolsPlugin()]
    }
}

struct LineToolsPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.lineTools, name: String(localized: "按行处理"), symbol: "list.bullet.rectangle",
                          summary: String(localized: "一列文字加引号和逗号（SQL 的 IN 列表）、转 JSON 数组、加减序号、倒序、打乱；一行用逗号隔开的拆成多行"),
                          accepts: [.text], maxLength: 500_000, check: .lineList)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text, let items = LineTools.items(text) else {
            return .failure(String(localized: "需要至少两项：一行一项，或者一行里用逗号隔开"))
        }
        let rows = await runInBackground { LineTools.conversions(text) }
        guard !rows.isEmpty else { return .failure(String(localized: "这些内容没有可以转换的写法")) }
        return .card(ResultCard(title: String(localized: "按行处理"), detail: String(localized: "共 \(items.values.count) 项"), rows: rows,
                                rowsReplaceable: true, rowLineLimit: 2))
    }
}
