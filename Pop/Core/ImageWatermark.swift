import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 给图片加文字水印：斜着铺满整张图、半透明，存成「原名 水印」放在原图旁边，原图不动。
/// 证件复印件这类图片写上用途，别人拿去也不好挪作他用。
enum ImageWatermark {
    struct Failure: Error, Equatable {
        let message: String
    }

    static let defaultText = "仅供办理业务使用，他用无效"
    /// 上次用的水印文字存在这里
    static let textKey = "watermarkText"

    /// 在图片上斜着铺满水印；opacity 是文字的不透明度（0.1 很淡，0.6 很浓）
    static func apply(_ image: CGImage, text: String, opacity: Double) -> CGImage? {
        let width = image.width
        let height = image.height
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let canvas = CGRect(x: 0, y: 0, width: width, height: height)
        context.draw(image, in: canvas)
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { return context.makeImage() }

        // 字的大小跟着图片走：长边的 1/28，小图也不小于 12 像素
        let fontSize = max(CGFloat(max(width, height)) / 28, 12)
        let font = CTFontCreateUIFontForLanguage(.system, fontSize, nil) ?? CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
        let color = CGColor(gray: 0.45, alpha: CGFloat(min(max(opacity, 0.05), 1)))
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: words, attributes: attributes))
        let bounds = CTLineGetBoundsWithOptions(line, [])
        let stepX = bounds.width + fontSize * 3
        let stepY = fontSize * 4.5

        // 以图片中心为原点转 30°，铺到转过之后还能盖住整张图的范围；每一行错开半个
        context.translateBy(x: CGFloat(width) / 2, y: CGFloat(height) / 2)
        context.rotate(by: .pi / 6)
        let reach = (CGFloat(width * width + height * height)).squareRoot() / 2 + bounds.width
        var row = 0
        var y = -reach
        while y <= reach {
            var x = -reach - (row % 2 == 0 ? 0 : stepX / 2)
            while x <= reach {
                context.textPosition = CGPoint(x: x, y: y)
                CTLineDraw(line, context)
                x += stepX
            }
            y += stepY
            row += 1
        }
        return context.makeImage()
    }

    /// 预览用：缩小后的图片加上水印（字的大小按比例，看起来和存出来的一样）
    static func preview(_ url: URL, text: String, opacity: Double, maxSide: Int = 480) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSide,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return apply(thumbnail, text: text, opacity: opacity)
    }

    /// 加上水印另存一份：照片存成 JPEG，其余存成 PNG；返回新文件的位置
    static func watermark(_ url: URL, text: String, opacity: Double) throws -> URL {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0,
              let image = ImageConverter.uprightImage(source) else {
            throw Failure(message: "读不了「\(url.lastPathComponent)」")
        }
        guard let marked = apply(image, text: text, opacity: opacity) else { throw Failure(message: "「\(url.lastPathComponent)」加水印失败") }
        let sourceType = (CGImageSourceGetType(source) as String?).flatMap { UTType($0) } ?? .png
        let photo = sourceType.conforms(to: .jpeg) || sourceType.conforms(to: .heic) || sourceType.conforms(to: .heif)
        let type: UTType = photo ? .jpeg : .png
        let output = FileNames.available(in: url.deletingLastPathComponent(),
                                         base: url.deletingPathExtension().lastPathComponent + " 水印", extension: photo ? "jpg" : "png")
        guard let destination = CGImageDestinationCreateWithURL(output as CFURL, type.identifier as CFString, 1, nil) else {
            throw Failure(message: "存储「\(output.lastPathComponent)」失败")
        }
        CGImageDestinationAddImage(destination, marked, [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: output)
            throw Failure(message: "存储「\(output.lastPathComponent)」失败")
        }
        return output
    }
}
