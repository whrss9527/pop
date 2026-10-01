import AppKit
@testable import Pop

/// 插件包「对比度」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopContrastEntry)
final class ContrastEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [ContrastPlugin()]
    }
}

struct ContrastPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.contrast, name: String(localized: "对比度"), symbol: "circle.lefthalf.filled",
                          summary: String(localized: "选中两个颜色（比如「#333333 #FFFFFF」），算出文字和背景的对比度，看是否达到 WCAG 的 AA、AAA"),
                          accepts: [.text], maxLength: 200, check: .colorPair)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text, let pair = ColorContrast.pair(in: text) else {
            return .failure(String(localized: "需要两个颜色值，比如「#333333 #FFFFFF」"))
        }
        return .card(ResultCard(title: String(localized: "对比度"),
                                detail: String(localized: "前一个当文字颜色，后一个当背景；大号文字指 18pt 以上，或 14pt 以上的粗体"),
                                rows: ColorContrast.rows(pair.foreground, pair.background),
                                palette: [pair.foreground.hexString, pair.background.hexString]))
    }
}
