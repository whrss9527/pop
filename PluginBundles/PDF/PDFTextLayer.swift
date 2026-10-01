import AppKit
import CoreText
import PDFKit
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

    /// Vision 给的位置（0～1，左下角是原点）换成页面上的点
    static func lines(_ found: [(text: String, box: CGRect)], pageSize: CGSize) -> [Line] {
        found.compactMap { item in
            let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, item.box.width > 0, item.box.height > 0 else { return nil }
            return Line(text: text, rect: CGRect(x: item.box.minX * pageSize.width, y: item.box.minY * pageSize.height,
                                                 width: item.box.width * pageSize.width, height: item.box.height * pageSize.height))
        }
    }

    /// 认出一页上的字（在后台线程调用）；annotated 是同一页用 PDFKit 打开的样子，批注上的字也认
    static func recognize(_ page: CGPDFPage, annotated: PDFPage? = nil) throws -> [Line] {
        // 长边 2400 像素左右，Vision 认得清楚
        guard let image = PDFRedraw.render(page, annotated: annotated, longSide: 2400) else { return [] }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = languages
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        let found = (request.results ?? []).compactMap { observation -> (text: String, box: CGRect)? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return (candidate.string, observation.boundingBox)
        }
        return lines(found, pageSize: PDFRedraw.displaySize(of: page))
    }

    /// 写成新的 PDF：每页先原样画上原来的页面（批注一起画进去），再在每行的位置写上看不见的文字
    static func write(_ document: CGPDFDocument, pages: [[Line]], annotations: PDFDocument? = nil, to url: URL) throws {
        try PDFRedraw.write(document, annotations: annotations, to: url) { index, _, context in
            drawInvisible(index < pages.count ? pages[index] : [], in: context)
        }
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
            let document: CGPDFDocument
            do {
                document = try PDFRedraw.open(pdf)
            } catch {
                finish(.failure(error as? PDFTools.Failure ?? PDFTools.Failure(message: error.localizedDescription)))
                return
            }
            total = document.numberOfPages
            // 同一个文件用 PDFKit 打开：签名、图章这些批注一起认、一起画进新文件
            let annotations = PDFDocument(url: pdf)
            var pages: [[PDFTextLayer.Line]] = []
            for number in 1...document.numberOfPages {
                let result = await runInBackground { () -> Result<[PDFTextLayer.Line], Error> in
                    Result {
                        try document.page(at: number).map { try PDFTextLayer.recognize($0, annotated: annotations?.page(at: number - 1)) } ?? []
                    }
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
                Result { try PDFTextLayer.write(document, pages: pages, annotations: annotations, to: destination) }
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
