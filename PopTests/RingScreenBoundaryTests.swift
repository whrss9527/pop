import XCTest
@testable import Pop

final class RingScreenBoundaryTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)

    func testMenuBarRemainsAvailableWithoutNotch() {
        let boundary = RingScreenBoundary(screenFrame: screen,
                                          visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 876))
        XCTAssertEqual(boundary.availableFrame, screen)
        XCTAssertTrue(boundary.availableFrame.contains(CGPoint(x: 720, y: 890)))
        XCTAssertTrue(boundary.excludedFrames.isEmpty)
    }

    func testBottomDockStaysExcludedWhileMenuBarOpens() {
        let boundary = RingScreenBoundary(screenFrame: screen,
                                          visibleFrame: CGRect(x: 0, y: 70, width: 1440, height: 806))
        XCTAssertEqual(boundary.availableFrame, CGRect(x: 0, y: 70, width: 1440, height: 830))
        XCTAssertFalse(boundary.availableFrame.contains(CGPoint(x: 720, y: 35)))
    }

    func testSideDockStaysExcludedOnEitherSide() {
        for visible in [CGRect(x: 80, y: 0, width: 1360, height: 876),
                        CGRect(x: 0, y: 0, width: 1360, height: 876)] {
            let boundary = RingScreenBoundary(screenFrame: screen, visibleFrame: visible)
            XCTAssertEqual(boundary.availableFrame.minX, visible.minX)
            XCTAssertEqual(boundary.availableFrame.maxX, visible.maxX)
            XCTAssertEqual(boundary.availableFrame.minY, visible.minY)
            XCTAssertEqual(boundary.availableFrame.maxY, screen.maxY)
        }
    }

    func testNotchOnlyExcludesGapBetweenGlobalAuxiliaryAreas() {
        let boundary = RingScreenBoundary(screenFrame: screen,
                                          visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 868),
                                          topInset: 32,
                                          auxiliaryTopLeft: CGRect(x: 0, y: 868, width: 610, height: 32),
                                          auxiliaryTopRight: CGRect(x: 830, y: 868, width: 610, height: 32),
                                          displayScale: 2)
        XCTAssertEqual(boundary.availableFrame, screen)
        XCTAssertEqual(boundary.excludedFrames, [CGRect(x: 610, y: 868, width: 220, height: 32)])
        XCTAssertEqual(boundary.displayScale, 2)
        XCTAssertFalse(boundary.excludedFrames.contains { $0.contains(CGPoint(x: 400, y: 890)) })
        XCTAssertTrue(boundary.excludedFrames.contains { $0.contains(CGPoint(x: 720, y: 890)) })
    }

    func testNegativeScreenOriginDoesNotTranslateAuxiliaryAreasTwice() {
        let screen = CGRect(x: -1440, y: -900, width: 1440, height: 900)
        let boundary = RingScreenBoundary(screenFrame: screen,
                                          visibleFrame: CGRect(x: -1360, y: -830, width: 1360, height: 798),
                                          topInset: 32,
                                          auxiliaryTopLeft: CGRect(x: -1440, y: -32, width: 610, height: 32),
                                          auxiliaryTopRight: CGRect(x: -610, y: -32, width: 610, height: 32))
        XCTAssertEqual(boundary.availableFrame, CGRect(x: -1360, y: -830, width: 1360, height: 830))
        XCTAssertEqual(boundary.excludedFrames, [CGRect(x: -830, y: -32, width: 220, height: 32)])
    }

    func testMissingAuxiliaryMetadataConservativelyExcludesTopBand() {
        let boundary = RingScreenBoundary(screenFrame: screen, visibleFrame: screen, topInset: 32,
                                          auxiliaryTopLeft: .zero, auxiliaryTopRight: nil)
        XCTAssertEqual(boundary.excludedFrames, [CGRect(x: 0, y: 868, width: 1440, height: 32)])
    }

    func testObstructionIsClippedToAvailableAreaWithSideDock() {
        let boundary = RingScreenBoundary(screenFrame: screen,
                                          visibleFrame: CGRect(x: 80, y: 70, width: 1360, height: 798),
                                          topInset: 32)
        XCTAssertEqual(boundary.excludedFrames, [CGRect(x: 80, y: 868, width: 1360, height: 32)])
    }

    func testDisplayScaleDoesNotChangeLogicalScreenCoordinates() {
        let boundary = RingScreenBoundary(screenFrame: screen, visibleFrame: screen, displayScale: 2)
        XCTAssertEqual(boundary.availableFrame, screen)
        XCTAssertEqual(boundary.displayScale, 2)
        XCTAssertEqual(RingScreenBoundary(screenFrame: screen, visibleFrame: screen, displayScale: .nan).displayScale, 1)
    }
}
