import AppKit
@testable import Pop

/// 插件包「文字转图片」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopTextImageEntry)
final class TextImageEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [TextImagePlugin()]
    }
}

struct TextImagePlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.textImage, name: String(localized: "文字转图片"), symbol: "text.below.photo",
                          summary: String(localized: "把选中的文字排成一张手机上看着舒服的长图（宽 1080 像素），白底、米黄、深色三种底色，可以复制、存储或贴到屏幕上"),
                          accepts: [.text], maxLength: 50_000)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text else { return .failure(String(localized: "没有文字")) }
        return TextImage.outcome(text, style: .paper)
    }
}
