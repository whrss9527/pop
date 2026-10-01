import AppKit
@testable import Pop

/// 插件包「Base64 图片」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopBase64ImageEntry)
final class Base64ImageEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [Base64ImagePlugin()]
    }
}

struct Base64ImagePlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.base64Image, name: String(localized: "Base64 图片"), symbol: "photo.artframe",
                          summary: String(localized: "把 Base64 或 data: 开头的图片数据显示成图片，可以复制、保存、贴到屏幕"), accepts: [.text],
                          maxLength: 30_000_000, check: .base64Image)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text else { return .failure(String(localized: "没有选中文字")) }
        let result = await runInBackground { () -> (Base64Image.Decoded, Data)? in
            guard let decoded = Base64Image.decode(text), let png = Base64Image.png(from: decoded.data) else { return nil }
            return (decoded, png)
        }
        guard let (decoded, png) = result else { return .failure(String(localized: "解不出图片")) }
        let rows = [
            ResultCard.Row(label: String(localized: "格式"), value: decoded.type.preferredFilenameExtension?.uppercased() ?? decoded.type.identifier),
            ResultCard.Row(label: String(localized: "尺寸"), value: "\(decoded.width) × \(decoded.height)"),
            ResultCard.Row(label: String(localized: "大小"), value: FileInfo.shortSize(Int64(decoded.data.count))),
        ]
        return .card(ResultCard(title: String(localized: "Base64 图片"), rows: rows, image: png, buttons: [
            CardButton(title: String(localized: "复制图片"), action: .copyImage(png)),
            CardButton(title: String(localized: "存到「下载」"), action: .saveImage(png, name: ImageFiles.timestampedName(String(localized: "Base64 图片")))),
            CardButton(title: String(localized: "贴到屏幕"), action: .pinImage(png)),
        ]))
    }
}
