import AppKit
import PDFKit
import XCTest
@testable import Pop

final class TextDiffTests: XCTestCase {
    func testLineChanges() {
        XCTAssertTrue(TextDiff.compare("a\nb", "a\r\nb").isIdentical)

        let result = TextDiff.compare("a\nb\nc", "a\nc\nd")
        XCTAssertEqual(result.lines.map(\.kind), [.same, .removed, .same, .added])
        XCTAssertEqual(result.lines.map(\.text), ["a", "b", "c", "d"])
        XCTAssertEqual(result.removedCount, 1)
        XCTAssertEqual(result.addedCount, 1)
        XCTAssertEqual(result.unifiedText, "  a\n- b\n  c\n+ d")
    }

    func testInlineChangesByWordAndCharacter() {
        let english = TextDiff.compare("hello world\nsame", "hello there\nsame")
        XCTAssertEqual(english.lines.map(\.kind), [.removed, .added, .same])
        XCTAssertEqual(english.lines[0].segments, [.init(text: "hello ", changed: false), .init(text: "world", changed: true)])
        XCTAssertEqual(english.lines[1].segments, [.init(text: "hello ", changed: false), .init(text: "there", changed: true)])

        // 中文按字比较
        let chinese = TextDiff.compare("今天天气很好", "今天天气不错")
        XCTAssertEqual(chinese.lines[0].segments, [.init(text: "今天天气", changed: false), .init(text: "很好", changed: true)])
        XCTAssertEqual(chinese.lines[1].segments, [.init(text: "今天天气", changed: false), .init(text: "不错", changed: true)])

        // 完全不一样的两行不逐词标，整行标出就好
        let different = TextDiff.compare("abc", "xyz")
        XCTAssertEqual(different.lines.map(\.segments), [[.init(text: "abc", changed: false)], [.init(text: "xyz", changed: false)]])
    }

    func testTokens() {
        XCTAssertEqual(TextDiff.tokens("hello, 世界 foo_bar1"), ["hello", ",", " ", "世", "界", " ", "foo_bar1"])
    }

    func testFoldingLongUnchangedStretches() {
        let head: [String] = (1...10).map { "\($0)" }
        let tail: [String] = (11...20).map { "\($0)" }
        let before: [String] = head + ["x"] + tail
        let after: [String] = head + ["y"] + tail
        let rows: [TextDiff.Row] = TextDiff.compare(before.joined(separator: "\n"), after.joined(separator: "\n")).rows()
        XCTAssertEqual(rows.count, 8)
        XCTAssertEqual(rows.first, TextDiff.Row.skipped(8))
        XCTAssertEqual(rows.last, TextDiff.Row.skipped(8))
        // 只隔着一两行相同的不折叠
        let short: [TextDiff.Row] = TextDiff.compare("a\nb\nc\nd", "a\nb\nc\ne").rows()
        XCTAssertEqual(short.count, 5)
        XCTAssertFalse(short.contains(TextDiff.Row.skipped(1)))
    }

    @MainActor
    func testPluginComparesWithClipboard() async {
        let context = PluginContext(settings: AppSettings(), openSettings: {})
        let content = ContentClassifier.classify(.text("hello there"))
        let outcome = await TextDiffPlugin(clipboardText: { "hello world\n" }).run(content, context: context)
        guard case .card(let card) = outcome else { return XCTFail("应该返回结果卡片") }
        XCTAssertEqual(card.diff?.removedCount, 1)
        XCTAssertEqual(card.copyText, "- hello world\n+ hello there")

        let same = await TextDiffPlugin(clipboardText: { "hello there" }).run(content, context: context)
        XCTAssertEqual(same, .done(toast: "两段文字完全相同"))
        let empty = await TextDiffPlugin(clipboardText: { nil }).run(content, context: context)
        guard case .failure = empty else { return XCTFail("剪贴板里没有文字时应该提示") }
    }
}

