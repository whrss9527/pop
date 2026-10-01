import AppKit
@testable import Pop

/// 插件包「代码截图」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopCodeImageEntry)
final class CodeImageEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [CodeImagePlugin()]
    }
}

struct CodeImagePlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.codeImage, name: String(localized: "代码截图"), symbol: "chevron.left.forwardslash.chevron.right",
                          summary: String(localized: "把选中的代码画成一张图片（深色编辑器、语法着色、渐变背景），可以复制、存储或贴到屏幕上"),
                          accepts: [.text], maxLength: 20_000)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text, let png = CodeImage.render(text) else { return .failure(String(localized: "没能画出这段代码")) }
        return .card(ResultCard(title: String(localized: "代码截图"), detail: String(localized: "按住拖动预览图也能拖到别的 App 里"), image: png, buttons: [
            CardButton(title: String(localized: "复制图片"), action: .copyImage(png)),
            CardButton(title: String(localized: "存储"), action: .saveImage(png, name: ImageFiles.timestampedName(String(localized: "Pop 代码")))),
            CardButton(title: String(localized: "贴到屏幕"), action: .pinImage(png)),
        ]))
    }
}
