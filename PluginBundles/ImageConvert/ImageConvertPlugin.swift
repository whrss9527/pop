import AppKit
@testable import Pop

/// 插件包「图片转换」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopImageConvertEntry)
final class ImageConvertEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [ImageConvertPlugin()]
    }
}

struct ImageConvertPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.imageConvert, name: String(localized: "图片转换"), symbol: "photo.on.rectangle.angled",
                          summary: String(localized: "把选中的图片文件转成 PNG、JPEG、HEIC，缩小一半、压缩体积或者压到指定大小以内，旋转、左右翻转，或者去掉照片里的位置和拍摄信息；结果存在原图旁边"),
                          accepts: [.imageFile])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        let files = content.files.filter(ContentClassifier.isImageFile)
        guard !files.isEmpty else { return .failure(String(localized: "没有选中图片文件")) }
        let first = files[0]
        let single = files.count == 1
        let rows = await runInBackground { single ? ImageInfo.rows(for: first) : [] }
        let what = files.count == 1 ? files[0].lastPathComponent : String(localized: "\(files.count) 张图片")
        // 照片里有位置、拍摄信息时才给去掉的按钮。最多看 200 张，要一张张读（iCloud 里没下载下来的还要先下载），放在后台
        let sample = Array(files.prefix(200))
        let metadata = await runInBackground { sample.compactMap(PhotoMetadata.read) }
        let hasLocation = metadata.contains { $0.hasLocation }
        let hasCapture = metadata.contains { !$0.isEmpty }
        let operations = ImageConverter.Operation.allCases.filter { operation in
            switch operation {
            case .removeLocation: return hasLocation
            case .removeMetadata: return hasCapture
            default: return true
            }
        }
        var buttons = operations.map { operation in
            CardButton(title: operation.title, action: .convertImages(files, operation))
        }
        buttons.append(CardButton(title: String(localized: "压缩到指定大小…"), action: .imageSizeLimit(files)))
        // 一张不太大的图可以直接复制成 data URI（写进网页、CSS、Markdown）
        if files.count == 1, let uri = Base64Image.dataURI(for: files[0]) {
            buttons.append(CardButton(title: String(localized: "复制为 data URI"), action: .copy(uri)))
        }
        return .card(ResultCard(title: String(localized: "图片转换"), detail: String(localized: "\(what)，转换后存在原图旁边"), rows: rows, buttons: buttons))
    }
}
