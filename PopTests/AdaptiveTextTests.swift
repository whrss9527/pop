import XCTest
@testable import Pop

final class AdaptiveTextTests: XCTestCase {
    /// 卡片上太长的文字只显示前面一部分，后面说一句；短的原样显示
    func testLongTextIsCutForDisplay() {
        XCTAssertEqual(AdaptiveText.displayed("短的"), "短的")
        let exactly = String(repeating: "a", count: AdaptiveText.displayLimit)
        XCTAssertEqual(AdaptiveText.displayed(exactly), exactly)
        // 中文一个字三个字节：字节数过了上限、字数没过的也原样显示
        let chinese = String(repeating: "字", count: AdaptiveText.displayLimit)
        XCTAssertEqual(AdaptiveText.displayed(chinese), chinese)

        let long = String(repeating: "{\"a\": 1}\n", count: 50_000)
        let shown = AdaptiveText.displayed(long)
        XCTAssertTrue(shown.hasPrefix(String(long.prefix(AdaptiveText.displayLimit))))
        XCTAssertTrue(shown.hasSuffix("（太长了，这里只显示前面一部分；复制、替换原文用的是全部）"))
        XCTAssertLessThan(shown.count, AdaptiveText.displayLimit + 100)
    }

    /// 长文字放进滚动区域：字多、行多都算长；很长的不用一个个数
    func testLongTextScrolls() {
        XCTAssertFalse(AdaptiveText.isLong("一行字"))
        XCTAssertTrue(AdaptiveText.isLong(String(repeating: "字", count: 601)))
        XCTAssertFalse(AdaptiveText.isLong(String(repeating: "字", count: 600)))
        XCTAssertTrue(AdaptiveText.isLong(String(repeating: "一行\n", count: 15)))
        XCTAssertFalse(AdaptiveText.isLong(String(repeating: "一行\n", count: 14)))
        XCTAssertTrue(AdaptiveText.isLong(String(repeating: "一行\n", count: 7), compact: true))
        XCTAssertTrue(AdaptiveText.isLong(String(repeating: "{\"a\": 1}\n", count: 500_000)))
    }
}
