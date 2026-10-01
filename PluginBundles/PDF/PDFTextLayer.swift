import AppKit
import CoreText
import SwiftUI
import Vision
@testable import Pop

/// 给扫描的 PDF 加上文字层：每页认出文字，在原来的位置写上看不见的文字，页面本身原样画进去。
/// 存成新的 PDF 以后能搜索、选中、复制，看起来和原来一样。
enum PDFTextLayer {
    /// 认出来的一行字和它在页面上的位置（点；页面按显示的方向转好，左下角是原点）
    struct Line: Equatable {
        let text: String
        let rect: CGRect
    }

    struct Summary: Equatable {
        let pages: Int
        let characters: Int
    }

    /// 识别的语言：和「识别文字」一样，中英日韩
    static let languages = ["zh-Hans", "zh-Hant", "en-US", "ja-JP", "ko-KR"]

    /// 文字少于每页这么多个，就当它没有文字层（扫描件），给出「识别文字」
    static let sparseCharactersPerPage = 20

    static func needsTextLayer(characters: Int, pages: Int) -> Bool {
        characters < max(pages, 1) * sparseCharactersPerPage
    }

    /// 页面按显示的方向（算上旋转）有多大：看到的那块（裁切框）
    static func displaySize(of page: CGPDFPage) -> CGSize {
        let box = page.getBoxRect(.cropBox)
        let quarterTurns = Int(page.rotationAngle) / 90
        return quarterTurns % 2 == 0 ? box.size : CGSize(width: box.height, height: box.width)
    }

    /// 把页面按显示的方向画进 size 大小的地方
    private static func drawPage(_ page: CGPDFPage, size: CGSize, in context: CGContext) {
        context.saveGState()
        context.concatenate(page.getDrawingTransform(.cropBox, rect: CGRect(origin: .zero, size: size), rotate: 0, preserveAspectRatio: true))
        context.drawPDFPage(page)
        context.restoreGState()
    }

    /// 画成白底的图片给 Vision 认：长边 2400 像素左右，最多放大 4 倍
    static func render(_ page: CGPDFPage, longSide: CGFloat = 2400) -> CGImage? {
        let size = displaySize(of: page)
        guard size.width > 1, size.height > 1 else { return nil }
        let scale = min(4, max(1, longSide / max(size.width, size.height)))
        let width = Int((size.width * scale).rounded())
        let height = Int((size.height * scale).rounded())
        guard width * height <= 60_000_000,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        drawPage(page, size: size, in: context)
        return context.makeImage()
    }

    /// Vision 给的位置（0～1，左下角是原点）换成页面上的点
    static func lines(_ found: [(text: String, box: CGRect)], pageSize: CGSize) -> [Line] {
        found.compactMap { item in
            let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, item.box.width > 0, item.box.height > 0 else { return nil }
            return Line(text: text, rect: CGRect(x: item.box.minX * pageSize.width, y: item.box.minY * pageSize.height,
                                                 width: item.box.width * pageSize.width, height: item.box.height * pageSize.height))
        }
    }

    /// 认出一页上的字（在后台线程调用）
    static func recognize(_ page: CGPDFPage) throws -> [Line] {
        guard let image = render(page) else { return [] }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = languages
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        let found = (request.results ?? []).compactMap { observation -> (text: String, box: CGRect)? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return (candidate.string, observation.boundingBox)
        }
        return lines(found, pageSize: displaySize(of: page))
    }

    /// 写成新的 PDF：每页先原样画上原来的页面，再在每行的位置写上看不见的文字。标题和作者照搬
    static func write(_ document: CGPDFDocument, pages: [[Line]], to url: URL) throws {
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
            drawInvisible(number - 1 < pages.count ? pages[number - 1] : [], in: context)
            context.endPage()
        }
        context.closePDF()
    }

    /// 每行写在它的位置上：字号按行高，横向拉伸到和这一行一样宽；看不见，但能搜索、选中、复制
    static func drawInvisible(_ lines: [Line], in context: CGContext) {
        context.saveGState()
        context.setTextDrawingMode(.invisible)
        for line in lines {
            let size = max(line.rect.height * 0.86, 1)
            let font = CTFontCreateWithName("PingFangSC-Regular" as CFString, size, nil)
            let attributes: [NSAttributedString.Key: Any] = [NSAttributedString.Key(kCTFontAttributeName as String): font]
            let ctLine = CTLineCreateWithAttributedString(NSAttributedString(string: line.text, attributes: attributes))
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            var leading: CGFloat = 0
            let width = CGFloat(CTLineGetTypographicBounds(ctLine, &ascent, &descent, &leading))
            guard width > 0 else { continue }
            context.textMatrix = CGAffineTransform(scaleX: line.rect.width / width, y: 1)
            // 基线放在框底往上一个下行高度，字的上下和框差不多对齐
            context.textPosition = CGPoint(x: line.rect.minX, y: line.rect.minY + descent * line.rect.height / max(ascent + descent, 1))
            CTLineDraw(ctLine, context)
        }
        context.restoreGState()
    }
}

