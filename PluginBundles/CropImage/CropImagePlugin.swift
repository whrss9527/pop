import AppKit
@testable import Pop

/// 插件包「裁剪图片」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopCropImageEntry)
final class CropImageEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [CropImagePlugin()]
    }
}

struct CropImagePlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.cropImage, name: String(localized: "裁剪图片"), symbol: "crop",
                          summary: String(localized: "把选中的图片裁成 1:1、4:3、3:4、16:9、9:16，自动对准画面里的主体；另存一份放在原图旁边"),
                          accepts: [.imageFile])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        let images = content.files.filter(ContentClassifier.isImageFile)
        guard !images.isEmpty else { return .failure(String(localized: "没有选中图片")) }
        return .card(SmartCrop.card(images))
    }
}
