import XCTest
@testable import Pop

final class GeometryTests: XCTestCase {
    private let ring = RingGeometry(slotCount: 8, innerRadius: 38, outerRadius: 124)

    func testSlotDirectionsClockwiseFromTop() {
        XCTAssertEqual(ring.slot(at: CGVector(dx: 0, dy: 100)), 0)
        XCTAssertEqual(ring.slot(at: CGVector(dx: 100, dy: 100)), 1)
        XCTAssertEqual(ring.slot(at: CGVector(dx: 100, dy: 0)), 2)
        XCTAssertEqual(ring.slot(at: CGVector(dx: 100, dy: -100)), 3)
        XCTAssertEqual(ring.slot(at: CGVector(dx: 0, dy: -100)), 4)
        XCTAssertEqual(ring.slot(at: CGVector(dx: -100, dy: -100)), 5)
        XCTAssertEqual(ring.slot(at: CGVector(dx: -100, dy: 0)), 6)
        XCTAssertEqual(ring.slot(at: CGVector(dx: -100, dy: 100)), 7)
    }

    func testWrapAroundNearTopAndDeadZone() {
        XCTAssertEqual(ring.slot(at: CGVector(dx: -5, dy: 100)), 0)
        XCTAssertEqual(ring.slot(at: CGVector(dx: 5, dy: 100)), 0)
        XCTAssertNil(ring.slot(at: CGVector(dx: 10, dy: 10)))
        // 只看方向不看距离：划出圆盘外也能选中
        XCTAssertEqual(ring.slot(at: CGVector(dx: 1000, dy: 0)), 2)
    }

    func testOtherSlotCounts() {
        let four = RingGeometry(slotCount: 4)
        XCTAssertEqual(four.slot(at: CGVector(dx: 100, dy: 0)), 1)
        XCTAssertEqual(four.slot(at: CGVector(dx: 0, dy: -100)), 2)
        XCTAssertEqual(four.slot(at: CGVector(dx: -100, dy: 0)), 3)
        let twelve = RingGeometry(slotCount: 12)
        XCTAssertEqual(twelve.slot(at: CGVector(dx: 100, dy: 0)), 3)
    }

    func testSlotCentersAndSectors() {
        let top = ring.slotCenterOffset(0)
        XCTAssertEqual(top.dx, 0, accuracy: 0.001)
        XCTAssertEqual(top.dy, ring.labelRadius, accuracy: 0.001)
        let right = ring.slotCenterOffset(2)
        XCTAssertEqual(right.dx, ring.labelRadius, accuracy: 0.001)
        XCTAssertEqual(right.dy, 0, accuracy: 0.001)
        // 每一格的中心都应该落回这一格
        for index in 0..<8 {
            XCTAssertEqual(ring.slot(at: ring.slotCenterOffset(index)), index)
        }
        let sector = ring.sectorDegrees(0)
        XCTAssertEqual(sector.start, -112.5, accuracy: 0.001)
        XCTAssertEqual(sector.end, -67.5, accuracy: 0.001)
    }

    func testCoordinateConversion() {
        let point = ScreenGeometry.appKitPoint(fromQuartz: CGPoint(x: 100, y: 50), primaryScreenHeight: 900)
        XCTAssertEqual(point, CGPoint(x: 100, y: 850))
    }

    func testRingFrameIsClampedIntoScreen() {
        let bounds = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let centered = ScreenGeometry.ringFrame(center: CGPoint(x: 700, y: 450), diameter: 280, within: bounds)
        XCTAssertEqual(centered, CGRect(x: 560, y: 310, width: 280, height: 280))
        let nearCorner = ScreenGeometry.ringFrame(center: CGPoint(x: 10, y: 890), diameter: 280, within: bounds)
        XCTAssertEqual(nearCorner.minX, 0)
        XCTAssertEqual(nearCorner.maxY, 900)
    }