/// 识别文字、存成可搜索的 PDF 的卡片：一页页认，显示认到第几页，可以停下；关掉卡片也在后台接着认
@MainActor
final class PDFTextLayerModel: ObservableObject {
    let pdf: URL
    let destination: URL
    @Published private(set) var done = 0
    @Published private(set) var total = 0
    @Published private(set) var stopped = false
    private var task: Task<Void, Never>?

    init(pdf: URL, destination: URL) {
        self.pdf = pdf
        self.destination = destination
    }

    /// 「正在识别第 3 / 12 页」
    var progressText: String {
        total == 0 ? String(localized: "正在打开 PDF…") : String(localized: "正在识别第 \(min(done + 1, total)) / \(total) 页")
    }

    /// 开始识别；认完写好文件以后 finish 调一次（停下了不调）
    func start(_ finish: @escaping @MainActor (Result<PDFTextLayer.Summary, PDFTools.Failure>) -> Void) {
        let pdf = pdf
        let destination = destination
        task = Task {
            guard let document = CGPDFDocument(pdf as CFURL), document.numberOfPages > 0 else {
                finish(.failure(PDFTools.Failure(message: String(localized: "读不了「\(pdf.lastPathComponent)」"))))
                return
            }
            guard !document.isEncrypted || document.isUnlocked else {
                finish(.failure(PDFTools.Failure(message: String(localized: "「\(pdf.lastPathComponent)」有密码，先解锁再处理"))))
                return
            }
            total = document.numberOfPages
            var pages: [[PDFTextLayer.Line]] = []
            for number in 1...document.numberOfPages {
                let result = await runInBackground { () -> Result<[PDFTextLayer.Line], Error> in
                    Result { try document.page(at: number).map(PDFTextLayer.recognize) ?? [] }
                }
                guard !Task.isCancelled else { return }
                switch result {
                case .success(let lines):
                    pages.append(lines)
                case .failure(let error):
                    finish(.failure(PDFTools.Failure(message: String(localized: "识别文字失败：\(error.localizedDescription)"))))
                    return
                }
                done = number
            }
            let written = await runInBackground { () -> Result<Void, Error> in
                Result { try PDFTextLayer.write(document, pages: pages, to: destination) }
            }
            guard !Task.isCancelled else {
                try? FileManager.default.removeItem(at: destination)
                return
            }
            switch written {
            case .success:
                let characters = pages.joined().reduce(0) { $0 + $1.text.count }
                finish(.success(PDFTextLayer.Summary(pages: pages.count, characters: characters)))
            case .failure(let error):
                try? FileManager.default.removeItem(at: destination)
                finish(.failure(error as? PDFTools.Failure ?? PDFTools.Failure(message: error.localizedDescription)))
            }
        }
    }

    /// 停下来，不存文件
    func stop() {
        stopped = true
        task?.cancel()
    }

    /// 等识别做完或者停下（测试用）
    func waitUntilDone() async {
        await task?.value
    }
}

struct PDFTextLayerView: View {
    @ObservedObject var model: PDFTextLayerModel
    var onStop: () -> Void
    var onClose: () -> Void

    var body: some View {
        CardContainer(title: String(localized: "识别文字"), subtitle: model.pdf.lastPathComponent, width: 360, onClose: onClose) {
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: Double(model.done), total: Double(max(model.total, 1)))
                Text(model.progressText)
                    .font(.callout)
                    .monospacedDigit()
            }
            Text("认好以后存成「\(model.destination.lastPathComponent)」，页面和原来一样，文字能搜索、选中、复制。关掉卡片也会在后台接着认，认完了会提示")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("停止", action: onStop)
            }
        }
        .controlSize(.small)
    }
}
