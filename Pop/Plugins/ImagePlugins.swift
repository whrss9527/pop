import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

// MARK: - 图片转换

struct ImageConvertPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.imageConvert, name: String(localized: "图片转换"), symbol: "photo.on.rectangle.angled",
                          summary: String(localized: "把选中的图片文件转成 PNG、JPEG、HEIC，缩小一半、压缩体积或者压到指定大小以内，旋转、左右翻转，或者去掉照片里的位置和拍摄信息；结果存在原图旁边"),
                          accepts: [.imageFile])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        let files = content.files.filter(ContentClassifier.isImageFile)
        guard !files.isEmpty else { return .failure(String(localized: "没有选中图片文件")) }
        let rows = files.count == 1 ? ImageInfo.rows(for: files[0]) : []
        let what = files.count == 1 ? files[0].lastPathComponent : String(localized: "\(files.count) 张图片")
        // 照片里有位置、拍摄信息时才给去掉的按钮
        let metadata = files.prefix(200).compactMap(PhotoMetadata.read)
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

enum ImageInfo {
    /// 尺寸、格式、文件大小
    static func rows(for url: URL) -> [ResultCard.Row] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return [] }
        var rows: [ResultCard.Row] = []
        if let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int {
            rows.append(ResultCard.Row(label: String(localized: "尺寸"), value: "\(width) × \(height)"))
        }
        if let identifier = CGImageSourceGetType(source) as String?, let type = UTType(identifier) {
            rows.append(ResultCard.Row(label: String(localized: "格式"), value: type.preferredFilenameExtension?.uppercased() ?? identifier))
        }
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
            rows.append(ResultCard.Row(label: String(localized: "大小"), value: ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)))
        }
        return rows
    }
}

// MARK: - 换行排列

/// 一行放不下时自动换到下一行的排列（结果卡片底部的按钮）
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var width: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            width = max(width, x + size.width)
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: proposal.width ?? width, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
