import AppKit
@testable import Pop

/// 插件包「SQL 格式化」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopFormatSQLEntry)
final class FormatSQLEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [FormatSQLPlugin()]
    }

    @MainActor static func didLoad(_ host: PluginHost.Registrar) {
        // CI 截图：写在一行里的查询按子句分行
        host.addDemoScene(PluginHost.DemoScene(name: "sql", after: "photo", order: 1, delay: 1.4, hold: 0, show: { demo in
            let query = "select u.id, u.name, count(o.id) as orders from users u left join orders o on o.user_id = u.id "
                + "where u.created_at >= '2026-01-01' and u.vip = true group by u.id, u.name order by orders desc limit 20"
            guard case .card(let card) = await FormatSQLPlugin().run(ContentClassifier.classify(.text(query)),
                                                                     context: PluginContext(settings: AppSettings(), openSettings: {})) else { return nil }
            demo.overlay.showCard(ResultCardView(card: card, onAction: { _ in }, onMore: {}, onClose: {}), anchor: demo.center)
            return demo.cardRegion
        }))
    }
}

struct FormatSQLPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.formatSQL, name: String(localized: "SQL 格式化"), symbol: "cylinder.split.1x2",
                          summary: String(localized: "把选中的 SQL 按子句分行、关键字大写、子查询缩进，也可以压成一行"), accepts: [.text],
                          maxLength: 500_000, check: .sql)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text else { return .failure(String(localized: "没有选中文字")) }
        let formatted = SQLFormatter.format(text)
        guard !formatted.isEmpty else { return .failure(String(localized: "没有可以格式化的 SQL")) }
        return .card(ResultCard(title: String(localized: "SQL 格式化"), body: formatted, monospaced: true, copyText: formatted, replaceText: formatted,
                                buttons: [CardButton(title: String(localized: "复制成一行"), action: .copy(SQLFormatter.format(text, compact: true)))]))
    }
}