final class ColorPaletteTests: XCTestCase {
    /// 一张 sRGB 图，从左到右一段一段的纯色（每段 count 列，alpha 为 0 的是透明）
    private func image(_ columns: [(red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8, count: Int)], height: Int = 10) throws -> CGImage {
        let width = columns.reduce(0) { $0 + $1.count }
        var pixels: [UInt8] = []
        for _ in 0..<height {
            for column in columns {
                for _ in 0..<column.count {
                    pixels += [column.red, column.green, column.blue, column.alpha]
                }
            }
        }
        let provider = try XCTUnwrap(CGDataProvider(data: Data(pixels) as CFData))
        return try XCTUnwrap(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                                     space: try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)),
                                     bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                     provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    }

    func testMainColorsByArea() throws {
        let swatches = ColorPalette.extract(from: try image([(255, 0, 0, 255, 30), (0, 0, 255, 255, 18), (255, 255, 255, 255, 12)]))
        XCTAssertEqual(swatches.map(\.hex), ["#FF0000", "#0000FF", "#FFFFFF"])
        XCTAssertEqual(swatches[0].share, 0.5, accuracy: 0.01)
        XCTAssertEqual(swatches[1].share, 0.3, accuracy: 0.01)
        XCTAssertEqual(swatches[2].share, 0.2, accuracy: 0.01)
    }

    func testCloseShadesMergeAndTransparencyIsIgnored() throws {
        // 两种很接近的红算一种，排在绿色前面
        let swatches = ColorPalette.extract(from: try image([(250, 10, 10, 255, 20), (240, 20, 20, 255, 20), (0, 128, 0, 255, 20)]))
        XCTAssertEqual(swatches.map(\.hex), ["#F50F0F", "#008000"])
        // 透明的部分不算
        let halfClear = ColorPalette.extract(from: try image([(255, 0, 0, 255, 10), (0, 0, 0, 0, 30)]))
        XCTAssertEqual(halfClear.map(\.hex), ["#FF0000"])
        XCTAssertEqual(halfClear.first?.share ?? 0, 1, accuracy: 0.001)
        XCTAssertTrue(ColorPalette.extract(from: try image([(0, 0, 0, 0, 10)])).isEmpty)
    }
}

final class ScanCodeTests: XCTestCase {
    func testWiFiCodes() {
        XCTAssertEqual(WiFiCode.parse(#"WIFI:T:WPA;S:My\;Net;P:pa\:ss;;"#),
                       WiFiCode.Network(ssid: "My;Net", password: "pa:ss", security: "WPA", hidden: false))
        XCTAssertEqual(WiFiCode.parse("WIFI:S:Cafe;T:nopass;H:true;;"),
                       WiFiCode.Network(ssid: "Cafe", password: nil, security: nil, hidden: true))
        XCTAssertNil(WiFiCode.parse("WIFI:T:WPA;P:x;;"))
        XCTAssertNil(WiFiCode.parse("https://example.com"))
    }

    func testResultCards() throws {
        let link = QRCode.card(for: ["https://example.com/pop"])
        XCTAssertEqual(link.buttons.first?.action, .open(try XCTUnwrap(URL(string: "https://example.com/pop"))))
        XCTAssertEqual(link.copyText, "https://example.com/pop")
        let wifi = QRCode.card(for: ["WIFI:S:Home;T:WPA;P:secret;;"])
        XCTAssertEqual(wifi.title, "Wi-Fi 二维码")
        XCTAssertEqual(wifi.rows.map(\.value), ["Home", "secret", "WPA"])
        XCTAssertEqual(QRCode.card(for: ["A", "B"]).body, "A\nB")
    }
}

final class PDFToolsTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "pop-pdf-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    /// 一张纯色 PNG，没有分辨率信息，按 72 dpi 算，点数和像素一样
    private func writePNG(_ name: String, width: Int, height: Int) throws -> URL {
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                                                 samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                                 bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.systemBlue.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: height)).fill()
        NSGraphicsContext.restoreGraphicsState()
        let url = folder.appending(path: name)
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: url)
        return url
    }

    func testCombineImagesAndPDFs() throws {
        let wide = try writePNG("a.png", width: 200, height: 100)
        let tall = try writePNG("b.png", width: 100, height: 200)
        let twoPages = folder.appending(path: "two.pdf")
        XCTAssertEqual(try PDFTools.combine([wide, tall], into: twoPages), 2)
        let merged = folder.appending(path: "merged.pdf")
        XCTAssertEqual(try PDFTools.combine([twoPages, wide], into: merged), 3)
        XCTAssertEqual(PDFDocument(url: merged)?.pageCount, 3)
        XCTAssertThrowsError(try PDFTools.combine([folder.appending(path: "missing.png")], into: folder.appending(path: "x.pdf")))
    }

    func testExportPagesAsImages() throws {
        let pdf = folder.appending(path: "doc.pdf")
        try PDFTools.combine([try writePNG("a.png", width: 200, height: 100), try writePNG("b.png", width: 100, height: 200)],
                             into: pdf)
        let pages = try PDFTools.exportPages(of: pdf, to: folder.appending(path: "pages"), scale: 1)
        XCTAssertEqual(pages.map(\.lastPathComponent), ["doc-01.png", "doc-02.png"])
        let first = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: pages[0])))
        XCTAssertEqual(first.pixelsWide, 200)
        XCTAssertEqual(first.pixelsHigh, 100)
        let second = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: pages[1])))
        XCTAssertEqual(second.pixelsWide, 100)
        XCTAssertEqual(second.pixelsHigh, 200)
    }

    func testNaturalOrder() {
        let urls = ["p10.png", "p2.png", "p1.png"].map { URL(fileURLWithPath: "/tmp/\($0)") }
        XCTAssertEqual(PDFTools.sorted(urls).map(\.lastPathComponent), ["p1.png", "p2.png", "p10.png"])
    }

    @MainActor
    func testPluginCombinesOrSummarizes() async throws {
        let wide = try writePNG("a.png", width: 200, height: 100)
        let tall = try writePNG("b.png", width: 100, height: 200)
        let context = PluginContext(settings: AppSettings(), openSettings: {})
        final class Revealed {
            var urls: [URL] = []
        }
        let revealed = Revealed()
        let plugin = PDFPlugin(reveal: { revealed.urls = $0 })
        XCTAssertTrue(plugin.info.canHandle(ContentClassifier.classify(.files([wide, tall]))))
        XCTAssertFalse(plugin.info.canHandle(ContentClassifier.classify(.files([folder.appending(path: "notes.txt")]))))

        let outcome = await plugin.run(ContentClassifier.classify(.files([tall, wide])), context: context)
        XCTAssertEqual(outcome, .done(toast: "已合成 2 页的 PDF"))
        XCTAssertEqual(revealed.urls.map(\.lastPathComponent), ["a 等 2 个文件.pdf"])

        // 只选了一个 PDF：列出页数，可以把每页存成图片
        let summary = await plugin.run(ContentClassifier.classify(.files(revealed.urls)), context: context)
        guard case .card(let card) = summary else { return XCTFail("应该返回结果卡片") }
        XCTAssertEqual(card.buttons.first?.action, .exportPDFPages(revealed.urls[0]))
        XCTAssertEqual(card.buttons.last?.action, .compressPDF(revealed.urls[0]))
        XCTAssertTrue(card.detail?.hasPrefix("2 页") == true, card.detail ?? "")
    }

    func testCompressShrinksImages() throws {
        // 一页上放一张 2 倍像素的杂色图（CoreGraphics 按无损压缩存），压缩后小很多，页数不变
        let width = 1200
        let height = 900
        let bitmap = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                             space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        let bytes = try XCTUnwrap(bitmap.data?.assumingMemoryBound(to: UInt8.self))
        var seed: UInt32 = 7
        for index in 0..<(width * height * 4) {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            bytes[index] = UInt8(truncatingIfNeeded: seed >> 24)
        }
        let image = try XCTUnwrap(bitmap.makeImage())
        let pdf = folder.appending(path: "扫描件.pdf")
        var box = CGRect(x: 0, y: 0, width: width / 2, height: height / 2)
        let context = try XCTUnwrap(CGContext(pdf as CFURL, mediaBox: &box, nil))
        context.beginPDFPage(nil)
        context.draw(image, in: box)
        context.endPDFPage()
        context.closePDF()

        let compression = try PDFTools.compress(pdf)
        XCTAssertEqual(compression.url.lastPathComponent, "扫描件 压缩.pdf")
        XCTAssertEqual(PDFDocument(url: compression.url)?.pageCount, 1)
        XCTAssertTrue(compression.worthwhile, "\(compression.before) → \(compression.after)")
    }
}

