import XCTest
@testable import Pop

final class ContentClassifierTests: XCTestCase {
    private func kinds(_ text: String) -> Set<ContentKind> {
        ContentClassifier.classify(.text(text)).kinds
    }

    func testEmptySelection() {
        XCTAssertTrue(ContentClassifier.classify(.none).isEmpty)
        XCTAssertTrue(ContentClassifier.classify(.text("  \n ")).isEmpty)
        XCTAssertTrue(ContentClassifier.classify(.files([])).isEmpty)
    }

    func testForeignText() {
        let content = ContentClassifier.classify(.text("  Hello, how are you doing today?  "))
        XCTAssertEqual(content.kinds, [.text, .foreignText])
        XCTAssertEqual(content.text, "Hello, how are you doing today?")
        XCTAssertEqual(content.language, "en")
        XCTAssertEqual(kinds("こんにちは、元気ですか"), [.text, .foreignText])
        XCTAssertEqual(kinds("The word 你好 means hello"), [.text, .foreignText])
    }

    func testChineseText() {
        let content = ContentClassifier.classify(.text("今天天气很好，我们出去走走吧"))
        XCTAssertEqual(content.kinds, [.text, .chineseText])
        XCTAssertEqual(content.language?.hasPrefix("zh"), true)
        // 中英混排仍然算中文
        XCTAssertEqual(kinds("用 React 写一个组件"), [.text, .chineseText])
    }

    func testLinksAndEmail() {
        let url = ContentClassifier.classify(.text("https://github.com/whrss9527/pop"))
        XCTAssertEqual(url.kinds, [.text, .url])
        XCTAssertEqual(url.url?.host, "github.com")
        XCTAssertTrue(kinds("www.apple.com").contains(.url))
        XCTAssertEqual(kinds("someone@example.com"), [.text, .email])
        // 文件名不当成域名
        XCTAssertFalse(kinds("README.md").contains(.url))
        XCTAssertFalse(kinds("main.py").contains(.url))
    }

    func testStructuredText() {
        XCTAssertEqual(kinds(#"{"name": "pop", "tags": [1, 2]}"#), [.text, .json])
        XCTAssertEqual(kinds("[1, 2, 3]"), [.text, .json])
        XCTAssertFalse(kinds("{not json}").contains(.json))
        XCTAssertEqual(kinds("1727510400"), [.text, .timestamp])
        XCTAssertEqual(kinds("1727510400000"), [.text, .timestamp])
        XCTAssertFalse(kinds("9999999999").contains(.timestamp))
    }

    func testMath() {
        XCTAssertEqual(kinds("1 + 2"), [.text, .math])
        XCTAssertEqual(kinds("(3.5 - 1) / 2"), [.text, .math])
        XCTAssertEqual(kinds("200*15%"), [.text, .math])
        XCTAssertEqual(kinds("10 - 3"), [.text, .math])
        // 日期、编号、单独的数字不算算式
        XCTAssertFalse(kinds("2026-09-28").contains(.math))
        XCTAssertFalse(kinds("138-0000-0000").contains(.math))
        XCTAssertFalse(kinds("9/28").contains(.math))
        XCTAssertFalse(kinds("50%").contains(.math))
        XCTAssertFalse(kinds("12345").contains(.math))
        XCTAssertEqual(kinds("12345"), [.text, .number])
        XCTAssertEqual(kinds("138-0000-0000"), [.text])
    }

    func testColorsNumbersAndDates() {
        XCTAssertEqual(kinds("#FF8800"), [.text, .color])
        XCTAssertEqual(kinds("rgb(255, 136, 0)"), [.text, .color])
        XCTAssertEqual(kinds("hsl(120, 100%, 50%)"), [.text, .color])
        // #123 更像 issue 编号
        XCTAssertFalse(kinds("#123").contains(.color))
        XCTAssertEqual(kinds("0x1F"), [.text, .number])
        XCTAssertEqual(kinds("3.14"), [.text, .number])
        XCTAssertEqual(kinds("1,234,567"), [.text, .number])
        XCTAssertEqual(kinds("2026-09-28"), [.text, .dateTime])
        XCTAssertEqual(kinds("2026-09-28 14:30"), [.text, .dateTime])
        XCTAssertEqual(kinds("2026年9月28日"), [.text, .dateTime])
        XCTAssertEqual(ContentClassifier.classify(.text("#FF8800")).summary, "颜色")
    }

    func testWordsAndPaths() {
        XCTAssertEqual(kinds("serendipity"), [.text, .foreignText, .word])
        XCTAssertEqual(kinds("state-of-the-art"), [.text, .foreignText, .word])
        XCTAssertEqual(kinds("你好"), [.text, .chineseText, .word])
        XCTAssertFalse(kinds("hello world").contains(.word))
        XCTAssertFalse(kinds("a").contains(.word))

        let path = ContentClassifier.classify(.text("/tmp"))
        XCTAssertEqual(path.kinds, [.text, .files])
        XCTAssertEqual(path.files.first?.lastPathComponent, "tmp")
        XCTAssertEqual(path.summary, "路径")
        XCTAssertFalse(kinds("/definitely/not/here-\(UUID().uuidString)").contains(.files))
    }

    func testFilesAndImages() {
        let files = [URL(fileURLWithPath: "/tmp/a.txt"), URL(fileURLWithPath: "/tmp/b.txt")]
        let content = ContentClassifier.classify(.files(files))
        XCTAssertEqual(content.kinds, [.files])
        XCTAssertEqual(content.files, files)
        XCTAssertEqual(content.summary, "2 个文件")
        XCTAssertEqual(ContentClassifier.classify(.image(Data([0x89]))).kinds, [.image])
        let images = [URL(fileURLWithPath: "/tmp/a.png"), URL(fileURLWithPath: "/tmp/b.jpg")]
        XCTAssertEqual(ContentClassifier.classify(.files(images)).kinds, [.files, .imageFile])
    }

    func testScriptProfile() {
        XCTAssertTrue(ScriptProfile("中文").isChinese)
        XCTAssertFalse(ScriptProfile("日本語のテキスト").isChinese)
        XCTAssertFalse(ScriptProfile("한국어 텍스트").isChinese)
        XCTAssertFalse(ScriptProfile("12345 !!").hasLetters)
    }

    func testTimestampAndJSONHelpers() throws {
        let date = TimestampConverter.date(from: "1727510400")
        XCTAssertEqual(date, Date(timeIntervalSince1970: 1_727_510_400))
        XCTAssertEqual(TimestampConverter.localString(try XCTUnwrap(date), timeZone: try XCTUnwrap(TimeZone(identifier: "UTC"))), "2024-09-28 08:00:00")
        XCTAssertEqual(TimestampConverter.date(from: "1727510400123")?.timeIntervalSince1970 ?? 0, 1_727_510_400.123, accuracy: 0.0001)
        XCTAssertNil(TimestampConverter.date(from: "17275104a0"))

        let pretty = try XCTUnwrap(JSONFormatter.prettyPrinted(#"{"b":1,"a":[1,2]}"#))
        XCTAssertTrue(pretty.contains("\n"))
        // 键按字母排序
        let a = try XCTUnwrap(pretty.range(of: "\"a\"")?.lowerBound)
        let b = try XCTUnwrap(pretty.range(of: "\"b\"")?.lowerBound)
        XCTAssertLessThan(a, b)
    }
}
