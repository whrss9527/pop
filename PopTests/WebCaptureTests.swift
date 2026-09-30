import PDFKit
import XCTest
@testable import Pop

final class WebCaptureTests: XCTestCase {
    func testFileNames() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/news/1"))
        XCTAssertEqual(WebCapture.fileName(title: "发布说明 / 0.29.0: 新功能", url: url), "发布说明 - 0.29.0- 新功能")
        XCTAssertEqual(WebCapture.fileName(title: "  ", url: url), "example.com")
        XCTAssertEqual(WebCapture.fileName(title: nil, url: url), "example.com")
        XCTAssertEqual(WebCapture.fileName(title: String(repeating: "长", count: 200), url: url).count, 80)
    }

    /// 不联网：直接给一段很长的 HTML（里面有一张地址写在 data-src 里的图片），整页存成一页 PDF，再画成长图
    @MainActor
    func testSavesTheWholePageAsOnePDFPage() async throws {
        let html = """
        <html><head><meta charset="utf-8"><title>存档测试</title></head>
        <body style="margin:0"><h1>网页存档测试 TopMarker</h1>
        <img data-src="data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7" width="10" height="10">
        <div style="height:2600px"></div><p>页面最下面 BottomMarker</p></body></html>
        """
        let saved = try await WebCapture.load(nil, html: html, timeout: 30)
        XCTAssertEqual(saved.title, "存档测试")
        let document = try XCTUnwrap(PDFDocument(data: saved.pdf))
        XCTAssertEqual(document.pageCount, 1)
        let page = try XCTUnwrap(document.page(at: 0))
        let bounds = page.bounds(for: .mediaBox)
        // 显示滚动条的 Mac 上会窄一条滚动条的宽度
        XCTAssertEqual(bounds.width, WebCapture.pageWidth, accuracy: 20)
        // 整页都在，不只是第一屏
        XCTAssertGreaterThan(bounds.height, 2600)
        let text = page.string ?? ""
        XCTAssertTrue(text.contains("TopMarker"), text)
        XCTAssertTrue(text.contains("BottomMarker"), text)

        let png = try WebCapture.image(fromPDF: saved.pdf)
        let image = try XCTUnwrap(NSBitmapImageRep(data: png))
        XCTAssertEqual(CGFloat(image.pixelsWide), bounds.width * 1.5, accuracy: 2)
        XCTAssertGreaterThan(image.pixelsHigh, 3900)
    }

    func testVeryLongPagesAreScaledDown() throws {
        // 1200×40000 点的一页：按高度上限缩小
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 1200, height: 40_000)
        let consumer = try XCTUnwrap(CGDataConsumer(data: data as CFMutableData))
        let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &box, nil))
        context.beginPDFPage(nil)
        context.setFillColor(CGColor(gray: 0.5, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1200, height: 100))
        context.endPDFPage()
        context.closePDF()
        let png = try WebCapture.image(fromPDF: data as Data)
        let image = try XCTUnwrap(NSBitmapImageRep(data: png))
        XCTAssertLessThanOrEqual(CGFloat(image.pixelsHigh), WebCapture.maxImageHeight + 1)
        XCTAssertLessThanOrEqual(CGFloat(image.pixelsWide * image.pixelsHigh), WebCapture.maxImagePixels * 1.01)
        XCTAssertThrowsError(try WebCapture.image(fromPDF: Data("不是 PDF".utf8)))
    }

    @MainActor
    func testPluginOffersBothFormats() async throws {
        let plugin = WebCapturePlugin()
        XCTAssertTrue(plugin.info.canHandle(ContentClassifier.classify(.text("https://example.com/a"))))
        XCTAssertFalse(plugin.info.canHandle(ContentClassifier.classify(.text("你好"))))
        let url = try XCTUnwrap(URL(string: "https://example.com/a"))
        let outcome = await plugin.run(ContentClassifier.classify(.text("https://example.com/a")),
                                       context: PluginContext(settings: AppSettings(), openSettings: {}))
        guard case .card(let card) = outcome else { return XCTFail("应该返回结果卡片") }
        XCTAssertEqual(card.buttons.map(\.action), [.captureWeb(url, .pdf), .captureWeb(url, .image), .captureWeb(url, .markdown)])
        let mail = await plugin.run(ContentClassifier.classify(.text("pop@example.com")),
                                    context: PluginContext(settings: AppSettings(), openSettings: {}))
        guard case .failure = mail else { return XCTFail("邮箱不是网页") }
    }

    func testMarkdownStartsWithTheTitleAndSource() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/post"))
        // 正文自己有一级标题：原文链接放在它下面
        XCTAssertEqual(WebCapture.markdown(title: "Hello · Blog", url: url, html: "<article><h1>Hello</h1><p>World</p></article>"),
                       "# Hello\n\n原文：<https://example.com/post>\n\nWorld\n")
        // 没有：用网页标题，没有标题时用主机名
        XCTAssertEqual(WebCapture.markdown(title: "Hi", url: url, html: "<p>World</p>"), "# Hi\n\n原文：<https://example.com/post>\n\nWorld\n")
        XCTAssertEqual(WebCapture.markdown(title: " ", url: url, html: "<p>World</p>"), "# example.com\n\n原文：<https://example.com/post>\n\nWorld\n")
        XCTAssertNil(WebCapture.markdown(title: "Hi", url: url, html: "<div> </div>"))
    }

    /// 不联网：给一段有导航、侧栏、页脚的 HTML，只留下正文，相对地址换成完整的网址
    @MainActor
    func testArticleKeepsTheMainTextWithFullLinks() async throws {
        let url = try XCTUnwrap(URL(string: "https://pop.invalid/blog/post"))
        let paragraph = String(repeating: "Pop keeps only the main text of a page. ", count: 8)
        let html = """
        <html><head><meta charset="utf-8"><title>Post · Blog</title></head><body>
        <nav><a href="/">Home</a> <a href="/about">AboutMarker</a></nav>
        <article><h1>Post</h1><p>\(paragraph)<a href="../docs/start">start here</a></p>
        <img data-src="images/pic.png" alt="pic"><p style="display:none">HiddenMarker</p></article>
        <aside>RelatedMarker</aside><footer>FooterMarker</footer>
        </body></html>
        """
        let article = try await WebCapture.loadArticle(url, html: html, timeout: 30)
        XCTAssertEqual(article.title, "Post · Blog")
        for marker in ["AboutMarker", "RelatedMarker", "FooterMarker", "HiddenMarker"] {
            XCTAssertFalse(article.html.contains(marker), marker)
        }
        let markdown = try XCTUnwrap(WebCapture.markdown(title: article.title, url: url, html: article.html))
        XCTAssertTrue(markdown.hasPrefix("# Post\n\n原文：<https://pop.invalid/blog/post>\n\n"), markdown)
        XCTAssertTrue(markdown.contains("[start here](https://pop.invalid/docs/start)"), markdown)
        XCTAssertTrue(markdown.contains("https://pop.invalid/blog/images/pic.png"), markdown)
    }
}
