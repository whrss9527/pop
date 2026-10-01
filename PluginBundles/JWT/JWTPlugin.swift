import AppKit
@testable import Pop

/// 插件包「JWT 解码」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopJWTEntry)
final class JWTEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [JWTPlugin()]
    }
}

struct JWTPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.jwtDecode, name: String(localized: "JWT 解码"), symbol: "key",
                          summary: String(localized: "解码选中的 JWT，列出签发者、过期时间等声明（只解码，不验证签名）"), accepts: [.text],
                          pattern: JWTDecoder.pattern)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text, let token = JWTDecoder.decode(text) else { return .failure(String(localized: "不是有效的 JWT")) }
        return .card(ResultCard(title: "JWT", body: token.payload, detail: String(localized: "只是解码，没有验证签名"), monospaced: true,
                                copyText: token.payload, rows: JWTDecoder.rows(for: token),
                                buttons: [CardButton(title: String(localized: "复制头部"), action: .copy(token.header))]))
    }
}
