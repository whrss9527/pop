import AppKit
@testable import Pop

/// 插件包「提取信息」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopExtractInfoEntry)
final class ExtractInfoEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [ExtractInfoPlugin()]
    }
}

struct ExtractInfoPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.extractInfo, name: String(localized: "提取信息"), symbol: "text.magnifyingglass",
                          summary: String(localized: "从一段文字里找出链接、邮箱、电话号码和 IP 地址，逐个复制或者一起复制"),
                          accepts: [.text], maxLength: InfoExtractor.maxLength, check: .extractable)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text else { return .failure(String(localized: "没有文字")) }
        let items = await runInBackground { InfoExtractor.extract(text) }
        guard !items.isEmpty else { return .failure(String(localized: "没有找到链接、邮箱、电话号码或 IP 地址")) }
        return .card(InfoExtractor.card(for: items))
    }
}
