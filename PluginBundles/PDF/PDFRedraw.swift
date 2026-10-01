import AppKit
@testable import Pop

/// 把 PDF 一页页重新画进新的 PDF：每页先原样画上原来的页面（按显示的方向，转过的页面摆正），
/// 再在上面加东西（看不见的文字层、页码）。标题和作者照搬。
enum PDFRedraw {
    /// 页面按显示的方向（算上旋转）有多大：看到的那块（裁切框）
    static func displaySize(of page: CGPDFPage) -> CGSize {
        let box = page.getBoxRect(.cropBox)
        let quarterTurns = Int(page.rotationAngle) / 90
        return quarterTurns % 2 == 0 ? box.size : CGSize(width: box.height, height: box.width)
    }

    /// 把页面按显示的方向画进 size 大小的地方（左下角是原点）
    static func drawPage(_ page: CGPDFPage, size: CGSize, in context: CGContext) {
        context.saveGState()
        context.concatenate(page.getDrawingTransform(.cropBox, rect: CGRect(origin: .zero, size: size), rotate: 0, preserveAspectRatio: true))
        context.drawPDFPage(page)
        context.restoreGState()
    }

    /// 画成白底的图片：长边 longSide 像素，最多放大 4 倍；overlay 在页面坐标里接着画
    static func render(_ page: CGPDFPage, longSide: CGFloat, overlay: (CGSize, CGContext) -> Void = { _, _ in }) -> CGImage? {
        let size = displaySize(of: page)
        guard size.width > 1, size.height > 1 else { return nil }
        let scale = min(4, longSide / max(size.width, size.height))
        let width = Int((size.width * scale).rounded())
        let height = Int((size.height * scale).rounded())
        guard width > 0, height > 0, width * height <= 60_000_000,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        drawPage(page, size: size, in: context)
        overlay(size, context)
        return context.makeImage()
    }

    /// 写成新的 PDF：overlay 拿到第几页（0 开始）、页面大小，在原来的页面上面接着画
    static func write(_ document: CGPDFDocument, to url: URL, overlay: (_ index: Int, _ size: CGSize, _ context: CGContext) -> Void) throws {
        var info: [String: Any] = [kCGPDFContextCreator as String: "Pop"]
        if let dictionary = document.info {
            for (key, name) in [("Title", kCGPDFContextTitle), ("Author", kCGPDFContextAuthor)] {
                var value: CGPDFStringRef?
                if CGPDFDictionaryGetString(dictionary, key, &value), let value, let text = CGPDFStringCopyTextString(value) {
                    info[name as String] = text as String
                }
            }
        }
        var firstBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(url as CFURL, mediaBox: &firstBox, info as CFDictionary) else {
            throw PDFTools.Failure(message: String(localized: "写不进「\(url.lastPathComponent)」"))
        }
        for number in 1...max(document.numberOfPages, 1) {
            guard let page = document.page(at: number) else { continue }
            let size = displaySize(of: page)
            var box = CGRect(origin: .zero, size: size)
            context.beginPage(mediaBox: &box)
            drawPage(page, size: size, in: context)
            overlay(number - 1, size, context)
            context.endPage()
        }
        context.closePDF()
    }

    /// 打开要重画的 PDF：读不了、有密码时说明原因
    static func open(_ pdf: URL) throws -> CGPDFDocument {
        guard let document = CGPDFDocument(pdf as CFURL), document.numberOfPages > 0 else {
            throw PDFTools.Failure(message: String(localized: "读不了「\(pdf.lastPathComponent)」"))
        }
        guard !document.isEncrypted || document.isUnlocked else {
            throw PDFTools.Failure(message: String(localized: "「\(pdf.lastPathComponent)」有密码，先解锁再处理"))
        }
        return document
    }
}
