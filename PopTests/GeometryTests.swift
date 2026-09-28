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
}
