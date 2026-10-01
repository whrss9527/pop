import AppKit
@testable import Pop

/// 插件包「表格转换」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopTableConvertEntry)
final class TableConvertEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [TableConvertPlugin()]
    }
}

struct TableConvertPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.tableConvert, name: String(localized: "表格转换"), symbol: "tablecells",
                          summary: String(localized: "从表格软件复制的文字、CSV、Markdown 表格互相转换，也能转成 JSON"), accepts: [.text],
                          pattern: #"[\t,|][^\n]*\n[^\n]*[\t,|]"#, maxLength: 500_000)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text else { return .failure(String(localized: "没有文字")) }
        guard let table = await runInBackground({ TableConverter.parse(text) }) else {
            return .failure(String(localized: "这段文字不像表格：需要至少两行两列，并且每行的列数一样。"))
        }
        let columns = table.rows.first?.count ?? 0
        let rows = await runInBackground { TableConverter.conversions(table) }
        return .card(ResultCard(title: String(localized: "表格转换"), detail: String(localized: "\(table.rows.count) 行 × \(columns) 列（第一行当作表头）"),
                                rows: rows, rowsReplaceable: true, rowLineLimit: 3))
    }
}
