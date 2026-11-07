import XCTest
@testable import Pop

final class GeometryTests: XCTestCase {
    private let ring = RingGeometry(slotCount: 8, innerRadius: 38, outerRadius: 124)
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)

    func testSlotDirectionsClockwiseFromTop() {
        let directions: [CGVector] = [CGVector(dx: 0, dy: 100), CGVector(dx: 100, dy: 100),
            CGVector(dx: 100, dy: 0), CGVector(dx: 100, dy: -100), CGVector(dx: 0, dy: -100),
            CGVector(dx: -100, dy: -100), CGVector(dx: -100, dy: 0), CGVector(dx: -100, dy: 100)]
        for (index, vector) in directions.enumerated() { XCTAssertEqual(ring.slot(at: vector), index) }
    }

    func testWrapAroundNearTopAndDeadZone() {
        XCTAssertEqual(ring.slot(at: CGVector(dx: -5, dy: 100)), 0)
        XCTAssertEqual(ring.slot(at: CGVector(dx: 5, dy: 100)), 0)
        XCTAssertNil(ring.slot(at: CGVector(dx: 10, dy: 10)))
        XCTAssertEqual(ring.slot(at: CGVector(dx: 1000, dy: 0)), 2)
    }

    func testOtherSlotCounts() {
        XCTAssertEqual(RingGeometry(slotCount: 4).slot(at: CGVector(dx: 100, dy: 0)), 1)
        XCTAssertEqual(RingGeometry(slotCount: 4).slot(at: CGVector(dx: 0, dy: -100)), 2)
        XCTAssertEqual(RingGeometry(slotCount: 12).slot(at: CGVector(dx: 100, dy: 0)), 3)
    }

    func testSlotCentersAndSectors() {
        XCTAssertEqual(ring.slotCenterOffset(0).dx, 0, accuracy: 0.001)
        XCTAssertEqual(ring.slotCenterOffset(0).dy, ring.labelRadius, accuracy: 0.001)
        for index in 0..<8 { XCTAssertEqual(ring.slot(at: ring.slotCenterOffset(index)), index) }
        XCTAssertEqual(ring.sectorDegrees(0).start, -112.5, accuracy: 0.001)
        XCTAssertEqual(ring.sectorDegrees(0).end, -67.5, accuracy: 0.001)
    }

    func testButtonMetricsUseTheOriginalCircleChord() {
        for count in [1, 2, 3, 4, 6, 8, 10, 12] {
            let original = RingGeometry(slotCount: count, outerRadius: RingGeometry.outerRadius(forSlotCount: count))
            let width = min(60, max(36, 2 * original.labelRadius * sin(.pi / CGFloat(count)) - 12))
            let metrics = RingButtonMetrics(slotCount: count)
            XCTAssertEqual(metrics.bodySize, CGSize(width: width, height: min(54, width)))
            XCTAssertEqual(metrics.cornerRadius, min(14, width * 0.28))
        }
    }

    func testDefaultAppearancePreservesMetricsAndPlacement() {
        let anchor = CGPoint(x: 0, y: 450)
        XCTAssertEqual(RingButtonMetrics(slotCount: 8), RingButtonMetrics(slotCount: 8, appearance: .default))
        XCTAssertEqual(RingPlacement(slotCount: 8, anchor: anchor, safeFrame: screen, displayScale: 2),
                       RingPlacement(slotCount: 8, anchor: anchor, safeFrame: screen, displayScale: 2, appearance: .default))
    }

    func testRoundedAppearanceScalesActualWidthAndHeight() {
        let metrics = RingButtonMetrics(slotCount: 4, appearance: RingAppearance(scale: 1.25))
        XCTAssertEqual(metrics.bodySize, CGSize(width: 75, height: 67.5))
        XCTAssertEqual(metrics.cornerRadius, 17.5)
        let small = RingButtonMetrics(slotCount: 12, appearance: RingAppearance(scale: 0.8))
        XCTAssertEqual(small.bodySize, CGSize(width: 36, height: 36))
    }

    func testCircleAndSquareHaveSquareConfiguredBodies() {
        let circle = RingButtonMetrics(slotCount: 4, appearance: RingAppearance(shape: .circle, scale: 1.2))
        let square = RingButtonMetrics(slotCount: 4, appearance: RingAppearance(shape: .square, scale: 1.2))
        XCTAssertEqual(circle.bodySize, CGSize(width: 72, height: 72))
        XCTAssertEqual(square.bodySize, circle.bodySize)
        XCTAssertEqual(circle.cornerRadius, 36)
        XCTAssertEqual(square.cornerRadius, 0)
    }

    func testPlacementStoresNormalizedAppearance() {
        var invalid = RingAppearance(shape: .circle)
        invalid.scale = .infinity
        let placement = RingPlacement(slotCount: 4, anchor: CGPoint(x: 720, y: 450), safeFrame: screen,
                                      appearance: invalid)
        XCTAssertEqual(placement.appearance, RingAppearance(shape: .circle, scale: 1))
        XCTAssertEqual(placement.buttonSize, CGSize(width: 60, height: 60))
        assertSafe(placement)
    }

    func testConfiguredShapeAndSizeDriveRealScreenAndExclusionFootprints() {
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 650)
        let notch = CGRect(x: 420, y: 618, width: 160, height: 32)
        for shape in RingButtonShape.allCases {
            for scale in [0.8, 1.6] {
                for displayScale: CGFloat in [1, 2] {
                    let appearance = RingAppearance(shape: shape, scale: scale)
                    let metrics = RingButtonMetrics(slotCount: 12, appearance: appearance)
                    for anchor in [CGPoint.zero, CGPoint(x: 500, y: 650)] {
                        let placement = RingPlacement(slotCount: 12, anchor: anchor, safeFrame: bounds,
                                                      excludedFrames: [notch], displayScale: displayScale,
                                                      appearance: appearance)
                        XCTAssertEqual(placement.appearance, appearance.normalized)
                        XCTAssertEqual(placement.buttonSize, metrics.bodySize)
                        for index in 0..<placement.visibleSlotCount {
                            XCTAssertEqual(placement.labelFrame(index, hoverSafe: false).size, metrics.bodySize)
                        }
                        assertSafe(placement)
                    }
                }
            }
        }
    }

    func testLargerConfiguredTargetsChangeCapacityInsteadOfUsingOldMetrics() {
        let bounds = CGRect(x: 0, y: 0, width: 320, height: 240)
        let normal = RingPlacement(slotCount: 12, anchor: .zero, safeFrame: bounds, displayScale: 2)
        let large = RingPlacement(slotCount: 12, anchor: .zero, safeFrame: bounds, displayScale: 2,
                                  appearance: RingAppearance(shape: .square, scale: 1.6))
        XCTAssertGreaterThan(large.buttonSize.width, normal.buttonSize.width)
        XCTAssertGreaterThan(large.buttonSize.height, normal.buttonSize.height)
        XCTAssertLessThan(large.visibleSlotCount, normal.visibleSlotCount)
        XCTAssertTrue(large.hasOverflow)
        assertSafe(normal)
        assertSafe(large)
    }

    func testFullCircleIsKeptWhenActualButtonsAndHubFit() {
        let anchor = CGPoint(x: 720, y: 450)
        let placement = RingPlacement(slotCount: 4, anchor: anchor, safeFrame: screen)
        XCTAssertTrue(placement.geometry.isFullCircle)
        XCTAssertEqual(placement.geometry.labelRadius, ring.labelRadius)
        XCTAssertEqual(placement.displayOrder, [0, 1, 2, 3])
        XCTAssertNotNil(placement.hubFrame)
        XCTAssertFalse(placement.hasOverflow)
        assertSafe(placement)
    }

    func testTransparentWindowPaddingCannotForceEdgeMode() {
        let centered = RingPlacement(slotCount: 4, anchor: CGPoint(x: 720, y: 450), safeFrame: screen)
        let nearEdge = RingPlacement(slotCount: 4, anchor: CGPoint(x: 120, y: 450), safeFrame: screen)
        // 原窗口 outerRadius124+padding22 超出边界，但真实按钮阴影仍完整可见。
        XCTAssertLessThan(nearEdge.anchor.x, 124 + RingPlacement.padding)
        XCTAssertTrue(nearEdge.geometry.isFullCircle)
        XCTAssertEqual(nearEdge.geometry, centered.geometry)
        XCTAssertEqual(nearEdge.frame.minX, screen.minX)
        assertSafe(nearEdge)
    }

    func testTwelveItemCircleDoesNotOverlapOrMisrouteItsCorners() {
        let placement = RingPlacement(slotCount: 12, anchor: CGPoint(x: 720, y: 450), safeFrame: screen, displayScale: 2)
        XCTAssertTrue(placement.geometry.isFullCircle)
        XCTAssertEqual(placement.visibleSlotCount, 12)
        assertSafe(placement)
    }

    func testAnalyticRegularCircleKeepsNominalDirectionsAndActionOrder() {
        for count in [8, 12] {
            let placement = RingPlacement(slotCount: count, anchor: CGPoint(x: 720, y: 450),
                                          safeFrame: screen, displayScale: 2)
            XCTAssertTrue(placement.geometry.isFullCircle)
            XCTAssertEqual(placement.displayOrder, Array(0..<count))
            for index in 0..<count {
                XCTAssertEqual(placement.geometry.slotCenterDegrees(index), -90 + Double(index) * 360 / Double(count),
                               accuracy: 0.000_001)
            }
            assertSafe(placement)
        }
    }

    func testHubUsesItsActualSeventyTwoPointBodyOrIsOmitted() {
        let interior = RingPlacement(slotCount: 8, anchor: CGPoint(x: 60, y: 450), safeFrame: screen)
        XCTAssertEqual(interior.hubFrame?.size, CGSize(width: 72, height: 72))
        let edge = RingPlacement(slotCount: 8, anchor: CGPoint(x: 0, y: 450), safeFrame: screen)
        XCTAssertNil(edge.hubFrame)
        let notch = CGRect(x: 700, y: 850, width: 40, height: 50)
        let nearNotch = RingPlacement(slotCount: 8, anchor: CGPoint(x: 720, y: 840), safeFrame: screen,
                                      excludedFrames: [notch])
        XCTAssertNil(nearNotch.hubFrame)
        assertSafe(interior)
        assertSafe(edge)
        assertSafe(nearNotch)
    }

    func testAllConfiguredActionsFitAtEveryPhysicalEdgeAndCorner() {
        let anchors = [CGPoint(x: 0, y: 450), CGPoint(x: 1440, y: 450), CGPoint(x: 720, y: 0), CGPoint(x: 720, y: 900),
            CGPoint.zero, CGPoint(x: 1440, y: 0), CGPoint(x: 1440, y: 900), CGPoint(x: 0, y: 900)]
        for count in [3, 4, 8, 12] {
            for anchor in anchors {
                let placement = RingPlacement(slotCount: count, anchor: anchor, safeFrame: screen, displayScale: 2)
                XCTAssertEqual(placement.anchor, anchor)
                XCTAssertEqual(placement.visibleSlotCount, count, "\(count) items at \(anchor)")
                XCTAssertFalse(placement.hasOverflow)
                assertSafe(placement)
            }
        }
    }

    func testCornerGrowsFromRealPixelsInsteadOfKeepingOnlyTwoOrFourItems() {
        let placement = RingPlacement(slotCount: 12, anchor: .zero, safeFrame: screen, displayScale: 2)
        XCTAssertEqual(placement.visibleSlotCount, 12)
        XCTAssertFalse(placement.hasOverflow)
        XCTAssertGreaterThan(placement.geometry.labelRadius, 140, "不能保留旧样式上限而过早进入更多")
        XCTAssertEqual(placement.buttonSize, RingButtonMetrics(slotCount: 12).bodySize)
        assertSafe(placement)
    }

    func testFixedMetricsSurviveEdgeChangesAndOverflow() {
        for count in [4, 8, 12] {
            let expected = RingButtonMetrics(slotCount: count).bodySize
            for (anchor, bounds) in [(CGPoint(x: 720, y: 450), screen), (CGPoint.zero, screen),
                                     (CGPoint(x: 2, y: 2), CGRect(x: 0, y: 0, width: 180, height: 160))] {
                let placement = RingPlacement(slotCount: count, anchor: anchor, safeFrame: bounds)
                XCTAssertEqual(placement.buttonSize, expected)
                for index in 0..<placement.visibleSlotCount {
                    XCTAssertEqual(placement.labelFrame(index, hoverSafe: false).size, expected)
                }
                assertSafe(placement)
            }
        }
    }

    func testMoreAppearsOnlyWhenTheAvailableSingleRingCannotHoldAllTargets() {
        let bounds = CGRect(x: 0, y: 0, width: 72, height: 900)
        let placement = RingPlacement(slotCount: 12, anchor: CGPoint(x: 0, y: 450), safeFrame: bounds, displayScale: 2)
        XCTAssertTrue(placement.hasOverflow)
        XCTAssertLessThan(placement.visibleSlotCount, 12)
        let direct = placement.visibleSlotCount - 1
        XCTAssertEqual(direct + (12 - direct), 12)
        XCTAssertEqual(Set(placement.displayOrder), Set(0..<placement.visibleSlotCount))
        assertSafe(placement)
    }

    func testSmallScreenKeepsUsableOriginalSizeTargetsAndMore() {
        let bounds = CGRect(x: 0, y: 0, width: 180, height: 160)
        let placement = RingPlacement(slotCount: 12, anchor: CGPoint(x: 2, y: 2), safeFrame: bounds)
        XCTAssertTrue(placement.hasOverflow)
        XCTAssertGreaterThan(placement.visibleSlotCount, 1)
        XCTAssertLessThan(placement.visibleSlotCount, 12)
        assertSafe(placement)
    }

    func testButtonExactlyTangentToDeadZoneStillBelongsToItself() {
        // 旧角度三角函数往返会得到37.99999999999999，被误当作死区。
        let placement = RingPlacement(slotCount: 12, anchor: CGPoint(x: 0, y: 450),
                                      safeFrame: CGRect(x: 0, y: 0, width: 72, height: 900), displayScale: 2)
        assertSafe(placement)
        XCTAssertEqual(ring.slot(at: CGVector(dx: CGFloat(Double(38).nextDown), dy: 0)), 2)
        XCTAssertNil(placement.geometry.slot(at: CGVector(dx: 37.99, dy: 0)))
    }

    func testRealNotchExclusionsDoNotForceMissingActions() {
        let notch = CGRect(x: 650, y: 870, width: 140, height: 30)
        for anchor in [CGPoint(x: 720, y: 860), CGPoint(x: 640, y: 880), CGPoint(x: 800, y: 880)] {
            let placement = RingPlacement(slotCount: 8, anchor: anchor, safeFrame: screen,
                                          excludedFrames: [notch], displayScale: 2)
            XCTAssertEqual(placement.visibleSlotCount, 8)
            XCTAssertFalse(placement.hasOverflow)
            assertSafe(placement)
        }
    }

    func testActualPointerInExclusionCannotSelectAnOtherwiseValidDirection() {
        let exclusion = CGRect(x: 980, y: 440, width: 30, height: 20)
        let anchor = CGPoint(x: 720, y: 450)
        let placement = RingPlacement(slotCount: 4, anchor: anchor, safeFrame: screen, excludedFrames: [exclusion])
        let offset = CGVector(dx: exclusion.midX - anchor.x, dy: exclusion.midY - anchor.y)
        XCTAssertNotNil(placement.geometry.slot(at: offset), "证明回归确实经过禁区过滤")
        XCTAssertNil(placement.slot(at: offset))
        assertSafe(placement)
    }

    func testTopMenuBarPixelsAreAvailableWhenIncludedInPhysicalBounds() {
        let placement = RingPlacement(slotCount: 4, anchor: CGPoint(x: 720, y: 790), safeFrame: screen)
        XCTAssertTrue((0..<placement.visibleSlotCount).contains { placement.labelFrame($0).maxY > 876 })
        XCTAssertFalse(placement.hasOverflow)
        assertSafe(placement)
    }

    func testCyclicCutPreservesActionOrderAndMinimizesIdentityDisplacement() {
        let placement = RingPlacement(slotCount: 8, anchor: CGPoint(x: 0, y: 450), safeFrame: screen, displayScale: 2)
        XCTAssertNotEqual(placement.displayOrder, Array(0..<8))
        for index in 0..<8 {
            XCTAssertEqual(placement.displayOrder[(index + 1) % 8], (placement.displayOrder[index] + 1) % 8)
        }
        func score(_ rotation: Int) -> Double {
            (0..<8).reduce(0.0) { sum, index in
                let desired = -90 + Double((index + rotation) % 8) * 45
                let delta = (placement.geometry.slotCenterDegrees(index) - desired).remainder(dividingBy: 360)
                return sum + delta * delta
            }
        }
        let actual = score(placement.displayOrder[0])
        for rotation in 0..<8 { XCTAssertLessThanOrEqual(actual, score(rotation) + 0.000_001) }
        assertSafe(placement)
    }

    func testNearbyCornerKeepsThePreferredCutAndOriginalIDsNearTheirPreviousPositions() {
        let first = RingPlacement(slotCount: 8, anchor: CGPoint(x: 0.5, y: 0), safeFrame: screen, displayScale: 2)
        let second = RingPlacement(slotCount: 8, anchor: CGPoint(x: 0, y: 0.5), safeFrame: screen, displayScale: 2,
                                   preferredDisplayOrder: first.displayOrder)
        XCTAssertEqual(second.displayOrder, first.displayOrder)
        for physical in 0..<8 {
            let before = first.geometry.slotCenterOffset(physical)
            let after = second.geometry.slotCenterOffset(physical)
            XCTAssertLessThan(hypot(before.dx - after.dx, before.dy - after.dy), first.buttonSize.width / 4,
                              "半像素邻近唤起不能把同一个动作换到扇形另一端")
        }
        assertSafe(first)
        assertSafe(second)
    }

    func testInvalidOrDifferentCapacityPreferredOrdersAreIgnored() {
        let anchor = CGPoint(x: 0, y: 450)
        let expected = RingPlacement(slotCount: 8, anchor: anchor, safeFrame: screen, displayScale: 2)
        for invalid in [[], [0], Array(0..<7), Array(repeating: 0, count: 8),
                        [0, 2, 1, 3, 4, 5, 6, 7], [-1, 0, 1, 2, 3, 4, 5, 6]] {
            XCTAssertEqual(RingPlacement(slotCount: 8, anchor: anchor, safeFrame: screen, displayScale: 2,
                                         preferredDisplayOrder: invalid), expected)
        }
        let bounds = CGRect(x: 0, y: 0, width: 320, height: 240)
        let overflow = RingPlacement(slotCount: 12, anchor: .zero, safeFrame: bounds, displayScale: 2)
        XCTAssertTrue(overflow.hasOverflow)
        XCTAssertEqual(RingPlacement(slotCount: 12, anchor: .zero, safeFrame: bounds, displayScale: 2,
                                     preferredDisplayOrder: Array(0..<12)), overflow)
    }

    func testPreferredOrderCanRetainAnOverflowCutButCannotRotateTheNormalCircle() {
        let bounds = CGRect(x: 0, y: 0, width: 320, height: 240)
        let first = RingPlacement(slotCount: 12, anchor: .zero, safeFrame: bounds, displayScale: 2)
        let rotated = (0..<first.visibleSlotCount).map { ($0 + 1) % first.visibleSlotCount }
        let preferred = RingPlacement(slotCount: 12, anchor: .zero, safeFrame: bounds, displayScale: 2,
                                      preferredDisplayOrder: rotated)
        XCTAssertEqual(preferred.visibleSlotCount, first.visibleSlotCount)
        XCTAssertEqual(preferred.displayOrder, rotated)
        assertSafe(preferred)
        let normal = RingPlacement(slotCount: 8, anchor: CGPoint(x: 720, y: 450), safeFrame: screen,
                                   displayScale: 2, preferredDisplayOrder: [6, 7, 0, 1, 2, 3, 4, 5])
        XCTAssertTrue(normal.geometry.isFullCircle)
        XCTAssertEqual(normal.displayOrder, Array(0..<8))
        assertSafe(normal)
    }

    func testSmallerRadiusIsStillSearchedBeforeHidingConfiguredActions() {
        let normal = RingPlacement(slotCount: 12, anchor: CGPoint(x: 720, y: 450), safeFrame: screen, displayScale: 2)
        let compact = RingPlacement(slotCount: 12, anchor: CGPoint(x: 145, y: 145),
                                    safeFrame: CGRect(x: 0, y: 0, width: 290, height: 290), displayScale: 2)
        XCTAssertEqual(compact.visibleSlotCount, 12)
        XCTAssertFalse(compact.hasOverflow, "首选自然半径放不下时，必须先尝试更小可行半径")
        XCTAssertLessThan(compact.geometry.labelRadius, normal.geometry.labelRadius)
        assertSafe(compact)
    }

    func testRestoringTheRegularCircleDoesNotSwapByAWholeButton() {
        for count in [8, 12] {
            var previous: RingPlacement?
            for x in 110...160 {
                let placement = RingPlacement(slotCount: count, anchor: CGPoint(x: x, y: 450), safeFrame: screen,
                                              displayScale: 2, preferredDisplayOrder: previous?.displayOrder)
                if let previous {
                    for action in 0..<count {
                        let before = previous.geometry.slotCenterOffset(previous.displayOrder.firstIndex(of: action)!)
                        let after = placement.geometry.slotCenterOffset(placement.displayOrder.firstIndex(of: action)!)
                        XCTAssertLessThan(hypot(before.dx - after.dx, before.dy - after.dy), placement.buttonSize.width / 3,
                                          "逐点恢复整圆应逐步回到正常方向，不能跳一个完整按钮")
                    }
                }
                previous = placement
            }
        }
    }

    func testNoActionsDisappearAsAnchorMovesFromEdgeToCenter() {
        for distance: CGFloat in [0, 1, 12, 35, 64, 100, 145, 220, 450] {
            let placement = RingPlacement(slotCount: 8, anchor: CGPoint(x: 720, y: 900 - distance),
                                          safeFrame: screen, displayScale: 2)
            XCTAssertEqual(placement.visibleSlotCount, 8)
            XCTAssertFalse(placement.hasOverflow)
            assertSafe(placement)
        }
    }

    func testPixelSearchUsesTheScreenScale() {
        for scale: CGFloat in [1, 2] {
            let placement = RingPlacement(slotCount: 12, anchor: .zero, safeFrame: screen, displayScale: scale)
            XCTAssertEqual(placement.geometry.labelRadius * scale,
                           (placement.geometry.labelRadius * scale).rounded(), accuracy: 0.000_001)
            assertSafe(placement)
        }
    }

    func testTranslatedFractionalMonitorsPreserveActionGeometry() {
        let anchor = CGPoint(x: 0, y: 450)
        let original = RingPlacement(slotCount: 8, anchor: anchor, safeFrame: screen, displayScale: 2)
        for shift in [CGVector(dx: -1440, dy: -900), CGVector(dx: -1728.5, dy: 400.25)] {
            let translated = RingPlacement(slotCount: 8, anchor: CGPoint(x: anchor.x + shift.dx, y: anchor.y + shift.dy),
                                           safeFrame: screen.offsetBy(dx: shift.dx, dy: shift.dy), displayScale: 2)
            XCTAssertEqual(translated.geometry.labelRadius, original.geometry.labelRadius, accuracy: 0.000_001)
            XCTAssertEqual(translated.displayOrder, original.displayOrder)
            for index in 0..<8 {
                XCTAssertEqual(translated.geometry.slotCenterDegrees(index), original.geometry.slotCenterDegrees(index), accuracy: 0.000_001)
            }
            assertSafe(translated)
        }
    }

    func testPlacementIsDeterministicAndStatusDoesNotConsumeCapacity() {
        let placement = RingPlacement(slotCount: 12, anchor: .zero, safeFrame: screen, displayScale: 2)
        XCTAssertEqual(placement, RingPlacement(slotCount: 12, anchor: .zero, safeFrame: screen, displayScale: 2))
        XCTAssertNil(placement.statusFrame)
        XCTAssertEqual(placement.visibleSlotCount, 12)
    }

    func testImpossibleTinyAreaKeepsAnchorAndOriginalButtonSize() {
        let anchor = CGPoint(x: 10, y: 10)
        let bounds = CGRect(x: 0, y: 0, width: 20, height: 20)
        let placement = RingPlacement(slotCount: 12, anchor: anchor, safeFrame: bounds)
        XCTAssertEqual(placement.visibleSlotCount, 1)
        XCTAssertTrue(placement.hasOverflow)
        XCTAssertEqual(placement.anchor, anchor)
        XCTAssertEqual(placement.frame, bounds)
        XCTAssertEqual(placement.buttonSize, RingButtonMetrics(slotCount: 12).bodySize)
        XCTAssertEqual(placement.labelFrame(0, hoverSafe: false).size, placement.buttonSize)
    }

    func testPartialArcSharesRenderingAndHitBoundaries() {
        let geometry = RingGeometry(slotCount: 4, outerRadius: 200,
                                    arcStartDegrees: -60, arcSweepDegrees: 120, labelRadius: 140)
        for index in 0..<4 {
            let sector = geometry.sectorDegrees(index)
            XCTAssertEqual(sector.start, -60 + Double(index) * 30)
            XCTAssertEqual(sector.end, -30 + Double(index) * 30)
            XCTAssertEqual(geometry.slot(at: offset(angle: sector.start + 0.001, radius: 140)), index)
            XCTAssertEqual(geometry.slot(at: offset(angle: sector.end - 0.001, radius: 140)), index)
            XCTAssertEqual(geometry.slot(at: geometry.slotCenterOffset(index, radius: 10_000)), index)
            XCTAssertNil(geometry.slot(at: geometry.slotCenterOffset(index, radius: 37.99)))
        }
        XCTAssertNil(geometry.slot(at: offset(angle: -60.001, radius: 140)))
        XCTAssertNil(geometry.slot(at: offset(angle: 60.001, radius: 140)))
    }

    func testPartialArcCanCrossZeroWithoutChangingSlotIdentity() {
        let geometry = RingGeometry(slotCount: 3, arcStartDegrees: 330, arcSweepDegrees: 120, labelRadius: 140)
        for index in 0..<3 { XCTAssertEqual(geometry.slot(at: geometry.slotCenterOffset(index)), index) }
        XCTAssertNil(geometry.slot(at: offset(angle: 329.99, radius: 1000)))
        XCTAssertNil(geometry.slot(at: offset(angle: 450.01, radius: 1000)))
    }

    func testEmptyGeometryAndInvalidPointersDoNotSelect() {
        XCTAssertNil(RingGeometry(slotCount: 0).slot(at: CGVector(dx: 100, dy: 100)))
        XCTAssertNil(RingGeometry(slotCount: 3, arcSweepDegrees: 0).slot(at: CGVector(dx: 100, dy: 100)))
        for vector in [CGVector(dx: CGFloat.infinity, dy: 100), CGVector(dx: CGFloat.nan, dy: 100)] {
            XCTAssertNil(ring.slot(at: vector))
            XCTAssertNil(RingPlacement(slotCount: 4, anchor: .zero, safeFrame: screen).slot(at: vector))
        }
    }

    private func offset(angle: Double, radius: CGFloat) -> CGVector {
        let radians = CGFloat(angle) * .pi / 180
        return CGVector(dx: cos(radians) * radius, dy: -sin(radians) * radius)
    }

    /// 检查实际控件包络、完整点击矩形、循环动作编号和有解释的取消区。
    private func assertSafe(_ placement: RingPlacement, file: StaticString = #filePath, line: UInt = #line) {
        let geometry = placement.geometry
        let safe = placement.safeFrame.insetBy(dx: -0.000_001, dy: -0.000_001)
        let frame = placement.frame.insetBy(dx: -0.000_001, dy: -0.000_001)
        XCTAssertEqual(Set(placement.displayOrder), Set(0..<placement.visibleSlotCount), file: file, line: line)
        XCTAssertEqual(placement.displayOrder.count, placement.visibleSlotCount, file: file, line: line)
        XCTAssertNil(placement.slot(at: .zero), file: file, line: line)
        if !geometry.isFullCircle {
            let outside = geometry.startDegrees + geometry.sweepDegrees + (360 - geometry.sweepDegrees) / 2
            XCTAssertNil(geometry.slot(at: offset(angle: outside, radius: 10_000)), file: file, line: line)
        }
        for index in 0..<placement.visibleSlotCount {
            let visual = placement.labelFrame(index)
            let body = placement.labelFrame(index, hoverSafe: false)
            XCTAssertTrue(safe.contains(visual), "阴影包络越过屏幕: \(visual)", file: file, line: line)
            XCTAssertTrue(frame.contains(visual), "阴影包络越过窗口", file: file, line: line)
            for exclusion in placement.excludedFrames {
                XCTAssertTrue(exclusion.intersection(visual).isEmpty, "按钮进入实际不可见区域", file: file, line: line)
            }
            for x in [body.minX, body.maxX] { for y in [body.minY, body.maxY] {
                XCTAssertEqual(placement.slot(at: CGVector(dx: x - placement.anchor.x, dy: y - placement.anchor.y)), index,
                               "按钮角落必须选择自己的动作", file: file, line: line)
            }}
            XCTAssertEqual(placement.slot(at: geometry.slotCenterOffset(index)), index, file: file, line: line)
            XCTAssertEqual(geometry.slot(at: geometry.slotCenterOffset(index, radius: 10_000)), index, file: file, line: line)
            for other in 0..<index {
                let previous = placement.labelFrame(other, hoverSafe: false)
                let xGap = max(body.minX - previous.maxX, previous.minX - body.maxX)
                let yGap = max(body.minY - previous.maxY, previous.minY - body.maxY)
                XCTAssertGreaterThanOrEqual(max(xGap, yGap), RingButtonMetrics.gap - 0.000_001,
                                            "真实按钮矩形之间应保留间隙", file: file, line: line)
            }
        }
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

    func testWindowFrameIgnoresSubpixelLayoutNoiseAtEachBackingScale() {
        let actual = CGRect(x: 368, y: 275, width: 436, height: 270)
        for scale in [CGFloat(1), CGFloat(2)] {
            // 与诊断中的小数高度和整数 panel.frame 相同：上边固定，底边只抖动亚像素。
            let noise = 0.125 / scale
            let measured = CGRect(x: actual.minX, y: actual.minY + noise,
                                  width: actual.width, height: actual.height - noise)
            XCTAssertEqual(ScreenGeometry.pixelAlignedWindowFrame(measured, scale: scale), actual)
        }
    }

    func testWindowFrameKeepsRealSinglePixelChanges() {
        for scale in [CGFloat(1), CGFloat(2)] {
            let original = CGRect(x: -400, y: 100, width: 200, height: 150)
            let expanded = CGRect(x: original.minX, y: original.minY,
                                  width: original.width + 1 / scale, height: original.height)
            XCTAssertNotEqual(ScreenGeometry.pixelAlignedWindowFrame(original, scale: scale),
                              ScreenGeometry.pixelAlignedWindowFrame(expanded, scale: scale))
            XCTAssertEqual(ScreenGeometry.pixelAlignedWindowFrame(expanded, scale: scale), expanded)
        }
    }

    func testWindowFrameAlignmentContainsContentAndIsStableOnNegativeCoordinates() {
        let content = CGRect(x: -1279.75, y: -125.125, width: 435.625, height: 269.375)
        for scale in [CGFloat(1), CGFloat(2)] {
            let aligned = ScreenGeometry.pixelAlignedWindowFrame(content, scale: scale)
            XCTAssertTrue(aligned.contains(content))
            XCTAssertLessThan(content.minX - aligned.minX, 1 / scale)
            XCTAssertLessThan(content.minY - aligned.minY, 1 / scale)
            XCTAssertLessThan(aligned.maxX - content.maxX, 1 / scale)
            XCTAssertLessThan(aligned.maxY - content.maxY, 1 / scale)
            XCTAssertEqual(ScreenGeometry.pixelAlignedWindowFrame(aligned, scale: scale), aligned)
        }
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
