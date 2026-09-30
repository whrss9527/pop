import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 给图片和 PDF 加文字水印：斜着铺满整张图（PDF 是每一页）、半透明，存成「原名 水印」放在原文件旁边，原文件不动。
/// 证件复印件这类图片写上用途，别人拿去也不好挪作他用。
enum ImageWatermark {
    struct Failure: Error, Equatable {
        let message: String
    }

    static let defaultText = String(localized: "仅供办理业务使用，他用无效")
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
        drawTiles(in: context, size: canvas.size, text: text, opacity: opacity)
        return context.makeImage()
    }

    /// 在 size 大小的画面上斜着铺满水印文字（图片和 PDF 页面共用）；没有文字就不画
    static func drawTiles(in context: CGContext, size: CGSize, text: String, opacity: Double) {
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty, size.width > 0, size.height > 0 else { return }

        // 字的大小跟着画面走：长边的 1/28，小图也不小于 12 像素
        let fontSize = max(max(size.width, size.height) / 28, 12)
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

        // 以画面中心为原点转 30°，铺到转过之后还能盖住整个画面的范围；每一行错开半个
        context.saveGState()
        context.translateBy(x: size.width / 2, y: size.height / 2)
        context.rotate(by: .pi / 6)
        let reach = (size.width * size.width + size.height * size.height).squareRoot() / 2 + bounds.width
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
        context.restoreGState()
    }

    static func isPDF(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "pdf"
    }

    /// PDF 的第一页画成不超过 maxSide 的图（预览用）
    static func pdfThumbnail(_ url: URL, maxSide: Int) -> CGImage? {
        guard let document = CGPDFDocument(url as CFURL), let page = document.page(at: 1) else { return nil }
        let size = pageSize(page)
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = CGFloat(maxSide) / max(size.width, size.height)
        let width = max(Int((size.width * scale).rounded()), 1)
        let height = max(Int((size.height * scale).rounded()), 1)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(rect)
        context.concatenate(page.getDrawingTransform(.cropBox, rect: rect, rotate: 0, preserveAspectRatio: true))
        context.drawPDFPage(page)
        return context.makeImage()
    }

    /// 页面转正之后的大小（/Rotate 是 90° 或 270° 时宽高对调）
    static func pageSize(_ page: CGPDFPage) -> CGSize {
        let box = page.getBoxRect(.cropBox)
        return page.rotationAngle % 180 == 0 ? box.size : CGSize(width: box.height, height: box.width)
    }

    /// PDF 每一页都铺上水印（画在页面内容上面，原来的文字还能选中、搜索），另存「原名 水印.pdf」
    static func watermarkPDF(_ url: URL, text: String, opacity: Double) throws -> URL {
        guard let document = CGPDFDocument(url as CFURL), document.numberOfPages > 0 else {
            throw Failure(message: String(localized: "读不了「\(url.lastPathComponent)」"))
        }
        if document.isEncrypted && !document.isUnlocked && !document.unlockWithPassword("") {
            throw Failure(message: String(localized: "「\(url.lastPathComponent)」有密码，先用「PDF → 去掉密码」再加水印"))
        }
        let output = FileNames.available(in: url.deletingLastPathComponent(),
                                         base: url.deletingPathExtension().lastPathComponent + String(localized: " 水印"), extension: "pdf")
        guard let context = CGContext(output as CFURL, mediaBox: nil, nil) else {
            throw Failure(message: String(localized: "存储「\(output.lastPathComponent)」失败"))
        }
        for index in 1...document.numberOfPages {
            guard let page = document.page(at: index) else { continue }
            var mediaBox = CGRect(origin: .zero, size: pageSize(page))
            context.beginPage(mediaBox: &mediaBox)
            context.saveGState()
            context.concatenate(page.getDrawingTransform(.cropBox, rect: mediaBox, rotate: 0, preserveAspectRatio: true))
            context.drawPDFPage(page)
            context.restoreGState()
            drawTiles(in: context, size: mediaBox.size, text: text, opacity: opacity)
            context.endPage()
        }
        context.closePDF()
        return output
    }

    /// 预览用：缩小后的图片加上水印（字的大小按比例，看起来和存出来的一样）
    static func preview(_ url: URL, text: String, opacity: Double, maxSide: Int = 480) -> CGImage? {
        if isPDF(url) {
            return pdfThumbnail(url, maxSide: maxSide).flatMap { apply($0, text: text, opacity: opacity) }
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSide,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return apply(thumbnail, text: text, opacity: opacity)
    }

    /// 加上水印另存一份：照片存成 JPEG，PDF 还是 PDF，其余存成 PNG；返回新文件的位置
    static func watermark(_ url: URL, text: String, opacity: Double) throws -> URL {
        if isPDF(url) {
            return try watermarkPDF(url, text: text, opacity: opacity)
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0,
              let image = ImageConverter.uprightImage(source) else {
            throw Failure(message: String(localized: "读不了「\(url.lastPathComponent)」"))
        }
        guard let marked = apply(image, text: text, opacity: opacity) else { throw Failure(message: String(localized: "「\(url.lastPathComponent)」加水印失败")) }
        let sourceType = (CGImageSourceGetType(source) as String?).flatMap { UTType($0) } ?? .png
        let photo = sourceType.conforms(to: .jpeg) || sourceType.conforms(to: .heic) || sourceType.conforms(to: .heif)
        let type: UTType = photo ? .jpeg : .png
        let output = FileNames.available(in: url.deletingLastPathComponent(),
                                         base: url.deletingPathExtension().lastPathComponent + String(localized: " 水印"), extension: photo ? "jpg" : "png")
        guard let destination = CGImageDestinationCreateWithURL(output as CFURL, type.identifier as CFString, 1, nil) else {
            throw Failure(message: String(localized: "存储「\(output.lastPathComponent)」失败"))
        }
        CGImageDestinationAddImage(destination, marked, [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: output)
            throw Failure(message: String(localized: "存储「\(output.lastPathComponent)」失败"))
        }
        return output
    }
}
