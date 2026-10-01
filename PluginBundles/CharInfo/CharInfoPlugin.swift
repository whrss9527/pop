import AppKit
@testable import Pop

/// 插件包「字符信息」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopCharInfoEntry)
final class CharInfoEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [CharInfoPlugin()]
    }
}

struct CharInfoPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.charInfo, name: String(localized: "字符信息"), symbol: "character.magnify",
                          summary: String(localized: "查看每个字符的 Unicode 码点、名称和编码；找出并去掉零宽空格这类看不见的字符"),
                          accepts: [.text], maxLength: 100_000, check: .characters)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text else { return .failure(String(localized: "没有文字")) }
        return .card(await runInBackground { CharacterInspector.card(for: text) })
    }
}
