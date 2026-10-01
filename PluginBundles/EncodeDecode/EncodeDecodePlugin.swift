import AppKit
@testable import Pop

/// 插件包「编码转换」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopEncodeDecodeEntry)
final class EncodeDecodeEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [EncodeDecodePlugin()]
    }
}

struct EncodeDecodePlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.encodeDecode, name: String(localized: "编码转换"), symbol: "chevron.left.forwardslash.chevron.right",
                          summary: String(localized: "Base64、URL、Unicode、HTML 实体的编码和解码"), accepts: [.text], maxLength: 200_000)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text else { return .failure(String(localized: "没有文字")) }
        let rows = await runInBackground { TextCodec.conversions(text) }
        return .card(ResultCard(title: String(localized: "编码转换"), rows: rows, rowsReplaceable: true))
    }
}
