import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 图片的尺寸、格式、文件大小（图片转换、文件信息的卡片上用）
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
