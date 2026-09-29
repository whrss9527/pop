import AppKit
import XCTest
@testable import Pop

final class LinkInspectorTests: XCTestCase {
    private func url(_ string: String) throws -> URL {
        try XCTUnwrap(URL(string: string))
    }

    func testCleaning() throws {
        XCTAssertEqual(LinkInspector.cleaned(try url("https://example.com/a?id=3&utm_source=x&utm_medium=y"))?.absoluteString,
                       "https://example.com/a?id=3")
        XCTAssertEqual(LinkInspector.cleaned(try url("https://example.com/?fbclid=abc"))?.absoluteString, "https://example.com/")
        // 只在某些网站上算跟踪参数
        XCTAssertEqual(LinkInspector.cleaned(try url("https://www.youtube.com/watch?v=abc&si=xyz"))?.absoluteString,
                       "https://www.youtube.com/watch?v=abc")
        XCTAssertNil(LinkInspector.cleaned(try url("https://example.com/?si=1")))
        XCTAssertNil(LinkInspector.cleaned(try url("https://example.com/search?q=pop")))
        XCTAssertNil(LinkInspector.cleaned(try url("https://example.com/")))
    }

    func testRows() throws {
        let rows = LinkInspector.rows(for: try url("https://example.com:8080/path/to?q=%E4%BD%A0%E5%A5%BD&n=1#top"))
        XCTAssertEqual(rows.map(\.label), ["协议", "主机", "端口", "路径", "q", "n", "片段"])
        XCTAssertEqual(rows.first { $0.label == "q" }?.value, "你好")
        XCTAssertEqual(rows.first { $0.label == "路径" }?.value, "/path/to")
    }

    @MainActor
    func testPlugin() async throws {
        let content = ContentClassifier.classify(.text("https://example.com/a?id=3&utm_campaign=x"))
        let outcome = await LinkInspectPlugin().run(content, context: PluginContext(settings: AppSettings(), openSettings: {}))
        guard case .card(let card) = outcome else { return XCTFail("应该返回结果卡片") }
        XCTAssertEqual(card.body, "https://example.com/a?id=3")
        XCTAssertEqual(card.replaceText, "https://example.com/a?id=3")
        XCTAssertEqual(card.buttons.first?.action, .copy("https://example.com/a?id=3"))
    }
}

final class JWTDecoderTests: XCTestCase {
    private let sample = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"
    private let expired = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJodHRwczovL2F1dGguZXhhbXBsZS5jb20iLCJhdWQiOlsicG9wIiwid2ViIl0sImV4cCI6MTAwMDAwMDAwMCwibmJmIjo5OTk5OTAwMDB9.sig"
    private let future = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJleHAiOjQxMDI0NDQ4MDB9."

    func testDecoding() throws {
        let token = try XCTUnwrap(JWTDecoder.decode(sample))
        XCTAssertEqual(token.algorithm, "HS256")
        XCTAssertTrue(token.payload.contains("\"name\" : \"John Doe\""))
        let utc = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let rows = JWTDecoder.rows(for: token, timeZone: utc)
        XCTAssertEqual(rows.first { $0.label == "主题" }?.value, "1234567890")
        XCTAssertEqual(rows.first { $0.label == "签发时间" }?.value, "2018-01-18 01:30:22")

        let old = try XCTUnwrap(JWTDecoder.decode(expired))
        let oldRows = JWTDecoder.rows(for: old, timeZone: utc)
        XCTAssertEqual(oldRows.first { $0.label == "受众" }?.value, "pop, web")
        XCTAssertEqual(oldRows.first { $0.label == "签发者" }?.value, "https://auth.example.com")
        XCTAssertEqual(oldRows.first { $0.label == "过期时间" }?.value.hasSuffix("（已过期）"), true)

        let later = try XCTUnwrap(JWTDecoder.decode(future))
        XCTAssertEqual(JWTDecoder.rows(for: later).first { $0.label == "过期时间" }?.value.hasSuffix("过期）"), true)
        XCTAssertNil(JWTDecoder.decode("eyJhbGciOiJIUzI1NiJ9.bm90IGpzb24.sig"))
        XCTAssertNil(JWTDecoder.decode("hello.world"))
    }

    func testTokensAreNotTranslated() {
        // 令牌、哈希只当普通文字，不会被「外文直接翻译」接走；JWT 解码出现在圆盘上
        let content = ContentClassifier.classify(.text(sample))
        XCTAssertEqual(content.kinds, [.text])
        XCTAssertTrue(JWTPlugin().info.canHandle(content))
        XCTAssertEqual(ContentClassifier.classify(.text("9f86d081884c7d659a2feaa0c55ad015a3bf4f1b")).kinds, [.text])
        XCTAssertFalse(JWTPlugin().info.canHandle(ContentClassifier.classify(.text("hello world"))))
        // 普通的长单词不受影响
        XCTAssertTrue(ContentClassifier.classify(.text("Supercalifragilistic")).kinds.contains(.foreignText))
    }
}

final class MarkdownRichTextTests: XCTestCase {
    func testRendering() throws {
        let rich = try XCTUnwrap(MarkdownRichText.render("# 标题\n\n**粗体**和 `code`\n\n- 一\n- 二\n\n1. 甲\n2. 乙"))
        let text = rich.string
        XCTAssertTrue(text.hasPrefix("标题\n"), text)
        XCTAssertTrue(text.contains("粗体和 code"), text)
        XCTAssertTrue(text.contains("• 一\n• 二"), text)
        XCTAssertTrue(text.contains("1. 甲\n2. 乙"), text)

        let titleFont = try XCTUnwrap(rich.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        XCTAssertGreaterThan(titleFont.pointSize, 13)
        XCTAssertTrue(titleFont.fontDescriptor.symbolicTraits.contains(.bold))
        let boldIndex = (text as NSString).range(of: "粗体").location
        let boldFont = try XCTUnwrap(rich.attribute(.font, at: boldIndex, effectiveRange: nil) as? NSFont)
        XCTAssertTrue(boldFont.fontDescriptor.symbolicTraits.contains(.bold))
        let codeIndex = (text as NSString).range(of: "code").location
        let codeFont = try XCTUnwrap(rich.attribute(.font, at: codeIndex, effectiveRange: nil) as? NSFont)
        XCTAssertTrue(codeFont.fontDescriptor.symbolicTraits.contains(.monoSpace))
    }

    func testOnlyOfferedForMarkdown() {
        let info = MarkdownCopyPlugin().info
        for markdown in ["# Title", "**bold** text", "- item\n- item", "1. first\n2. second", "see [Pop](https://example.com)", "run `ls`"] {
            XCTAssertTrue(info.canHandle(ContentClassifier.classify(.text(markdown))), markdown)
        }
        for plain in ["hello world", "今天天气很好", "a - b", "C# is fine"] {
            XCTAssertFalse(info.canHandle(ContentClassifier.classify(.text(plain))), plain)
        }
    }
}
