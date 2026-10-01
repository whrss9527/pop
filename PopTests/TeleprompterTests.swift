import XCTest
@testable import Pop

final class TeleprompterTests: XCTestCase {
    @MainActor
    func testScrollsAndStopsAtTheEnd() {
        let model = TeleprompterModel(text: "稿子", speed: 40, fontSize: 32)
        model.contentHeight = 600
        model.viewportHeight = 270
        // 最后一行滚到上三分之一处为止
        XCTAssertEqual(model.maxOffset, 510)
        model.advance(by: 1)
        XCTAssertEqual(model.offset, 40)
        // 暂停时不动
        model.togglePause()
        model.advance(by: 1)
        XCTAssertEqual(model.offset, 40)
        model.togglePause()
        model.advance(by: 100)
        XCTAssertEqual(model.offset, 510)
        XCTAssertTrue(model.reachedEnd)
        XCTAssertTrue(model.paused)
        // 滚到头以后再按一次：从头开始
        model.togglePause()
        XCTAssertEqual(model.offset, 0)
        XCTAssertFalse(model.paused)
    }

    @MainActor
    func testSpeedFontAndManualScroll() {
        let model = TeleprompterModel(text: "稿子", speed: 145, fontSize: 58)
        model.faster()
        XCTAssertEqual(model.speed, TeleprompterModel.speeds.upperBound)
        model.bigger()
        XCTAssertEqual(model.fontSize, TeleprompterModel.fontSizes.upperBound)
        model.slower()
        XCTAssertEqual(model.speed, 150 - TeleprompterModel.speedStep)
        model.contentHeight = 1000
        model.viewportHeight = 300
        model.scroll(by: -50)
        XCTAssertEqual(model.offset, 0)
        model.scroll(by: 5000)
        XCTAssertEqual(model.offset, 900)
        XCTAssertEqual(TeleprompterModel(text: "", speed: 1, fontSize: 1).speed, TeleprompterModel.speeds.lowerBound)
        XCTAssertEqual(TeleprompterModel.linesPerMinute(speed: 40, fontSize: 32), 52)
    }

    func testWindowSitsAtTheTopCenter() {
        let frame = Teleprompter.frame(in: CGRect(x: 0, y: 0, width: 1440, height: 875))
        XCTAssertEqual(frame.midX, 720, accuracy: 1)
        XCTAssertEqual(frame.maxY, 867, accuracy: 1)
        XCTAssertEqual(frame.width, 720)
        XCTAssertEqual(Teleprompter.frame(in: CGRect(x: 0, y: 0, width: 800, height: 600)).width, 560)
        XCTAssertEqual(Teleprompter.frame(in: CGRect(x: 0, y: 0, width: 3000, height: 1600)).width, 860)
    }

    @MainActor
    func testPluginNeedsSomeText() {
        let info = TeleprompterPlugin().info
        XCTAssertTrue(info.canHandle(ContentClassifier.classify(.text("大家好，今天介绍一下 Pop 的录屏功能。"))))
        XCTAssertFalse(info.canHandle(ContentClassifier.classify(.text("你好"))))
        XCTAssertFalse(info.canHandle(.empty))
    }
}
