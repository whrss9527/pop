import XCTest
@testable import Pop

final class TextTransformsTests: XCTestCase {
    private func value(_ rows: [ResultCard.Row], _ label: String) -> String? {
        rows.first { $0.label == label }?.value
    }

    func testCaseConversion() {
        XCTAssertEqual(CaseConverter.words("getHTTPResponse"), ["get", "HTTP", "Response"])
        XCTAssertEqual(CaseConverter.words("snake_case value"), ["snake", "case", "value"])
        XCTAssertEqual(CaseConverter.words("version2Update"), ["version2", "Update"])
        let rows = CaseConverter.conversions("hello world")
        XCTAssertEqual(value(rows, "大写"), "HELLO WORLD")
        XCTAssertEqual(value(rows, "首字母大写"), "Hello World")
        XCTAssertEqual(value(rows, "camelCase"), "helloWorld")
        XCTAssertEqual(value(rows, "PascalCase"), "HelloWorld")
        XCTAssertEqual(value(rows, "kebab-case"), "hello-world")
        XCTAssertEqual(value(rows, "CONSTANT"), "HELLO_WORLD")
        XCTAssertTrue(CaseConverter.conversions("  ").isEmpty)
    }

    func testCodecs() {
        XCTAssertEqual(TextCodec.base64Encode("Pop 你好"), "UG9wIOS9oOWlvQ==")
        XCTAssertEqual(TextCodec.base64Decode("UG9wIOS9oOWlvQ=="), "Pop 你好")
        XCTAssertEqual(TextCodec.base64Decode("aGVsbG8"), "hello")
        XCTAssertNil(TextCodec.base64Decode("hi"))
        XCTAssertEqual(TextCodec.urlEncode("a b&c"), "a%20b%26c")
        XCTAssertEqual(TextCodec.urlDecode("a%20b%26c"), "a b&c")
        XCTAssertNil(TextCodec.urlDecode("plain"))
        XCTAssertEqual(TextCodec.unicodeEscape("é😀a"), "\\u00e9\\ud83d\\ude00a")
        XCTAssertEqual(TextCodec.unicodeUnescape("\\u00e9\\ud83d\\ude00a"), "é😀a")
        XCTAssertEqual(TextCodec.unicodeUnescape("x\\u{1F600}y"), "x😀y")
        XCTAssertEqual(TextCodec.htmlEscape("<a href=\"x\">'&'</a>"), "&lt;a href=&quot;x&quot;&gt;&#39;&amp;&#39;&lt;/a&gt;")
        XCTAssertEqual(TextCodec.htmlUnescape("&lt;b&gt; &amp; &#20013;&#x6587; &unknown;"), "<b> & 中文 &unknown;")
        let rows = TextCodec.conversions("aGVsbG8=")
        XCTAssertEqual(rows.first?.label, "Base64 解码")
        XCTAssertEqual(rows.first?.value, "hello")
    }

    func testStatistics() {
        let statistics = TextStatistics("你好 world\nsecond line")
        XCTAssertEqual(statistics.characters, 20)
        XCTAssertEqual(statistics.nonWhitespace, 17)
        XCTAssertEqual(statistics.chinese, 2)
        XCTAssertEqual(statistics.lines, 2)
        XCTAssertEqual(statistics.utf8Bytes, 24)
        XCTAssertGreaterThanOrEqual(statistics.words, 3)
        XCTAssertEqual(statistics.readingTime, "不到 1 分钟")
        XCTAssertEqual(TextStatistics("").lines, 0)
    }

