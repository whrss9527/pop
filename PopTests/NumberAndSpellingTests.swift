import XCTest
@testable import Pop

final class NumberStatsTests: XCTestCase {
    func testColumnsWithLabels() throws {
        let column = try XCTUnwrap(NumberStats.parse("苹果 12\n香蕉 30.5\n橙子 7"))
        XCTAssertEqual(column.values, [12, 30.5, 7])
        // 合计、平均、中位数、最大、最小、个数
        XCTAssertEqual(column.rows.map(\.value), ["49.5", "16.5", "12", "30.5", "7", "3"])
        XCTAssertEqual(NumberStats.parse("1\n2\n3\n4")?.median, 2.5)
        // 浮点误差不显示出来
        XCTAssertEqual(NumberStats.parse("0.1\n0.2")?.rows.first?.value, "0.3")
    }

    func testOneLineLists() throws {
        let line = try XCTUnwrap(NumberStats.parse("1,234, 5,678; 10"))
        XCTAssertEqual(line.values, [1234, 5678, 10])
        XCTAssertEqual(line.rows.first?.value, "6922")
        XCTAssertEqual(NumberStats.parse("¥12 $3.5 -4")?.values, [12, 3.5, -4])
    }

    func testNotLists() {
        XCTAssertNil(NumberStats.parse("1,234"))
        XCTAssertNil(NumberStats.parse("2026-09-29"))
        XCTAssertNil(NumberStats.parse("version 1.2.3"))
        XCTAssertNil(NumberStats.parse("a\nb\nc 3"))
        XCTAssertNil(NumberStats.parse("hello world"))
    }

    func testRingShowsItOnlyForNumberLists() {
        let info = NumberStatsPlugin().info
        XCTAssertTrue(info.canHandle(ContentClassifier.classify(.text("12\n30\n7"))))
        XCTAssertTrue(info.canHandle(ContentClassifier.classify(.text("12, 30, 7"))))
        XCTAssertFalse(info.canHandle(ContentClassifier.classify(.text("42"))))
        XCTAssertFalse(info.canHandle(ContentClassifier.classify(.text("hello world"))))
    }
}

@MainActor
final class SpellCheckTests: XCTestCase {
    func testFindsAndFixesMisspellings() {
        let text = "I havv a speling eror"
        let issues = SpellCheck.issues(in: text, language: "en")
        XCTAssertEqual(issues.map(\.word), ["havv", "speling", "eror"])
        let corrected = SpellCheck.corrected(text, issues: issues)
        XCTAssertTrue(corrected.contains("spelling"), corrected)
        XCTAssertTrue(corrected.hasPrefix("I "), corrected)
        XCTAssertTrue(SpellCheck.issues(in: "This sentence is spelled correctly.", language: "en").isEmpty)
    }

    func testLanguages() {
        XCTAssertEqual(SpellCheck.supportedLanguage("en"), "en")
        XCTAssertNil(SpellCheck.supportedLanguage("xx"))
        XCTAssertNil(SpellCheck.supportedLanguage(nil))
    }

    func testCorrectionKeepsWordsWithoutSuggestions() {
        let issues = [SpellCheck.Issue(word: "zzqx", range: NSRange(location: 0, length: 4), suggestions: []),
                      SpellCheck.Issue(word: "teh", range: NSRange(location: 5, length: 3), suggestions: ["the"])]
        XCTAssertEqual(SpellCheck.corrected("zzqx teh cat", issues: issues), "zzqx the cat")
    }
}
