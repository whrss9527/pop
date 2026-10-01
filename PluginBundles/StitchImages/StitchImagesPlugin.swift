import AppKit
@testable import Pop

/// 插件包「拼接图片」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopStitchImagesEntry)
final class StitchImagesEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [StitchImagesPlugin()]
    }
}

struct StitchImagesPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.stitchImages, name: String(localized: "拼接图片"), symbol: "square.split.1x2",
                          summary: String(localized: "把选中的几张图片按文件名的顺序竖着或者横着拼成一张，或者合成一张动图，存在第一张旁边"),
                          accepts: [.imageFile])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        let images = ImageStitcher.ordered(content.files.filter(ContentClassifier.isImageFile))
        guard images.count >= 2 else { return .failure(String(localized: "选中两张以上的图片才能拼接")) }
        guard images.count <= ImageStitcher.maxCount else { return .failure(String(localized: "一次最多拼 \(ImageStitcher.maxCount) 张")) }
        let shown = 8
        var names = images.prefix(shown).map(\.lastPathComponent)
        if images.count > shown {
            names.append(String(localized: "……还有 \(images.count - shown) 张"))
        }
        let delay = Int(ImageStitcher.gifFrameDelay)
        let stitch = ImageStitcher.Direction.allCases.map { direction in
            CardButton(title: direction.title, action: .stitchImages(images, direction))
        }
        return .card(ResultCard(title: String(localized: "拼接图片"), body: names.joined(separator: "\n"),
                                detail: String(localized: "\(images.count) 张图片按上面的顺序拼接；宽度（横着拼时是高度）不一样时按最小的那张缩放。合成动图时每张停 \(delay) 秒，画面大小按第一张"),
                                buttons: stitch + [CardButton(title: String(localized: "合成动图"), action: .animateImages(images))]))
    }
}