    func testDigests() throws {
        let rows = Digests.rows(for: Data("abc".utf8))
        XCTAssertEqual(value(rows, "MD5"), "900150983cd24fb0d6963f7d28e17f72")
        XCTAssertEqual(value(rows, "SHA-1"), "a9993e364706816aba3e25717850c26c9cd0d89d")
        XCTAssertEqual(value(rows, "SHA-256"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(value(rows, "SHA-512")?.hasPrefix("ddaf35a193617aba"), true)

        let url = FileManager.default.temporaryDirectory.appending(path: "pop-hash-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("abc".utf8).write(to: url)
        XCTAssertEqual(try Digests.rows(forFile: url), rows)
        XCTAssertEqual(try Digests.sha256(ofFile: url), value(rows, "SHA-256"))
    }

    func testNumbers() throws {
        XCTAssertEqual(NumberConverter.parse("0x1F")?.integer, 31)
        XCTAssertEqual(NumberConverter.parse("0b1010")?.integer, 10)
        XCTAssertEqual(NumberConverter.parse("0o17")?.integer, 15)
        XCTAssertEqual(NumberConverter.parse("1,234,567")?.integer, 1_234_567)
        XCTAssertEqual(NumberConverter.parse("-42")?.integer, -42)
        XCTAssertNil(NumberConverter.parse("3.14")?.integer)
        XCTAssertEqual(NumberConverter.parse("3.14")?.decimal, Decimal(string: "3.14"))
        XCTAssertNil(NumberConverter.parse("1,23"))
        XCTAssertNil(NumberConverter.parse("abc"))
        XCTAssertNil(NumberConverter.parse("0x"))

        let rows = NumberConverter.rows(for: try XCTUnwrap(NumberConverter.parse("255")))
        XCTAssertEqual(value(rows, "十六进制"), "0xFF")
        XCTAssertEqual(value(rows, "八进制"), "0o377")
        XCTAssertEqual(value(rows, "二进制"), "0b11111111")
        XCTAssertEqual(value(rows, "千分位"), "255")
        XCTAssertEqual(NumberConverter.signed(-255, radix: 16, prefix: "0x"), "-0xFF")
        XCTAssertEqual(NumberConverter.grouped(Decimal(1_234_567)), "1,234,567")
    }

    func testRMBUppercase() {
        func rmb(_ text: String) -> String? {
            Decimal(string: text).flatMap(NumberConverter.rmbUppercase)
        }
        XCTAssertEqual(rmb("1234.5"), "壹仟贰佰叁拾肆元伍角")
        XCTAssertEqual(rmb("100000001"), "壹亿零壹元整")
        XCTAssertEqual(rmb("105000"), "壹拾万伍仟元整")
        XCTAssertEqual(rmb("100500"), "壹拾万零伍佰元整")
        XCTAssertEqual(rmb("10000"), "壹万元整")
        XCTAssertEqual(rmb("10.05"), "壹拾元零伍分")
        XCTAssertEqual(rmb("0.5"), "伍角")
        XCTAssertEqual(rmb("0"), "零元整")
        XCTAssertEqual(rmb("-3"), "负叁元整")
        XCTAssertEqual(rmb("2000000000"), "贰拾亿元整")
        XCTAssertNil(rmb("12345678901234567"))
    }

    func testColors() throws {
        let orange = try XCTUnwrap(ColorValue.parse("#FF8800"))
        XCTAssertEqual(orange.hexString, "#FF8800")
        XCTAssertEqual(orange.rgbString, "rgb(255, 136, 0)")
        XCTAssertEqual(orange.hslString, "hsl(32, 100%, 50%)")
        XCTAssertEqual(orange.swiftUIString, "Color(red: 1, green: 0.533, blue: 0)")

        XCTAssertEqual(ColorValue.parse("#abc")?.hexString, "#AABBCC")
        XCTAssertNil(ColorValue.parse("#123"))
        XCTAssertNil(ColorValue.parse("#12345"))
        XCTAssertEqual(ColorValue.parse("rgb(255, 0, 0)")?.hexString, "#FF0000")
        XCTAssertEqual(ColorValue.parse("rgb(255 0 0 / 50%)")?.hexString, "#FF000080")
        let translucent = try XCTUnwrap(ColorValue.parse("rgba(0, 0, 255, 0.5)"))
        XCTAssertEqual(translucent.hexString, "#0000FF80")
        XCTAssertEqual(translucent.rgbString, "rgba(0, 0, 255, 0.5)")
        XCTAssertEqual(ColorValue.parse("hsl(120, 100%, 50%)")?.hexString, "#00FF00")
        XCTAssertEqual(ColorValue.parse("HSL(0deg, 0%, 100%)")?.hexString, "#FFFFFF")
        XCTAssertNil(ColorValue.parse("rgb(300, 0, 0)"))
        XCTAssertNil(ColorValue.parse("hello"))
    }

    func testDates() throws {
        let utc = try XCTUnwrap(TimeZone(identifier: "UTC"))
        XCTAssertEqual(DateParser.parse("2026-09-28 14:30", timeZone: utc)?.timeIntervalSince1970, 1_790_605_800)
        XCTAssertEqual(DateParser.parse("2026-09-28", timeZone: utc)?.timeIntervalSince1970, 1_790_553_600)
        XCTAssertEqual(DateParser.parse("2026/09/28 14:30:00", timeZone: utc)?.timeIntervalSince1970, 1_790_605_800)
        XCTAssertEqual(DateParser.parse("2026年9月28日", timeZone: utc)?.timeIntervalSince1970, 1_790_553_600)
        XCTAssertEqual(DateParser.parse("2024-09-28T08:00:00Z")?.timeIntervalSince1970, 1_727_510_400)
        XCTAssertNil(DateParser.parse("12345678"))
        XCTAssertNil(DateParser.parse("hello world"))
        XCTAssertNil(DateParser.parse("2026-13-45"))

        let date = Date(timeIntervalSince1970: 1_727_510_400)
        let rows = DateParser.rows(for: date, timeZone: utc, now: date.addingTimeInterval(3 * 86_400))
        XCTAssertEqual(value(rows, "本地时间"), "2024-09-28 08:00:00")
        XCTAssertEqual(value(rows, "Unix 秒"), "1727510400")
        XCTAssertEqual(value(rows, "星期"), "星期六")
        XCTAssertEqual(value(rows, "距今")?.contains("3"), true)
    }

    func testRandom() {
        let password = RandomGenerator.password()
        XCTAssertEqual(password.count, 16)
        XCTAssertTrue(password.contains { $0.isLowercase })
        XCTAssertTrue(password.contains { $0.isUppercase })
        XCTAssertTrue(password.contains { $0.isNumber })
        XCTAssertTrue(password.contains { "!@#$%^&*-_=+?".contains($0) })
        let plain = RandomGenerator.password(length: 20, includeSymbols: false)
        XCTAssertEqual(plain.count, 20)
        XCTAssertTrue(plain.allSatisfy { $0.isLetter || $0.isNumber })
        XCTAssertNotEqual(RandomGenerator.password(), RandomGenerator.password())
    }

    func testPinyinSearch() {
        let keys = SearchText.keys(for: "翻译")
        XCTAssertTrue(SearchText.matches("fy", keys: keys))
        XCTAssertTrue(SearchText.matches("fanyi", keys: keys))
        XCTAssertTrue(SearchText.matches("翻", keys: keys))
        XCTAssertFalse(SearchText.matches("json", keys: keys))
        XCTAssertTrue(SearchText.matches("", keys: keys))
        XCTAssertTrue(SearchText.matches("JSON", keys: SearchText.keys(for: "JSON 格式化")))
        XCTAssertTrue(SearchText.matches("gsh", keys: SearchText.keys(for: "JSON 格式化")))
    }
}
