import AppKit
@testable import Pop

/// 插件包「XML 格式化」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopFormatXMLEntry)
final class FormatXMLEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [FormatXMLPlugin()]
    }
}

struct FormatXMLPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.formatXML, name: String(localized: "XML 格式化"), symbol: "chevron.left.forwardslash.chevron.right",
                          summary: String(localized: "格式化或压缩选中的 XML（也认 SVG、plist、XHTML）"), accepts: [.text],
                          maxLength: 2_000_000, check: .xml)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text, let pretty = XMLFormatter.prettyPrinted(text) else { return .failure(String(localized: "不是合法的 XML")) }
        var buttons: [CardButton] = []
        if let minified = XMLFormatter.minified(text) {
            buttons.append(CardButton(title: String(localized: "复制压缩版"), action: .copy(minified)))
        }
        return .card(ResultCard(title: String(localized: "XML 格式化"), body: pretty, monospaced: true, copyText: pretty, replaceText: pretty,
                                buttons: buttons))
    }
}
