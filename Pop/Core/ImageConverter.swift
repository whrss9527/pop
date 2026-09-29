import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 图片转换：换格式、缩小尺寸、压缩体积。结果存在原图旁边，不覆盖原图。
enum ImageConverter {
    enum Operation: String, CaseIterable, Identifiable {
        case png
        case jpeg
        case heic
        case halfSize
        case compress

        var id: String { rawValue }

        var title: String {
            switch self {
            case .png: return "转成 PNG"
            case .jpeg: return "转成 JPEG"
            case .heic: return "转成 HEIC"
            case .halfSize: return "缩小一半"
            case .compress: return "压缩"
            }
        }
    }

    struct Failure: Error, Equatable {
        let message: String
    }

    /// 转换一张图片，返回新文件的位置
    static func convert(_ url: URL, _ operation: Operation) throws -> URL {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0 else {
            throw Failure(message: "读不了「\(url.lastPathComponent)」")
        }
        let sourceType = (CGImageSourceGetType(source) as String?).flatMap { UTType($0) } ?? .png
        let type: UTType
        var properties: [CFString: Any] = [:]
        let image: CGImage?
        switch operation {
        case .png:
            type = .png
            image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        case .jpeg:
            type = .jpeg
            properties[kCGImageDestinationLossyCompressionQuality] = 0.9
            image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        case .heic:
            type = .heic
            properties[kCGImageDestinationLossyCompressionQuality] = 0.8
            image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        case .halfSize:
            type = sourceType
            image = halfSizeImage(source)
        case .compress:
            type = .jpeg
            properties[kCGImageDestinationLossyCompressionQuality] = 0.7
            image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        }
        guard let image else { throw Failure(message: "读不了「\(url.lastPathComponent)」") }
        let output = outputURL(for: url, operation: operation, type: type)
        guard let destination = CGImageDestinationCreateWithURL(output as CFURL, type.identifier as CFString, 1, nil) else {
            throw Failure(message: "这台 Mac 不支持存成 \(type.preferredFilenameExtension?.uppercased() ?? "这种格式")")
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: output)
            throw Failure(message: "存储「\(output.lastPathComponent)」失败")
        }
        return output
    }

    /// 缩小一半：按原图方向摆正后，长边缩到原来的一半
    private static func halfSizeImage(_ source: CGImageSource) -> CGImage? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(max(width, height) / 2, 1),
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// 新文件名：「原名.png」；和原图同名同格式时加上说明（「原名 缩小.jpg」），已经有同名文件时再加编号
    static func outputURL(for url: URL, operation: Operation, type: UTType) -> URL {
        let folder = url.deletingLastPathComponent()
        let base = url.deletingPathExtension().lastPathComponent
        // JPEG 习惯用 .jpg
        let ext = type == .jpeg ? "jpg" : (type.preferredFilenameExtension ?? url.pathExtension)
        var name = base
        switch operation {
        case .halfSize: name += " 缩小"
        case .compress: name += " 压缩"
        case .png, .jpeg, .heic: break
        }
        var candidate = folder.appending(path: "\(name).\(ext)")
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path(percentEncoded: false)) {
            candidate = folder.appending(path: "\(name) \(counter).\(ext)")
            counter += 1
        }
        return candidate
    }
}
