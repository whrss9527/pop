import XCTest
@testable import Pop

final class TextCleanupTests: XCTestCase {
    func testJoinLines() {
        XCTAssertEqual(TextCleanup.joinLines("The quick brown\nfox jumps. This is a sen-\ntence."),
                       "The quick brown fox jumps. This is a sentence.")
        XCTAssertEqual(TextCleanup.joinLines("第一行\n第二行"), "第一行第二行")
        XCTAssertEqual(TextCleanup.joinLines("Para one\r\nline two\n\n\nPara two"), "Para one line two\n\nPara two")
        XCTAssertNil(TextCleanup.joinLines("single line"))
    }

    func testSpacesAndWidth() {
        XCTAssertEqual(TextCleanup.spaceBetweenCJKAndLatin("用React写组件只要3分钟"), "用 React 写组件只要 3 分钟")
        XCTAssertEqual(TextCleanup.spaceBetweenCJKAndLatin("已经有 React 的"), "已经有 React 的")
        XCTAssertEqual(TextCleanup.halfWidth("ＡＢＣ１２３，你好"), "ABC123，你好")
        XCTAssertEqual(TextCleanup.collapseSpaces("  a   b\t\tc  \n d  "), "a b c\nd")
        XCTAssertEqual(TextCleanup.removeBlankLines("a\n\n  \nb"), "a\nb")
    }

    func testChineseConversions() {
        XCTAssertEqual(TextCleanup.pinyin("中文"), "zhōng wén")
        XCTAssertEqual(TextCleanup.stripTones("zhōng wén lǜ"), "zhong wen lü")
        let rows = TextCleanup.conversions("简体中文")
        XCTAssertEqual(rows.first { $0.label == "转为繁体" }?.value, "簡體中文")
        XCTAssertEqual(rows.first { $0.label == "无调拼音" }?.value, "jian ti zhong wen")
    }

    func testLinesAndRows() {
        XCTAssertEqual(TextCleanup.sortLines("banana\napple\ncherry"), "apple\nbanana\ncherry")
        XCTAssertEqual(TextCleanup.uniqueLines("a\nb\na\nc\nb"), "a\nb\nc")
        let rows = TextCleanup.conversions("第一行\n第一行")
        XCTAssertEqual(rows.first?.label, "合并换行")
        XCTAssertTrue(rows.contains { $0.label == "按行去重" && $0.value == "第一行" })
        // 没有可整理的地方时一行都没有
        XCTAssertTrue(TextCleanup.conversions("hello").isEmpty)
    }

    func testPluginOnlyShowsUpWhenUseful() {
        let info = TextCleanupPlugin().info
        XCTAssertFalse(info.canHandle(ContentClassifier.classify(.text("hello world"))))
        XCTAssertTrue(info.canHandle(ContentClassifier.classify(.text("你好"))))
        XCTAssertTrue(info.canHandle(ContentClassifier.classify(.text("a\nb"))))
        XCTAssertTrue(info.canHandle(ContentClassifier.classify(.text("a  b"))))
        XCTAssertTrue(info.canHandle(ContentClassifier.classify(.text("ＡＢＣ"))))
    }
}
