import XCTest
@testable import Pop

final class CameraBubbleTests: XCTestCase {
    func testPlacementAndSizes() {
        let visible = CGRect(x: 0, y: 80, width: 1440, height: 800)
        // 默认在右下角，离边缘 24 点
        XCTAssertEqual(CameraBubble.defaultFrame(size: 200, in: visible), CGRect(x: 1216, y: 104, width: 200, height: 200))

        // 换大小时中心不动
        let frame = CGRect(x: 600, y: 400, width: 140, height: 140)
        XCTAssertEqual(CameraBubble.resized(frame, to: 200, within: visible), CGRect(x: 570, y: 370, width: 200, height: 200))
        // 贴着右下角放大时挪回屏幕里
        let corner = CameraBubble.defaultFrame(size: 140, in: visible)
        let bigger = CameraBubble.resized(corner, to: 280, within: visible)
        XCTAssertEqual(bigger.size, CGSize(width: 280, height: 280))
        XCTAssertTrue(visible.contains(bigger), "\(bigger)")

        // 双击在三档之间转，滚动限制在范围里
        XCTAssertEqual(CameraBubble.nextSize(after: 140), 200)
        XCTAssertEqual(CameraBubble.nextSize(after: 200), 280)
        XCTAssertEqual(CameraBubble.nextSize(after: 280), 140)
        XCTAssertEqual(CameraBubble.nextSize(after: 170), 200)
        XCTAssertEqual(CameraBubble.scrolled(200, by: 30), 230)
        XCTAssertEqual(CameraBubble.scrolled(120, by: -50), CameraBubble.sizeRange.lowerBound)
        XCTAssertEqual(CameraBubble.scrolled(400, by: 90), CameraBubble.sizeRange.upperBound)
    }

    @MainActor
    func testPluginsNeedNoContent() {
        XCTAssertTrue(CameraBubblePlugin().info.canHandle(.empty))
        XCTAssertTrue(CameraBubblePlugin().info.hidesOverlay)
        XCTAssertTrue(PointerHighlightPlugin().info.canHandle(.empty))
        XCTAssertEqual(CameraBubble.Shape.allCases.map(\.title), ["圆形", "圆角方形"])
    }
}

final class PointerHighlightTests: XCTestCase {
    func testHaloIsCenteredOnThePointer() {
        let frame = PointerHighlight.frame(around: CGPoint(x: 500, y: 300))
        XCTAssertEqual(frame.midX, 500, accuracy: 1)
        XCTAssertEqual(frame.midY, 300, accuracy: 1)
        // 窗口放得下放大以后的波纹
        XCTAssertGreaterThanOrEqual(frame.width, PointerHighlight.diameter * PointerHighlight.rippleScale)
        XCTAssertEqual(frame.width, frame.height)
    }
}