@MainActor
final class KeepAwakeTests: XCTestCase {
    func testTitlesAndStatus() throws {
        XCTAssertEqual(KeepAwake.title(minutes: 30), "30 分钟")
        XCTAssertEqual(KeepAwake.title(minutes: 60), "1 小时")
        XCTAssertEqual(KeepAwake.title(minutes: 90), "1 小时 30 分钟")

        let awake = KeepAwake()
        XCTAssertNil(awake.statusText())
        XCTAssertTrue(awake.start(minutes: 30))
        XCTAssertTrue(awake.isActive)
        let status = try XCTUnwrap(awake.statusText())
        XCTAssertTrue(status.contains("还剩 30 分钟"), status)
        awake.stop()
        XCTAssertFalse(awake.isActive)
        XCTAssertNil(awake.endsAt)

        XCTAssertTrue(awake.start(minutes: nil))
        XCTAssertEqual(awake.statusText(), "一直保持唤醒，直到手动停止或退出 Pop")
        awake.stop()
    }

    func testPluginOffersDurations() async {
        let outcome = await KeepAwakePlugin().run(.empty, context: PluginContext(settings: AppSettings(), openSettings: {}))
        guard case .card(let card) = outcome else { return XCTFail("应该返回结果卡片") }
        XCTAssertEqual(card.buttons.prefix(4).map(\.title), ["30 分钟", "1 小时", "2 小时", "一直保持"])
        XCTAssertEqual(card.buttons[1].action, .keepAwake(minutes: 60))
    }
}
