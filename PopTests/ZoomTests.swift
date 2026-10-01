import XCTest
@testable import Pop

final class ZoomTests: XCTestCase {
    func testContentUnderThePointerStaysPut() {
        let size = CGSize(width: 1440, height: 900)
        for pointer in [CGPoint(x: 0, y: 0), CGPoint(x: 720, y: 450), CGPoint(x: 1000, y: 300), CGPoint(x: 1440, y: 900)] {
            for scale in [1.25, 2, 4, 8] as [CGFloat] {
                let frame = ScreenZoom.imageFrame(pointer: pointer, size: size, scale: scale)
                XCTAssertEqual(frame.width, size.width * scale)
                // 指针下面是放大前它下面的那一点
                XCTAssertEqual((pointer.x - frame.minX) / scale, pointer.x, accuracy: 0.001)
                XCTAssertEqual((pointer.y - frame.minY) / scale, pointer.y, accuracy: 0.001)
                // 放大的画面总是盖满屏幕
                XCTAssertLessThanOrEqual(frame.minX, 0.001)
                XCTAssertGreaterThanOrEqual(frame.maxX, size.width - 0.001)
                XCTAssertLessThanOrEqual(frame.minY, 0.001)
                XCTAssertGreaterThanOrEqual(frame.maxY, size.height - 0.001)
            }
        }
        // 指针在左下角看到左下角，在右上角看到右上角
        XCTAssertEqual(ScreenZoom.imageFrame(pointer: .zero, size: size, scale: 2).origin, .zero)
        XCTAssertEqual(ScreenZoom.imageFrame(pointer: CGPoint(x: 1440, y: 900), size: size, scale: 2).origin, CGPoint(x: -1440, y: -900))
        // 指针跑出屏幕时按屏幕边算
        XCTAssertEqual(ScreenZoom.imageFrame(pointer: CGPoint(x: -50, y: 2000), size: size, scale: 2).origin, CGPoint(x: 0, y: -900))
    }

    func testScaleStaysInRange() {
        XCTAssertEqual(ScreenZoom.clamped(1), 1.25)
        XCTAssertEqual(ScreenZoom.clamped(3), 3)
        XCTAssertEqual(ScreenZoom.clamped(20), 8)
        XCTAssertTrue(ScreenZoom.scales.contains(ScreenZoom.initialScale))
    }

    @MainActor
    func testDemoSnapshotCoversTheScreen() throws {
        let sample = try XCTUnwrap(CGContext(data: nil, width: 48, height: 30, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage())
        let snapshot = try XCTUnwrap(ScreenZoom.demoSnapshot(size: CGSize(width: 400, height: 300), scale: 2, sample: sample,
                                                            in: CGRect(x: 10, y: 10, width: 48, height: 30)))
        XCTAssertEqual(snapshot.width, 800)
        XCTAssertEqual(snapshot.height, 600)
    }

    @MainActor
    func testPluginNeedsNoContent() {
        let info = ZoomPlugin().info
        XCTAssertTrue(info.canHandle(.empty))
        XCTAssertTrue(info.hidesOverlay)
        XCTAssertFalse(ScreenZoom.shared.isActive)
    }
}
