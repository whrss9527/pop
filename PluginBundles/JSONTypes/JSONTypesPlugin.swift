import AppKit
@testable import Pop

/// 插件包「JSON 转代码」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopJSONTypesEntry)
final class JSONTypesEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [JSONTypesPlugin()]
    }

    @MainActor static func didLoad(_ host: PluginHost.Registrar) {
        // CI 截图：JSON 转代码卡片（分段切换语言）
        host.addDemoScene(PluginHost.DemoScene(name: "jsonTypes", after: "extract", delay: 1.4, hold: 0, show: { demo in
            let json = #"{"id": 42, "name": "Pop", "tags": ["效率"], "owner": {"login": "pop", "site_url": null}, "#
                + #""releases": [{"version": "0.10.0", "draft": false}, {"version": "0.11.0", "draft": true, "notes": "新功能"}]}"#
            guard let output = JSONTypes.generate(json) else { return nil }
            demo.overlay.showCard(ResultCardView(card: JSONTypesPlugin.card(output), onAction: { _ in }, onMore: {}, onClose: {}),
                                  anchor: demo.center)
            return demo.cardRegion
        }))
    }
}

struct JSONTypesPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.jsonTypes, name: String(localized: "JSON 转代码"), symbol: "curlybraces.square",
                          summary: String(localized: "根据选中的 JSON 生成 TypeScript、Swift、Go、Kotlin 的类型定义"),
                          accepts: [.json], maxLength: JSONTypes.maxLength)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text, let output = await runInBackground({ JSONTypes.generate(text) }) else {
            return .failure(String(localized: "JSON 里没有对象，不用生成类型定义"))
        }
        return .card(Self.card(output))
    }

    /// 每种语言一段，卡片上分段切换
    static func card(_ output: JSONTypes.Output) -> ResultCard {
        let tabs = output.code.map { ResultCard.Tab(title: $0.language.rawValue, text: $0.text) }
        return ResultCard(title: String(localized: "JSON 转代码"), detail: String(localized: "\(output.typeCount) 个类型；字段是否可选、能否为空按示例推断"),
                          tabs: tabs)
    }
}
