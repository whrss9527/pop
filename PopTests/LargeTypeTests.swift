import AppKit
import XCTest
@testable import Pop

final class LargeTypeTests: XCTestCase {
    func testPicksTheLargestSizeThatFits() {
        let area = CGSize(width: 1000, height: 600)
        let phone = LargeType.fontSize(for: "13812345678", fitting: area)
        // 一串数字不能拆开：整串放得下一行，再大一点就放不下
        XCTAssertTrue(LargeType.fits("13812345678", fontSize: phone, in: area))
        XCTAssertFalse(LargeType.fits("13812345678", fontSize: phone + 4, in: area))
        XCTAssertTrue((100...260).contains(phone), "\(phone)")

        // 一段话可以换行，字号比一串数字小
        let sentence = "周五的发布会改到下午三点，地点不变。会前请把演示用的 Mac 更新到最新系统，提前半小时到场调试投屏。"
        let smaller = LargeType.fontSize(for: sentence, fitting: area)
        XCTAssertLessThan(smaller, phone)
        XCTAssertTrue(LargeType.fits(sentence, fontSize: smaller, in: area))

        // 很长的链接可以在中间换行，不用为了放进一行缩得很小
        let link = "https://github.com/whrss9527/pop/releases?utm_source=newsletter&utm_medium=email"
        XCTAssertGreaterThan(LargeType.fontSize(for: link, fitting: area), 60)

        // 很短的字到上限为止
        XCTAssertEqual(LargeType.fontSize(for: "好", fitting: area, maximum: 320), 320)
    }

    func testKeepsWordsAndNumbersTogether() {
        XCTAssertEqual(LargeType.unbreakableRuns("Wi-Fi 密码：pop2026!"), ["Wi-Fi", "pop2026!"])
        XCTAssertEqual(LargeType.unbreakableRuns("取件码 3-1-2046"), ["3-1-2046"])
        XCTAssertTrue(LargeType.unbreakableRuns("你好").isEmpty)
    }

    @MainActor
    func testPluginNeedsShortText() {
        let info = LargeTypePlugin().info
        XCTAssertTrue(info.canHandle(ContentClassifier.classify(.text("13812345678"))))
        XCTAssertFalse(info.canHandle(ContentClassifier.classify(.text(String(repeating: "长", count: LargeType.maxLength + 1)))))
        XCTAssertFalse(info.canHandle(.empty))
    }
}

final class KeyboardCleanerTests: XCTestCase {
    func testCountdownText() {
        XCTAssertEqual(KeyboardCleaner.remainingText(60), "1:00")
        XCTAssertEqual(KeyboardCleaner.remainingText(44.2), "0:45")
        XCTAssertEqual(KeyboardCleaner.remainingText(0.1), "0:01")
        XCTAssertEqual(KeyboardCleaner.remainingText(-3), "0:00")
    }

    @MainActor
    func testBlocksKeysAndFunctionKeys() {
        let mask = KeyboardCleaner.eventMask
        XCTAssertNotEqual(mask & (CGEventMask(1) << CGEventMask(CGEventType.keyDown.rawValue)), 0)
        XCTAssertNotEqual(mask & (CGEventMask(1) << CGEventMask(CGEventType.flagsChanged.rawValue)), 0)
        // 亮度、音量这些功能键
        XCTAssertNotEqual(mask & (CGEventMask(1) << 14), 0)
        // 鼠标不拦
        XCTAssertEqual(mask & (CGEventMask(1) << CGEventMask(CGEventType.leftMouseDown.rawValue)), 0)
        XCTAssertTrue(KeyboardCleanerPlugin().info.canHandle(.empty))
    }
}
