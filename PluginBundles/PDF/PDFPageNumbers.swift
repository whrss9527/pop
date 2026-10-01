import AppKit
import CoreText
import PDFKit
import SwiftUI
@testable import Pop

/// 给 PDF 加页码：每页原样画进新的 PDF，再在底部居中、右下角或者右上角写上页码。
/// 前面几页（封面、目录）可以不标，第一个页码写几也能改；另存一份「原名 页码.pdf」。
enum PDFPageNumbers {
    enum Format: String, CaseIterable, Identifiable {
        case plain
        case page
        case fraction
        case dashed

        var id: Self { self }

        /// 「1」「第 1 页」「1 / 12」「- 1 -」
        func label(_ number: Int, of total: Int) -> String {
            switch self {
            case .plain: return "\(number)"
            case .page: return String(localized: "第 \(number) 页")
            case .fraction: return "\(number) / \(total)"
            case .dashed: return "- \(number) -"
            }
        }
    }

    enum Position: String, CaseIterable, Identifiable {
        case bottomCenter
        case bottomRight
        case topRight

        var id: Self { self }

        var title: String {
            switch self {
            case .bottomCenter: return String(localized: "底部居中")
            case .bottomRight: return String(localized: "右下角")
            case .topRight: return String(localized: "右上角")
            }
        }
    }

    struct Options: Equatable {
        var format = Format.plain
        var position = Position.bottomCenter
        /// 从第几页开始标（1 开始）；前面的封面、目录不标
        var firstPage = 1
        /// 标的第一页写几
        var startNumber = 1
    }

    /// 第 index 页（0 开始）写什么；不标的是 nil。「1 / 12」的总数按标了的最后一页算
    static func label(forPage index: Int, pageCount: Int, options: Options) -> String? {
        guard index + 1 >= options.firstPage, index < pageCount else { return nil }
        let number = options.startNumber + index + 1 - options.firstPage
        let total = options.startNumber + pageCount - options.firstPage
        return options.format.label(number, of: total)
    }

    /// 字号和离边的距离按页面大小：A4、Letter 上是 10 点、离边 28 点左右
    static func metrics(for size: CGSize) -> (fontSize: CGFloat, margin: CGFloat) {
        let side = min(size.width, size.height)
        return (min(max(side / 60, 7), 28), min(max(side * 0.047, 14), 90))
    }

    /// 页码这一行左下角（基线起点）放在哪
    static func origin(_ position: Position, pageSize: CGSize, textWidth: CGFloat, ascent: CGFloat, margin: CGFloat) -> CGPoint {
        switch position {
        case .bottomCenter: return CGPoint(x: (pageSize.width - textWidth) / 2, y: margin)
        case .bottomRight: return CGPoint(x: pageSize.width - margin - textWidth, y: margin)
        case .topRight: return CGPoint(x: pageSize.width - margin - textWidth, y: pageSize.height - margin - ascent)
        }
    }

    /// 在页面上写一个页码（深灰色）
    static func draw(_ label: String, position: Position, pageSize: CGSize, in context: CGContext) {
        let layout = metrics(for: pageSize)
        let font = CTFontCreateWithName("PingFangSC-Regular" as CFString, layout.fontSize, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.25, alpha: 1),
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: label, attributes: attributes))
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        context.saveGState()
        context.setTextDrawingMode(.fill)
        context.textMatrix = .identity
        context.textPosition = origin(position, pageSize: pageSize, textWidth: width, ascent: ascent, margin: layout.margin)
        CTLineDraw(line, context)
        context.restoreGState()
    }

    /// 另存一份加了页码的 PDF，返回标了几页
    @discardableResult
    static func write(_ pdf: URL, options: Options, to destination: URL) throws -> Int {
        let document = try PDFRedraw.open(pdf)
        let count = document.numberOfPages
        var numbered = 0
        try PDFRedraw.write(document, annotations: PDFDocument(url: pdf), to: destination) { index, size, context in
            guard let text = Self.label(forPage: index, pageCount: count, options: options) else { return }
            draw(text, position: options.position, pageSize: size, in: context)
            numbered += 1
        }
        return numbered
    }

    /// 预览：标了页码的第一页，长边 longSide 像素
    static func preview(_ document: CGPDFDocument, options: Options, longSide: CGFloat = 360, annotations: PDFDocument? = nil) -> CGImage? {
        let index = max(options.firstPage, 1) - 1
        guard let page = document.page(at: index + 1) else { return nil }
        return PDFRedraw.render(page, annotated: annotations?.page(at: index), longSide: longSide) { size, context in
            if let text = Self.label(forPage: index, pageCount: document.numberOfPages, options: options) {
                draw(text, position: options.position, pageSize: size, in: context)
            }
        }
    }
}

/// 加页码的卡片：左边是标了页码的第一页，右边选样式、位置、从第几页开始、第一个页码写几。样式和位置会记住
@MainActor
final class PDFPageNumbersModel: ObservableObject {
    static let formatKey = "pop.pdf.pageNumbers.format"
    static let positionKey = "pop.pdf.pageNumbers.position"

