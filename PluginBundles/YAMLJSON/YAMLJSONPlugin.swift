import AppKit
@testable import Pop

/// 插件包「YAML 和 JSON」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopYAMLJSONEntry)
final class YAMLJSONEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [YAMLJSONPlugin()]
    }
}

struct YAMLJSONPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.yamlJSON, name: String(localized: "YAML 和 JSON"), symbol: "arrow.left.arrow.right.square",
                          summary: String(localized: "选中 JSON 转成 YAML，选中 YAML 转成 JSON，键的顺序不变"), accepts: [.text],
                          maxLength: 500_000, check: .yamlOrJSON)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text else { return .failure(String(localized: "没有选中文字")) }
        // 几十万字的转换要好一会儿，放在后台
        return await runInBackground { Self.convert(text) }
    }

    /// 在后台转换
    static func convert(_ text: String) -> PluginOutcome {
        if JSONFormatter.isJSON(text) {
            guard let value = OrderedJSON.parse(text) else { return .failure(String(localized: "不是合法的 JSON")) }
            let yaml = YAMLConverter.yaml(from: value)
            return .card(ResultCard(title: String(localized: "JSON 转 YAML"), body: yaml, monospaced: true, copyText: yaml, replaceText: yaml))
        }
        do {
            let value = try YAMLConverter.parse(text)
            let json = OrderedJSON.format(value)
            return .card(ResultCard(title: String(localized: "YAML 转 JSON"), body: json, monospaced: true, copyText: json, replaceText: json,
                                    buttons: [CardButton(title: String(localized: "复制压缩版"), action: .copy(OrderedJSON.compact(value)))]))
        } catch let failure as YAMLConverter.Failure {
            return .failure(String(localized: "读不了这段 YAML：\(failure.description)"))
        } catch {
            return .failure(error.localizedDescription)
        }
    }
}
