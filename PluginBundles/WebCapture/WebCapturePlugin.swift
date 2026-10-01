import AppKit
@testable import Pop

/// 插件包「网页存档」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopWebCaptureEntry)
final class WebCaptureEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [WebCapturePlugin()]
    }
}

struct WebCapturePlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.webCapture, name: String(localized: "网页存档"), symbol: "arrow.down.doc",
                          summary: String(localized: "把选中的网址整页存成一页长 PDF（文字能选、能搜）、一张长图，或者只把正文存成 Markdown，放在「下载」里"),
                          accepts: [.url])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let url = content.url, ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            return .failure(String(localized: "只能存网页（http、https 开头的链接）"))
        }
        return .card(WebCapture.card(url))
    }
}
