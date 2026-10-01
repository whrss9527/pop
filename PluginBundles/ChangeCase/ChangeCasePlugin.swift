import AppKit
@testable import Pop

/// 插件包「大小写」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopChangeCaseEntry)
final class ChangeCaseEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [ChangeCasePlugin()]
    }
}

struct ChangeCasePlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.changeCase, name: String(localized: "大小写"), symbol: "textformat",
                          summary: String(localized: "大写、小写、驼峰、下划线等写法互相转换"), accepts: [.text],
                          pattern: "[A-Za-z]", maxLength: 20_000)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text else { return .failure(String(localized: "没有文字")) }
        let rows = CaseConverter.conversions(text)
        guard !rows.isEmpty else { return .failure(String(localized: "没有可以转换的字母")) }
        return .card(ResultCard(title: String(localized: "大小写转换"), rows: rows, rowsReplaceable: true))
    }
}
