import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

/// 按比例裁剪图片：在这个比例下取最大的一块，用 Vision 找出画面里最吸引注意的地方，尽量把它放在中间。
/// 另存一份放在原图旁边，原图不动。
enum SmartCrop {
    enum Ratio: String, CaseIterable, Identifiable {
        case square
        case fourThree
        case threeFour
        case sixteenNine
        case nineSixteen

        var id: String { rawValue }

        var title: String {
            switch self {
            case .square: return "1:1 方形"
            case .fourThree: return "4:3"
            case .threeFour: return "3:4"
            case .sixteenNine: return "16:9"
            case .nineSixteen: return "9:16"
            }
        }

        /// 宽 ÷ 高
        var value: CGFloat {
            switch self {
            case .square: return 1
            case .fourThree: return 4.0 / 3.0
            case .threeFour: return 3.0 / 4.0
            case .sixteenNine: return 16.0 / 9.0
            case .nineSixteen: return 9.0 / 16.0
            }
        }

        /// 文件名里用的写法（文件名里不能有冒号）
        var fileSuffix: String {
            switch self {
            case .square: return "1比1"
            case .fourThree: return "4比3"
            case .threeFour: return "3比4"
            case .sixteenNine: return "16比9"
            case .nineSixteen: return "9比16"
            }
        }
    }

    struct Failure: Error, Equatable {
        let message: String
    }

    /// 画面里最吸引注意的区域（像素，左上角为原点）；找不到时为 nil
    static func focus(of image: CGImage) -> CGRect? {
        let request = VNGenerateAttentionBasedSaliencyImageRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        guard (try? handler.perform([request])) != nil, let observation = request.results?.first,
              let objects = observation.salientObjects, !objects.isEmpty else { return nil }
        let union = objects.map(\.boundingBox).reduce(CGRect.null) { $0.union($1) }
        guard !union.isNull, union.width > 0, union.height > 0 else { return nil }
        return IDPhoto.pixelRect(union, width: image.width, height: image.height)
    }

    /// 宽高比 ratio 下最大的裁剪框（像素，左上角为原点），中心尽量对准 focus 的中心，不超出图片
    static func cropRect(imageSize: CGSize, ratio: CGFloat, focus: CGRect?) -> CGRect {
        var width = imageSize.width
        var height = width / ratio
        if height > imageSize.height {
            height = imageSize.height
            width = height * ratio
        }
        // 差一点点到整数的（比如 1079.9999）算整数
        width = min((width + 0.001).rounded(.down), imageSize.width)
        height = min((height + 0.001).rounded(.down), imageSize.height)
        let center = focus.map { CGPoint(x: $0.midX, y: $0.midY) } ?? CGPoint(x: imageSize.width / 2, y: imageSize.height / 2)
        let x = min(max(center.x - width / 2, 0), imageSize.width - width).rounded(.down)
        let y = min(max(center.y - height / 2, 0), imageSize.height - height).rounded(.down)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// 裁好另存一份放在原图旁边：「原名 16比9.jpg」。照片存成 JPEG，其余存成 PNG
    static func crop(_ url: URL, ratio: Ratio) throws -> URL {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0,
              let image = ImageConverter.uprightImage(source) else {
            throw Failure(message: "读不了「\(url.lastPathComponent)」")
        }
        let size = CGSize(width: image.width, height: image.height)
        let whole = cropRect(imageSize: size, ratio: ratio.value, focus: nil)
        if Int(whole.width) == image.width, Int(whole.height) == image.height {
            throw Failure(message: "「\(url.lastPathComponent)」本来就是 \(ratio.title)")
        }
        let rect = cropRect(imageSize: size, ratio: ratio.value, focus: focus(of: image))
        guard rect.width >= 1, rect.height >= 1, let cropped = image.cropping(to: rect) else {
            throw Failure(message: "「\(url.lastPathComponent)」裁剪失败")
        }
        let sourceType = (CGImageSourceGetType(source) as String?).flatMap { UTType($0) } ?? .png
        let photo = sourceType.conforms(to: .jpeg) || sourceType.conforms(to: .heic) || sourceType.conforms(to: .heif)
        let type: UTType = photo ? .jpeg : .png
        let output = FileNames.available(in: url.deletingLastPathComponent(),
                                         base: url.deletingPathExtension().lastPathComponent + " " + ratio.fileSuffix,
                                         extension: photo ? "jpg" : "png")
        guard let destination = CGImageDestinationCreateWithURL(output as CFURL, type.identifier as CFString, 1, nil) else {
            throw Failure(message: "存储「\(output.lastPathComponent)」失败")
        }
        CGImageDestinationAddImage(destination, cropped, [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: output)
            throw Failure(message: "存储「\(output.lastPathComponent)」失败")
        }
        return output
    }
}
