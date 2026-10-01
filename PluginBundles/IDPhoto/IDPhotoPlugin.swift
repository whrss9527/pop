import AppKit
@testable import Pop

/// 插件包「证件照」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopIDPhotoEntry)
final class IDPhotoEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [IDPhotoPlugin()]
    }
}

struct IDPhotoPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.idPhoto, name: String(localized: "证件照"), symbol: "person.crop.rectangle",
                          summary: String(localized: "把人像照片换成白底、蓝底或红底，按人脸位置裁成一寸、二寸（300 dpi）；在本机处理，另存一份放在原图旁边"),
                          accepts: [.imageFile])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let file = content.files.first(where: IDPhoto.isImage) else { return .failure(String(localized: "没有选中照片")) }
        return .idPhoto(file)
    }
}
