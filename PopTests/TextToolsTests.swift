import AppKit
import XCTest
@testable import Pop

final class HTMLToMarkdownTests: XCTestCase {
    private func convert(_ html: String) -> String? {
        HTMLToMarkdown.convert(html)
    }

    func testHeadingsParagraphsAndInlineFormatting() {
        XCTAssertEqual(convert(#"<h1>Title</h1><p>Some <strong>bold</strong> and <em>italic</em> text with a <a href="https://example.com/a">link</a>.</p>"#),
                       "# Title\n\nSome **bold** and *italic* text with a [link](https://example.com/a).")
        // 标记要紧贴文字，空格挪到外面
        XCTAssertEqual(convert("<p>a<b> bold </b>b</p>"), "a **bold** b")
        XCTAssertEqual(convert("<p><del>old</del> new<br>next line</p>"), "~~old~~ new\nnext line")
        XCTAssertEqual(convert("<p>One<p>Two"), "One\n\nTwo")
        XCTAssertEqual(convert("<p>A&nbsp;&amp;&nbsp;B</p>"), "A & B")
        XCTAssertEqual(convert("<style>p { color: red }</style><p>Hi</p><script>run()</script>"), "Hi")
    }

    func testLists() {
        XCTAssertEqual(convert("<ul><li>One</li><li>Two<ul><li>Nested</li></ul></li></ul><ol start=\"3\"><li>Three</li><li>Four</li></ol>"),
                       "- One\n- Two\n  - Nested\n\n3. Three\n4. Four")
        XCTAssertEqual(convert(#"<ul><li><input type="checkbox" checked>Done</li><li><input type="checkbox"> Todo</li></ul>"#),
                       "- [x] Done\n- [ ] Todo")
    }

    func testCodeQuotesRulesAndTables() {
        XCTAssertEqual(convert("<pre><code class=\"language-swift\">let x = 1\nprint(x)</code></pre><p>Use <code>x</code> here</p>"),
                       "```swift\nlet x = 1\nprint(x)\n```\n\nUse `x` here")
        XCTAssertEqual(convert("<blockquote><p>Quote</p></blockquote><hr><p>After</p>"), "> Quote\n\n---\n\nAfter")
        XCTAssertEqual(convert("<table><thead><tr><th>Name</th><th>Qty</th></tr></thead><tbody><tr><td>Apple</td><td>3</td></tr></tbody></table>"),
                       "| Name | Qty |\n| --- | --- |\n| Apple | 3 |")
    }

    func testLinksAndImages() {
        XCTAssertEqual(convert(#"<p><a href="https://example.com">https://example.com</a></p>"#), "<https://example.com>")
        XCTAssertEqual(convert(#"<p><a href="mailto:pop@example.com">pop@example.com</a></p>"#), "<pop@example.com>")
        XCTAssertEqual(convert(#"<p><img src="https://example.com/a.png" alt="Logo"></p>"#), "![Logo](https://example.com/a.png)")
        // 页内锚点、脚本链接只留文字
        XCTAssertEqual(convert(##"<p><a href="#top">Top</a> <a href="javascript:void(0)">Run</a></p>"##), "Top Run")
    }

    func testGoogleDocsStyles() {
        let html = #"<p><b style="font-weight:normal;" id="docs-internal-guid-1"><span style="font-weight:700">Bold</span> and "#
            + #"<span style="font-style:italic">italic</span></b></p>"#
        XCTAssertEqual(convert(html), "**Bold** and *italic*")
    }

    func testEscaping() {
        XCTAssertEqual(convert("<p>Use * and _private and snake_case</p>"), "Use \\* and \\_private and snake_case")
        XCTAssertEqual(convert("<p>1. not a list</p><p># not a heading</p>"), "1\\. not a list\n\n\\# not a heading")
    }

    func testPlainSelectionNeedsNoConversion() {
        XCTAssertNil(HTMLToMarkdown.convert(RichSelection(html: "<p>Hello   world</p>", text: "Hello world")))
        XCTAssertEqual(HTMLToMarkdown.convert(RichSelection(html: "<p>Hello <b>world</b></p>", text: "Hello world")),
                       "Hello **world**")
    }

    func testAttributedText() throws {
        let body = NSFont.systemFont(ofSize: 13)
        let text = NSMutableAttributedString(string: "Title\n", attributes: [.font: NSFont.boldSystemFont(ofSize: 24)])
        text.append(NSAttributedString(string: "Hello ", attributes: [.font: body]))
        text.append(NSAttributedString(string: "bold", attributes: [.font: NSFont.boldSystemFont(ofSize: 13)]))
        text.append(NSAttributedString(string: " and ", attributes: [.font: body]))
        text.append(NSAttributedString(string: "code", attributes: [.font: try XCTUnwrap(NSFont(name: "Menlo", size: 13))]))
        text.append(NSAttributedString(string: " with a ", attributes: [.font: body]))
        text.append(NSAttributedString(string: "link", attributes: [.font: body, .link: try XCTUnwrap(URL(string: "https://example.com"))]))
        text.append(NSAttributedString(string: " for more text here.", attributes: [.font: body]))
        XCTAssertEqual(HTMLToMarkdown.convert(attributed: text),
                       "# Title\n\nHello **bold** and `code` with a [link](https://example.com) for more text here.")
    }

    func testRTF() throws {
        let regular = try XCTUnwrap(NSFont(name: "Helvetica", size: 12))
        let bold = try XCTUnwrap(NSFont(name: "Helvetica-Bold", size: 12))
        let text = NSMutableAttributedString(string: "Plain and ", attributes: [.font: regular])
        text.append(NSAttributedString(string: "strong", attributes: [.font: bold]))
        text.append(NSAttributedString(string: " words.", attributes: [.font: regular]))
        let rtf = try XCTUnwrap(text.rtf(from: NSRange(location: 0, length: text.length), documentAttributes: [:]))
        XCTAssertEqual(HTMLToMarkdown.convert(RichSelection(rtf: rtf, text: text.string)), "Plain and **strong** words.")
    }
}

final class InfoExtractorTests: XCTestCase {
    func testFindsEachKindInOrderWithoutDuplicates() {
        let text = "联系 pop@example.com，电话 138-1234-5678；下载 https://github.com/whrss9527/pop/releases，"
            + "文档在 www.example.com；测试机 192.168.1.20:8080，备用 pop@example.com"
        let items = InfoExtractor.extract(text)
        XCTAssertEqual(items.map(\.value), ["pop@example.com", "138-1234-5678", "https://github.com/whrss9527/pop/releases",
                                            "www.example.com", "192.168.1.20:8080"])
        XCTAssertEqual(items.map(\.kind), [.email, .phone, .link, .link, .ip])

        let card = InfoExtractor.card(for: items)
        XCTAssertEqual(card.rows.map(\.label), ["邮箱 1", "电话 1", "链接 1", "链接 2", "IP 地址 1"])
        XCTAssertEqual(card.buttons.first { $0.title == "复制全部链接" }?.action,
                       .copy("https://github.com/whrss9527/pop/releases\nwww.example.com"))
        XCTAssertEqual(card.detail, "2 个链接，1 个邮箱，1 个电话，1 个 IP 地址")
    }

    func testPhoneFormats() {
        let text = "客服 400-123-4567，北京 010-12345678，国际 +1 (415) 555-2671，手机 +86 13812345678"
        XCTAssertEqual(InfoExtractor.extract(text).map(\.value),
                       ["400-123-4567", "010-12345678", "+1 (415) 555-2671", "+86 13812345678"])
        // 长数字串里的一段不算手机号
        XCTAssertTrue(InfoExtractor.extract("订单号 202609291381234567890").isEmpty)
    }

    func testFileNamesAreNotLinks() {
        XCTAssertTrue(InfoExtractor.extract("打开 main.py 和 README.md，再看 Pop.app").isEmpty)
    }

    func testWhenToOffer() {
        XCTAssertFalse(InfoExtractor.isWorthExtracting("https://example.com"))
        XCTAssertTrue(InfoExtractor.isWorthExtracting("见 https://example.com"))
        XCTAssertTrue(InfoExtractor.isWorthExtracting("a@example.com b@example.com"))
        XCTAssertFalse(InfoExtractor.isWorthExtracting("今天天气很好"))
    }
}

final class CharacterInspectorTests: XCTestCase {
    func testInvisibleCharacters() {
        let text = "a\u{200B}b\u{00A0}c\u{FEFF}d\u{200B}"
        let found = CharacterInspector.invisibles(in: text)
        XCTAssertEqual(found.map(\.name), ["零宽空格", "不换行空格", "BOM"])
        XCTAssertEqual(found.map(\.count), [2, 1, 1])
        XCTAssertEqual(CharacterInspector.removingInvisibles(text), "ab cd")
        // 表情符号里的零宽连字不算
        XCTAssertTrue(CharacterInspector.invisibles(in: "👨‍👩‍👧 好").isEmpty)
        XCTAssertEqual(CharacterInspector.removingInvisibles("👨‍👩‍👧"), "👨‍👩‍👧")
    }

    func testDescriptions() {
        XCTAssertEqual(CharacterInspector.describe("中"), "U+4E2D · CJK UNIFIED IDEOGRAPH-4E2D\nUTF-8 E4 B8 AD")
        let thumbs = CharacterInspector.describe("👍🏽")
        XCTAssertTrue(thumbs.hasPrefix("U+1F44D U+1F3FD · THUMBS UP SIGN + EMOJI MODIFIER FITZPATRICK TYPE-4"), thumbs)
        XCTAssertTrue(thumbs.hasSuffix("UTF-16 D83D DC4D D83C DFFD"), thumbs)
        XCTAssertEqual(CharacterInspector.label(" "), "空格")
        XCTAssertEqual(CharacterInspector.label("\u{200B}"), "零宽空格")
        XCTAssertEqual(CharacterInspector.label("A"), "A")
    }

    func testCard() {
        let card = CharacterInspector.card(for: "Hi")
        XCTAssertEqual(card.rows.map(\.label), ["H", "i"])
        XCTAssertEqual(card.buttons.first?.action, .copy("U+0048 U+0069"))
        XCTAssertNil(card.detail)

        let long = String(repeating: "长文字", count: 10) + "\u{200B}"
        let cleaned = CharacterInspector.card(for: long)
        XCTAssertEqual(cleaned.rows.count, 1)
        XCTAssertEqual(cleaned.detail, "有 1 个看不见的字符：零宽空格 ×1")
        XCTAssertTrue(cleaned.buttons.contains { $0.action == .replace(String(repeating: "长文字", count: 10)) })
    }

    func testWhenToOffer() {
        XCTAssertTrue(CharacterInspector.isApplicable("é"))
        XCTAssertFalse(CharacterInspector.isApplicable(String(repeating: "很长的一段文字", count: 5)))
        XCTAssertTrue(CharacterInspector.isApplicable(String(repeating: "很长的一段文字", count: 5) + "\u{200B}"))
    }

    func testTextCleanupRemovesInvisibles() {
        let rows = TextCleanup.conversions("复制\u{200B}来的文字")
        XCTAssertEqual(rows.first { $0.label == "去掉看不见的字符" }?.value, "复制来的文字")
    }
}

final class LineToolsTests: XCTestCase {
    private func value(_ rows: [ResultCard.Row], _ label: String) -> String? {
        rows.first { $0.label == label }?.value
    }

    func testItems() {
        XCTAssertEqual(LineTools.items("a\n\n b \nc"), LineTools.Items(values: ["a", "b", "c"], fromLines: true))
        XCTAssertEqual(LineTools.items("a, b, c"), LineTools.Items(values: ["a", "b", "c"], fromLines: false))
        XCTAssertEqual(LineTools.items("苹果、香蕉"), LineTools.Items(values: ["苹果", "香蕉"], fromLines: false))
        XCTAssertNil(LineTools.items("只有一项"))
        XCTAssertFalse(LineTools.isApplicable("第一段很长的文字" + String(repeating: "。", count: 300) + "\n第二段"))
    }

    func testConversions() {
        let rows = LineTools.conversions("1001\n1002\n1003")
        XCTAssertEqual(value(rows, "逗号隔开"), "1001, 1002, 1003")
        XCTAssertEqual(value(rows, "单引号"), "'1001', '1002', '1003'")
        XCTAssertEqual(value(rows, "JSON 数组"), "[1001, 1002, 1003]")
        XCTAssertEqual(value(rows, "加序号"), "1. 1001\n2. 1002\n3. 1003")
        XCTAssertEqual(value(rows, "倒序"), "1003\n1002\n1001")
        if let shuffled = value(rows, "打乱顺序") {
            XCTAssertEqual(shuffled.components(separatedBy: "\n").sorted(), ["1001", "1002", "1003"])
        }

        let names = LineTools.conversions("O'Brien\nSmith")
        XCTAssertEqual(value(names, "单引号"), "'O''Brien', 'Smith'")
        XCTAssertEqual(value(names, "双引号"), #""O'Brien", "Smith""#)
        XCTAssertEqual(value(names, "JSON 数组"), #"["O'Brien", "Smith"]"#)

        XCTAssertEqual(value(LineTools.conversions("1. 苹果\n2. 香蕉"), "去掉序号"), "苹果\n香蕉")
        XCTAssertEqual(value(LineTools.conversions("a、b、c"), "拆成多行"), "a\nb\nc")
        XCTAssertEqual(value(LineTools.conversions("'a'\n'b'"), "去掉引号"), "a\nb")
    }

    func testNumbering() {
        XCTAssertEqual(LineTools.removingNumbering("1.5"), "1.5")
        XCTAssertEqual(LineTools.removingNumbering("-5"), "-5")
        XCTAssertEqual(LineTools.removingNumbering("- item"), "item")
        XCTAssertEqual(LineTools.removingNumbering("（3）第三"), "第三")
        XCTAssertEqual(LineTools.removingNumbering("2、第二"), "第二")
    }
}

final class LunarCalendarTests: XCTestCase {
    private func date(_ text: String) throws -> Date {
        try XCTUnwrap(DateParser.parse(text, timeZone: shanghai))
    }

    private var shanghai: TimeZone { TimeZone(identifier: "Asia/Shanghai")! }

    func testLunarDates() throws {
        XCTAssertEqual(LunarCalendar.describe(try date("2026-09-25 12:00"), timeZone: shanghai), "丙午年（马年）八月十五 · 中秋节")
        XCTAssertEqual(LunarCalendar.describe(try date("2026-09-29 12:00"), timeZone: shanghai), "丙午年（马年）八月十九")
        XCTAssertEqual(LunarCalendar.describe(try date("2026-02-17 08:00"), timeZone: shanghai), "丙午年（马年）正月初一 · 春节")
        XCTAssertEqual(LunarCalendar.festival(try date("2026-02-16 20:00"), timeZone: shanghai), "除夕")
        XCTAssertEqual(LunarCalendar.describe(try date("2025-01-29 08:00"), timeZone: shanghai), "乙巳年（蛇年）正月初一 · 春节")
        XCTAssertEqual(LunarCalendar.weekAndDay(try date("2026-09-29 12:00"), timeZone: shanghai), "第 40 周 · 全年第 272 天")
    }

    func testDayNames() {
        XCTAssertEqual([1, 10, 15, 20, 21, 30].map(LunarCalendar.dayName), ["初一", "初十", "十五", "二十", "廿一", "三十"])
    }

    func testTimeCardShowsLunarDate() throws {
        let rows = DateParser.rows(for: try date("2024-09-28 16:00"), timeZone: shanghai)
        XCTAssertEqual(rows.first { $0.label == "农历" }?.value, "甲辰年（龙年）八月廿六")
        XCTAssertNotNil(rows.first { $0.label == "第几周" })
    }
}
