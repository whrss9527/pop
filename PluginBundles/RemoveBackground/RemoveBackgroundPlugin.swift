import AppKit
@testable import Pop

/// 插件包「抠图」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopRemoveBackgroundEntry)
final class RemoveBackgroundEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [RemoveBackgroundPlugin()]
    }
}

struct RemoveBackgroundPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.removeBackground, name: String(localized: "抠图"), symbol: "wand.and.stars",
                          summary: String(localized: "去掉选中图片的背景，只留下人、动物或物品（离线）"), accepts: [.image, .imageFile])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        let image: CGImage?
        var name = ImageFiles.timestampedName(String(localized: "Pop 抠图"))
        if case .image(let data) = content.selection {
            image = TextRecognizer.cgImage(from: data)
        } else if let url = content.files.first {
            image = await TextRecognizer.decodedImage(contentsOf: url)
            name = url.deletingPathExtension().lastPathComponent + String(localized: " 抠图")
        } else {
            image = nil
        }
        guard let image else { return .failure(String(localized: "无法读取图片")) }
        switch await SubjectLifter.lift(image) {
        case .success(let png):
            return .card(ResultCard(title: String(localized: "抠图"), detail: String(localized: "背景已去掉，复制或存储的 PNG 保留透明"), image: png,
                                    buttons: [CardButton(title: String(localized: "复制图片"), action: .copyImage(png)),
                                              CardButton(title: String(localized: "存到「下载」"), action: .saveImage(png, name: name)),
                                              CardButton(title: String(localized: "贴到屏幕"), action: .pinImage(png))]))
        case .failure(let error):
            return .failure(error.message)
        }
    }
}