    /// 圆盘靠边挪开了多少：指针要跟着挪过去，按住划动的方向才和看到的一致
    func testRingShiftNearEdges() {
        let bounds = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let middle = CGPoint(x: 700, y: 450)
        let centered = ScreenGeometry.ringFrame(center: middle, diameter: 280, within: bounds)
        XCTAssertNil(ScreenGeometry.ringShift(anchor: middle, center: CGPoint(x: centered.midX, y: centered.midY)))

        let corner = CGPoint(x: 10, y: 890)
        let moved = ScreenGeometry.ringFrame(center: corner, diameter: 280, within: bounds)
        let shift = ScreenGeometry.ringShift(anchor: corner, center: CGPoint(x: moved.midX, y: moved.midY))
        XCTAssertEqual(shift, CGVector(dx: 130, dy: -130))

        // 靠右边：只往左挪
        let right = CGPoint(x: 1430, y: 450)
        let movedLeft = ScreenGeometry.ringFrame(center: right, diameter: 280, within: bounds)
        XCTAssertEqual(ScreenGeometry.ringShift(anchor: right, center: CGPoint(x: movedLeft.midX, y: movedLeft.midY)),
                       CGVector(dx: -130, dy: 0))
        // 不到 1 点的差别不算挪开
        XCTAssertNil(ScreenGeometry.ringShift(anchor: middle, center: CGPoint(x: 700.5, y: 450.5)))
    }

    func testCardFramePrefersBottomRightAndFlips() {
        let bounds = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let size = CGSize(width: 400, height: 200)
        XCTAssertEqual(ScreenGeometry.cardFrame(anchor: CGPoint(x: 100, y: 800), size: size, within: bounds),
                       CGRect(x: 114, y: 586, width: 400, height: 200))
        // 右边放不下：放到指针左边
        XCTAssertEqual(ScreenGeometry.cardFrame(anchor: CGPoint(x: 1400, y: 800), size: size, within: bounds).minX, 986)
        // 下面放不下：放到指针上方
        XCTAssertEqual(ScreenGeometry.cardFrame(anchor: CGPoint(x: 100, y: 100), size: size, within: bounds).minY, 114)
    }

    func testPinFrames() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        XCTAssertEqual(ScreenGeometry.fitted(CGSize(width: 2000, height: 1000), within: CGSize(width: 1000, height: 1000)),
                       CGSize(width: 1000, height: 500))
        XCTAssertEqual(ScreenGeometry.fitted(CGSize(width: 200, height: 100), within: CGSize(width: 1000, height: 1000)),
                       CGSize(width: 200, height: 100))
        XCTAssertEqual(ScreenGeometry.pinFrame(size: CGSize(width: 200, height: 100), centeredAt: CGPoint(x: 500, y: 500),
                                               within: screen),
                       CGRect(x: 400, y: 450, width: 200, height: 100))
        // 刚框选的截图：右下角对着松开鼠标的位置，正好盖住原来的区域
        XCTAssertEqual(ScreenGeometry.pinFrame(size: CGSize(width: 300, height: 200), bottomRightAt: CGPoint(x: 800, y: 300),
                                               within: screen),
                       CGRect(x: 500, y: 300, width: 300, height: 200))
        // 靠近屏幕边缘时往里挪
        XCTAssertEqual(ScreenGeometry.pinFrame(size: CGSize(width: 200, height: 100), centeredAt: CGPoint(x: 10, y: 10),
                                               within: screen).origin,
                       .zero)
    }

    /// 缩放时指针下面的那一点不动
    func testResizeKeepsThePointUnderThePointer() {
        let frame = CGRect(x: 100, y: 100, width: 200, height: 100)
        XCTAssertEqual(ScreenGeometry.resized(frame, to: CGSize(width: 400, height: 200), keeping: CGPoint(x: 150, y: 125)),
                       CGRect(x: 50, y: 75, width: 400, height: 200))
        XCTAssertEqual(ScreenGeometry.resized(frame, to: CGSize(width: 100, height: 50), keeping: CGPoint(x: 200, y: 150)),
                       CGRect(x: 150, y: 125, width: 100, height: 50))
    }
}
