import CoreGraphics
import XCTest
@testable import Pop

/// 生产返回路径使用的边界决策，不创建协调器、窗口或真实剪贴板服务。
final class RingBoundaryReuseTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let visible = CGRect(x: 0, y: 0, width: 1440, height: 876)

    private func boundary(visibleFrame: CGRect? = nil, topInset: CGFloat = 0,
                          left: CGRect? = nil, right: CGRect? = nil, scale: CGFloat = 2) -> RingScreenBoundary {
        RingScreenBoundary(screenFrame: screen, visibleFrame: visibleFrame ?? visible,
                           topInset: topInset, auxiliaryTopLeft: left, auxiliaryTopRight: right, displayScale: scale)
    }

    private func placement(for boundary: RingScreenBoundary) -> RingPlacement {
        RingPlacement(slotCount: 4, anchor: CGPoint(x: 720, y: 450), safeFrame: boundary.availableFrame,
                      excludedFrames: boundary.excludedFrames, displayScale: boundary.displayScale)
    }

    private func matches(_ placement: RingPlacement, _ boundary: RingScreenBoundary) -> Bool {
        placement.matchesBoundary(safeFrame: boundary.availableFrame, excludedFrames: boundary.excludedFrames,
                                  displayScale: boundary.displayScale)
    }

    func testSameScreenIncludingMenuBarRestoresFrozenRing() {
        let current = boundary()
        let frozen = placement(for: current)
        XCTAssertNotEqual(frozen.safeFrame, visible, "旧 visibleFrame 比较会把未变化的屏幕误判为改变")
        XCTAssertTrue(matches(frozen, boundary()))
        XCTAssertEqual(frozen.safeFrame, screen)
    }

    func testBottomAndSideDockChangesRejectReuseInBothDirections() {
        let plain = boundary()
        let frozen = placement(for: plain)
        let dockFrames = [CGRect(x: 0, y: 70, width: 1440, height: 806),
                          CGRect(x: 80, y: 0, width: 1360, height: 876),
                          CGRect(x: 0, y: 0, width: 1360, height: 876)]
        for frame in dockFrames {
            let dock = boundary(visibleFrame: frame)
            XCTAssertFalse(matches(frozen, dock))
            XCTAssertFalse(matches(placement(for: dock), plain), "隐藏 Dock 后也不能复用旧边界")
        }
    }

    func testNotchChangesRejectReuseWithTheSameAvailableFrame() {
        let plain = boundary()
        let notch = boundary(topInset: 32, left: CGRect(x: 0, y: 868, width: 610, height: 32),
                             right: CGRect(x: 830, y: 868, width: 610, height: 32))
        XCTAssertEqual(plain.availableFrame, notch.availableFrame)
        XCTAssertFalse(matches(placement(for: plain), notch))
        let frozen = placement(for: notch)
        XCTAssertTrue(matches(frozen, notch))
        XCTAssertFalse(matches(frozen, plain))
        let widerNotch = boundary(topInset: 32, left: CGRect(x: 0, y: 868, width: 600, height: 32),
                                  right: CGRect(x: 840, y: 868, width: 600, height: 32))
        XCTAssertFalse(matches(frozen, widerNotch))
    }

    func testDisplayScaleChangesRejectReuseWithoutChangingLogicalFrame() {
        let frozen = placement(for: boundary(scale: 2))
        for scale: CGFloat in [1, 1.5, 3] {
            let changed = boundary(scale: scale)
            XCTAssertEqual(changed.availableFrame, frozen.safeFrame)
            XCTAssertFalse(matches(frozen, changed))
        }
        XCTAssertTrue(matches(frozen, boundary(scale: 2)))
    }

    func testScreenOffsetAndExtentChangesRejectReuse() {
        let frozen = placement(for: boundary())
        for changed in [screen.offsetBy(dx: -1440, dy: 0), screen.offsetBy(dx: 0, dy: -900),
                        screen.insetBy(dx: -100, dy: 0), screen.insetBy(dx: 0, dy: 1)] {
            XCTAssertFalse(frozen.matchesBoundary(safeFrame: changed, excludedFrames: [], displayScale: 2),
                           "即使旧圆盘仍在新范围内，屏幕原点或尺寸改变也须取消")
        }
    }

    func testScaleNormalizationMatchesTheSolverAndIsNotAWildcard() {
        let one = placement(for: boundary(scale: 1))
        let two = placement(for: boundary(scale: 2))
        let scales: [CGFloat] = [0, -1, 0.5, .nan, .infinity]
        for scale in scales {
            let normalized = RingPlacement(slotCount: 4, anchor: CGPoint(x: 720, y: 450),
                                            safeFrame: screen, displayScale: scale)
            XCTAssertEqual(normalized.displayScale, 1)
            XCTAssertTrue(one.matchesBoundary(safeFrame: screen, excludedFrames: [], displayScale: scale))
            XCTAssertFalse(two.matchesBoundary(safeFrame: screen, excludedFrames: [], displayScale: scale))
        }
        let fractional = placement(for: boundary(scale: 1.25))
        XCTAssertEqual(fractional.displayScale, 1.25)
        XCTAssertTrue(matches(fractional, boundary(scale: 1.25)))
        XCTAssertFalse(matches(fractional, boundary(scale: 1)))
    }

    func testNewOrInvalidExclusionsAndEmptyBoundsDoNotBypassTheGuard() {
        let frozen = placement(for: boundary())
        for exclusion in [CGRect(x: 100, y: 100, width: 20, height: 20), .zero, .null, .infinite] {
            XCTAssertFalse(frozen.matchesBoundary(safeFrame: screen, excludedFrames: [exclusion], displayScale: 2))
        }
        for invalid in [CGRect.zero, .null, .infinite] {
            XCTAssertFalse(frozen.matchesBoundary(safeFrame: invalid, excludedFrames: [], displayScale: 2))
        }
        let empty = RingPlacement(slotCount: 4, anchor: .zero, safeFrame: .zero)
        XCTAssertFalse(empty.matchesBoundary(safeFrame: .zero, excludedFrames: [], displayScale: 1))
    }
}