    let pdf: URL
    let pageCount: Int
    private let document: CGPDFDocument
    /// 同一个文件用 PDFKit 打开：预览时把批注画上
    private let annotations: PDFDocument?
    /// 卡片上选的样式、位置、从第几页开始、第一个页码：改的时候拉回能用的范围，记住样式和位置，重画预览。
    /// （不在 @Published 属性自己的 didSet 里改它：那样会再触发 didSet，一直递归下去）
    var options: PDFPageNumbers.Options {
        get { storedOptions }
        set {
            var value = newValue
            value.firstPage = min(max(value.firstPage, 1), pageCount)
            value.startNumber = min(max(value.startNumber, 0), 9999)
            UserDefaults.standard.set(value.format.rawValue, forKey: Self.formatKey)
            UserDefaults.standard.set(value.position.rawValue, forKey: Self.positionKey)
            guard value != storedOptions else { return }
            storedOptions = value
            drawPreview()
        }
    }
    @Published private var storedOptions: PDFPageNumbers.Options
    @Published private(set) var preview: CGImage?
    @Published private(set) var working = false
    @Published private(set) var message: String?

    init(pdf: URL) throws {
        document = try PDFRedraw.open(pdf)
        annotations = PDFDocument(url: pdf)
        self.pdf = pdf
        pageCount = document.numberOfPages
        var options = PDFPageNumbers.Options()
        let defaults = UserDefaults.standard
        options.format = defaults.string(forKey: Self.formatKey).flatMap(PDFPageNumbers.Format.init(rawValue:)) ?? .plain
        options.position = defaults.string(forKey: Self.positionKey).flatMap(PDFPageNumbers.Position.init(rawValue:)) ?? .bottomCenter
        storedOptions = options
        drawPreview()
    }

    /// 「共 18 页，标在第 2～18 页」
    var summary: String {
        options.firstPage >= pageCount
            ? String(localized: "共 \(pageCount) 页，只标第 \(pageCount) 页")
            : String(localized: "共 \(pageCount) 页，标在第 \(options.firstPage)～\(pageCount) 页")
    }

    /// 样式菜单里每一项：用这个 PDF 的页数写个例子
    func example(_ format: PDFPageNumbers.Format) -> String {
        format.label(options.startNumber, of: options.startNumber + pageCount - options.firstPage)
    }

    private func drawPreview() {
        preview = PDFPageNumbers.preview(document, options: options, annotations: annotations)
    }

    /// 存一份加了页码的，存好以后返回文件
    func apply() async -> URL? {
        guard !working else { return nil }
        working = true
        message = nil
        let pdf = pdf
        let options = options
        let destination = FileNames.available(in: pdf.deletingLastPathComponent(),
                                              base: pdf.deletingPathExtension().lastPathComponent + String(localized: " 页码"), extension: "pdf")
        let result = await runInBackground { () -> Result<Int, Error> in
            Result { try PDFPageNumbers.write(pdf, options: options, to: destination) }
        }
        working = false
        switch result {
        case .success:
            return destination
        case .failure(let error):
            try? FileManager.default.removeItem(at: destination)
            message = (error as? PDFTools.Failure)?.message ?? error.localizedDescription
            return nil
        }
    }
}

struct PDFPageNumbersView: View {
    @ObservedObject var model: PDFPageNumbersModel
    var onDone: (URL) -> Void
    var onClose: () -> Void

    var body: some View {
        CardContainer(title: String(localized: "加页码"), subtitle: model.pdf.lastPathComponent, width: 420, onClose: onClose) {
            HStack(alignment: .top, spacing: 14) {
                Group {
                    if let preview = model.preview {
                        Image(decorative: preview, scale: 2)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color.primary.opacity(0.15)))
                            .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
                    } else {
                        RoundedRectangle(cornerRadius: 2).fill(Color.primary.opacity(0.06))
                    }
                }
                .frame(width: 120, height: 160)
                VStack(alignment: .leading, spacing: 8) {
                    Picker("样式", selection: $model.options.format) {
                        ForEach(PDFPageNumbers.Format.allCases) { format in
                            Text(verbatim: model.example(format)).tag(format)
                        }
                    }
                    Picker("位置", selection: $model.options.position) {
                        ForEach(PDFPageNumbers.Position.allCases) { position in
                            Text(position.title).tag(position)
                        }
                    }
                    Stepper(value: $model.options.firstPage, in: 1...max(model.pageCount, 1)) {
                        Text("从第 \(model.options.firstPage) 页开始标")
                            .monospacedDigit()
                    }
                    Stepper(value: $model.options.startNumber, in: 0...9999) {
                        Text("第一个页码写 \(model.options.startNumber)")
                            .monospacedDigit()
                    }
                }
                .pickerStyle(.menu)
            }
            Text(model.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let message = model.message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            HStack {
                Text("另存一份，原来的 PDF 不动")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if model.working {
                    ProgressView()
                        .controlSize(.small)
                }
                Button("加页码") {
                    Task {
                        if let url = await model.apply() {
                            onDone(url)
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(model.working)
            }
        }
        .controlSize(.small)
    }
}
