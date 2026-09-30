import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 把几张图片拼成一张：竖着拼时宽度对齐，横着拼时高度对齐。
/// 按最窄（最矮）的那张缩放，小图不会被放大变糊；同一台设备的截图尺寸相同，原样拼接。
enum ImageStitcher {
    enum Direction: String, CaseIterable, Identifiable {
        case vertical
        case horizontal

        var id: String { rawValue }

        var title: String {
            switch self {
            case .vertical: return String(localized: "竖着拼接")
            case .horizontal: return String(localized: "横着拼接")
            }
        }
    }

    /// 拼出来的图最长这么多像素，超过了整体缩小
    static let maxLength: CGFloat = 30_000
    /// 一次最多拼这么多张
    static let maxCount = 50

    struct Failure: Error, Equatable {
        let message: String
    }

    struct Layout: Equatable {
        var size: CGSize
        /// 每张图的位置（像素，左上角为原点）
        var frames: [CGRect]
    }

    /// 每张图放在哪里
    static func layout(_ sizes: [CGSize], direction: Direction, maxLength: CGFloat = ImageStitcher.maxLength) -> Layout {
        guard !sizes.isEmpty else { return Layout(size: .zero, frames: []) }
        let sizes = sizes.map { CGSize(width: max($0.width, 1), height: max($0.height, 1)) }
        var frames: [CGRect] = []
        var offset: CGFloat = 0
        var total: CGSize
        switch direction {
        case .vertical:
            let width = sizes.map(\.width).min() ?? 1
            for size in sizes {
                let height = max((size.height * width / size.width).rounded(), 1)
                frames.append(CGRect(x: 0, y: offset, width: width, height: height))
                offset += height
            }
            total = CGSize(width: width, height: offset)
        case .horizontal:
            let height = sizes.map(\.height).min() ?? 1
            for size in sizes {
                let width = max((size.width * height / size.height).rounded(), 1)
                frames.append(CGRect(x: offset, y: 0, width: width, height: height))
                offset += width
            }
            total = CGSize(width: offset, height: height)
        }
        let longest = max(total.width, total.height)
        guard longest > maxLength else { return Layout(size: total, frames: frames) }
        // 太长了：整体缩小，每张的边界取整后首尾相接
        let scale = maxLength / longest
        var scaled: [CGRect] = []
        offset = 0
        for frame in frames {
            switch direction {
            case .vertical:
                let next = (frame.maxY * scale).rounded()
                scaled.append(CGRect(x: 0, y: offset, width: max((total.width * scale).rounded(), 1), height: max(next - offset, 1)))
                offset = next
            case .horizontal:
                let next = (frame.maxX * scale).rounded()
                scaled.append(CGRect(x: offset, y: 0, width: max(next - offset, 1), height: max((total.height * scale).rounded(), 1)))
                offset = next
            }
        }
        total = direction == .vertical
            ? CGSize(width: max((total.width * scale).rounded(), 1), height: offset)
            : CGSize(width: offset, height: max((total.height * scale).rounded(), 1))
        return Layout(size: total, frames: scaled)
    }

    /// 按文件名排好的顺序（截图的文件名里带着时间，按名字排就是按先后）
    static func ordered(_ urls: [URL]) -> [URL] {
        urls.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    /// 拼好存在第一张图旁边，返回新文件的位置
    static func stitch(_ urls: [URL], direction: Direction) throws -> URL {
        guard urls.count >= 2 else { throw Failure(message: String(localized: "至少选两张图片")) }
        guard urls.count <= maxCount else { throw Failure(message: String(localized: "一次最多拼 \(maxCount) 张")) }
        var sources: [CGImageSource] = []
        var sizes: [CGSize] = []
        for url in urls {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0,
                  let size = uprightSize(source) else {
                throw Failure(message: String(localized: "读不了「\(url.lastPathComponent)」"))
            }
            sources.append(source)
            sizes.append(size)
        }
        let plan = layout(sizes, direction: direction)
        // 全是照片（JPEG、HEIC）就存成 JPEG，否则存成 PNG（保留透明和截图的清晰度）
        let photos = sources.allSatisfy { source in
            guard let identifier = CGImageSourceGetType(source) as String?, let type = UTType(identifier) else { return false }
            return type.conforms(to: .jpeg) || type.conforms(to: .heic) || type.conforms(to: .heif)
        }
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: nil, width: Int(plan.size.width), height: Int(plan.size.height),
                                      bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw Failure(message: String(localized: "拼出来的图太大了"))
        }
        context.interpolationQuality = .high
        if photos {
            context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            context.fill(CGRect(origin: .zero, size: plan.size))
        }
        for (index, (source, frame)) in zip(sources, plan.frames).enumerated() {
            // 按需要的大小解码（照片按方向摆正），不用先把每张原图都完整读进内存
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: max(frame.width, frame.height),
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                throw Failure(message: String(localized: "读不了「\(urls[index].lastPathComponent)」"))
            }
            // CGContext 的原点在左下角
            context.draw(image, in: CGRect(x: frame.minX, y: plan.size.height - frame.maxY, width: frame.width, height: frame.height))
        }
        guard let result = context.makeImage() else { throw Failure(message: String(localized: "拼出来的图太大了")) }
        let type: UTType = photos ? .jpeg : .png
        let first = urls[0]
        let output = FileNames.available(in: first.deletingLastPathComponent(),
                                         base: first.deletingPathExtension().lastPathComponent + String(localized: " 拼接"),
                                         extension: photos ? "jpg" : "png")
        guard let destination = CGImageDestinationCreateWithURL(output as CFURL, type.identifier as CFString, 1, nil) else {
            throw Failure(message: String(localized: "存储「\(output.lastPathComponent)」失败"))
        }
        CGImageDestinationAddImage(destination, result, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: output)
            throw Failure(message: String(localized: "存储「\(output.lastPathComponent)」失败"))
        }
        return output
    }

    /// 按照片方向摆正后的尺寸（竖着拍的照片宽高对调）
    static func uprightSize(_ source: CGImageSource) -> CGSize? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int, width > 0, height > 0 else { return nil }
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        return orientation >= 5 && orientation <= 8
            ? CGSize(width: height, height: width)
            : CGSize(width: width, height: height)
    }
}
