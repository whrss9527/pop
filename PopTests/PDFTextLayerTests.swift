import CoreText
import PDFKit
import XCTest
@testable import Pop

final class PDFTextLayerTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "PDFTextLayerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    func testDecidesWhenAPDFNeedsATextLayer() {
        XCTAssertTrue(PDFTextLayer.needsTextLayer(characters: 0, pages: 3))
        // 扫描件上零星几个字（页眉、水印）也算没有
        XCTAssertTrue(PDFTextLayer.needsTextLayer(characters: 59, pages: 3))
        XCTAssertFalse(PDFTextLayer.needsTextLayer(characters: 60, pages: 3))
        XCTAssertTrue(PDFTextLayer.needsTextLayer(characters: 5, pages: 0))
    }

    func testConvertsVisionBoxesToPagePoints() {
        let lines = PDFTextLayer.lines([("  合同编号 2026-001 ", CGRect(x: 0.25, y: 0.5, width: 0.5, height: 0.125)),
                                        (" ", CGRect(x: 0, y: 0, width: 0.5, height: 0.5)),
                                        ("空的框", .zero)], pageSize: CGSize(width: 600, height: 800))
        XCTAssertEqual(lines, [PDFTextLayer.Line(text: "合同编号 2026-001", rect: CGRect(x: 150, y: 400, width: 300, height: 100))])
    }

    func testWritesInvisibleTextWhereItWasRecognized() throws {
        // 一页「扫描件」：只有一张图，没有文字层
        let pdf = try scannedPDF(name: "扫描.pdf", lines: ["Pop searchable scan 2026"])
        XCTAssertEqual(PDFDocument(url: pdf)?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "", "")
        let document = try XCTUnwrap(CGPDFDocument(pdf as CFURL))
        let output = folder.appending(path: "out.pdf")
        let line = PDFTextLayer.Line(text: "Hello layer", rect: CGRect(x: 72, y: 600, width: 300, height: 30))
        try PDFTextLayer.write(document, pages: [[line]], to: output)

        let written = try XCTUnwrap(PDFDocument(url: output))
        XCTAssertEqual(written.pageCount, 1)
        XCTAssertEqual(written.page(at: 0)?.bounds(for: .mediaBox).size, CGSize(width: 612, height: 792))
        XCTAssertTrue(written.string?.contains("Hello layer") == true, written.string ?? "")
        // 搜到的位置就是写进去的那一行
        let page = try XCTUnwrap(written.page(at: 0))
        let found = try XCTUnwrap(written.findString("layer", withOptions: []).first)
        let bounds = found.bounds(for: page)
        XCTAssertEqual(bounds.midY, 615, accuracy: 15)
        XCTAssertGreaterThan(bounds.minX, 150)
        XCTAssertLessThan(bounds.maxX, 390)
    }

    @MainActor
    func testMakesAScannedPDFSearchable() async throws {
        let pdf = try scannedPDF(name: "合同扫描.pdf", lines: ["Pop searchable scan 2026"], rotatedPage: "Rotated page 42")
        XCTAssertEqual(PDFDocument(url: pdf)?.page(at: 1)?.rotation, 90)
        let destination = folder.appending(path: "合同扫描 可搜索.pdf")
        let model = PDFTextLayerModel(pdf: pdf, destination: destination)
        XCTAssertEqual(model.progressText, "正在打开 PDF…")
        var result: Result<PDFTextLayer.Summary, PDFTools.Failure>?
        model.start { result = $0 }
        await model.waitUntilDone()
        let summary = try XCTUnwrap(result).get()
        XCTAssertEqual(summary.pages, 2)
        XCTAssertGreaterThan(summary.characters, 20)
        XCTAssertEqual(model.done, 2)
        XCTAssertEqual(model.total, 2)

        let output = try XCTUnwrap(PDFDocument(url: destination))
        XCTAssertEqual(output.pageCount, 2)
        // 转过的那页按显示的方向存成横的
        XCTAssertEqual(output.page(at: 1)?.bounds(for: .mediaBox).size, CGSize(width: 792, height: 612))
        let first = output.page(at: 0)?.string ?? ""
        XCTAssertTrue(first.localizedCaseInsensitiveContains("searchable"), first)
        XCTAssertTrue(first.contains("2026"), first)
        let second = output.page(at: 1)?.string ?? ""
        XCTAssertTrue(second.localizedCaseInsensitiveContains("rotated"), second)
        // 原来的文件不动
        XCTAssertEqual(PDFDocument(url: pdf)?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "", "")
    }

    @MainActor
    func testStoppingWritesNothing() async throws {
        let pdf = try scannedPDF(name: "很长.pdf", lines: ["Stop me"])
        let destination = folder.appending(path: "很长 可搜索.pdf")
        let model = PDFTextLayerModel(pdf: pdf, destination: destination)
        var finished = false
        model.start { _ in finished = true }
        model.stop()
        await model.waitUntilDone()
        XCTAssertTrue(model.stopped)
        XCTAssertFalse(finished)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)))
    }

    @MainActor
    func testUnreadableFileFails() async {
        let model = PDFTextLayerModel(pdf: folder.appending(path: "没有这个.pdf"), destination: folder.appending(path: "x.pdf"))
        var result: Result<PDFTextLayer.Summary, PDFTools.Failure>?
        model.start { result = $0 }
        await model.waitUntilDone()
        XCTAssertEqual(result, Result<PDFTextLayer.Summary, PDFTools.Failure>.failure(PDFTools.Failure(message: "读不了「没有这个.pdf」")))
    }

    @MainActor
    func testPDFCardOffersRecognitionOnlyWithoutText() async throws {
        let context = PluginContext(settings: AppSettings(), openSettings: {})
        let plugin = PDFPlugin(reveal: { _ in })
        let scanned = try scannedPDF(name: "扫描件.pdf", lines: ["Scan"])
        guard case .card(let card) = await plugin.run(ContentClassifier.classify(.files([scanned])), context: context) else {
            return XCTFail("应该返回结果卡片")
        }
        XCTAssertEqual(Array(card.buttons.map(\.title).prefix(2)), ["每页存成图片", "识别文字"])
        XCTAssertTrue(card.detail?.contains("没有文字层") == true, card.detail ?? "")

        let text = try textPDF(name: "文字.pdf", text: "这是一份本来就有文字层的 PDF，里面的字可以直接搜索和复制，不用再识别。")
        guard case .card(let textCard) = await plugin.run(ContentClassifier.classify(.files([text])), context: context) else {
            return XCTFail("应该返回结果卡片")
        }
        XCTAssertFalse(textCard.buttons.contains { $0.title == "识别文字" })
    }

    // MARK: - 做测试用的 PDF

    /// 「扫描件」：每页只有一张写着字的图片。rotatedPage 不为 nil 时再加一页：内容横着画、页面顺时针转 90 度，看起来是正的
    private func scannedPDF(name: String, lines: [String], rotatedPage: String? = nil) throws -> URL {
        let raw = folder.appending(path: "raw-\(name)")
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        let context = try XCTUnwrap(CGContext(raw as CFURL, mediaBox: &box, nil))
        context.beginPage(mediaBox: &box)
        context.draw(try XCTUnwrap(Self.textImage(lines, size: CGSize(width: 612, height: 792))), in: box)
        context.endPage()
        if let rotatedPage {
            context.beginPage(mediaBox: &box)
            // 显示时的 (x, y) 在页面上是 (612 - y, x)
            context.concatenate(CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 612, ty: 0))
            context.draw(try XCTUnwrap(Self.textImage([rotatedPage], size: CGSize(width: 792, height: 612))), in: CGRect(x: 0, y: 0, width: 792, height: 612))
            context.endPage()
        }
        context.closePDF()
        let url = folder.appending(path: name)
        let document = try XCTUnwrap(PDFDocument(url: raw))
        if rotatedPage != nil {
            document.page(at: 1)?.rotation = 90
        }
        XCTAssertTrue(document.write(to: url))
        return url
    }

    /// 本来就有文字层的 PDF
    private func textPDF(name: String, text: String) throws -> URL {
        let url = folder.appending(path: name)
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        let context = try XCTUnwrap(CGContext(url as CFURL, mediaBox: &box, nil))
        context.beginPage(mediaBox: &box)
        let font = CTFontCreateWithName("PingFangSC-Regular" as CFString, 12, nil)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]))
        context.textPosition = CGPoint(x: 40, y: 700)
        CTLineDraw(line, context)
        context.endPage()
        context.closePDF()
        return url
    }

    /// 白底黑字的图片，一行一段，40 点的 Helvetica，两倍像素
    private static func textImage(_ lines: [String], size: CGSize, scale: CGFloat = 2) -> CGImage? {
        let width = Int(size.width * scale)
        let height = Int(size.height * scale)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        let font = CTFontCreateWithName("Helvetica" as CFString, 40, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1),
        ]
        for (index, text) in lines.enumerated() {
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
            context.textPosition = CGPoint(x: 60, y: size.height - 140 - CGFloat(index) * 70)
            CTLineDraw(line, context)
        }
        return context.makeImage()
    }
}
