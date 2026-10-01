import AppKit
@testable import Pop

/// 插件包「数字转换」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopNumberConvertEntry)
final class NumberConvertEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [NumberConvertPlugin()]
    }
}

struct NumberConvertPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.numberConvert, name: String(localized: "数字转换"), symbol: "number.circle",
                          summary: String(localized: "进制转换、千分位、人民币大写"), accepts: [.number])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text, let number = NumberConverter.parse(text) else {
            return .failure(String(localized: "不是有效的数字"))
        }
        return .card(ResultCard(title: String(localized: "数字转换"), rows: NumberConverter.rows(for: number), rowsReplaceable: true))
    }
}
