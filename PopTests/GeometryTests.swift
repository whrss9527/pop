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

    func testFullPlacementPreservesExistingCenterLayout() {
        let safeFrame = CGRect(x: 0, y: 80, width: 1440, height: 794)
        let anchor = CGPoint(x: 720, y: 450)
        for count in [1, 2, 3, 4, 6, 8, 10, 12] {
            let expected = RingGeometry(slotCount: count, outerRadius: RingGeometry.outerRadius(forSlotCount: count))
            let placement = RingPlacement(slotCount: count, anchor: anchor, safeFrame: safeFrame)
            XCTAssertEqual(placement.geometry, expected)
            XCTAssertTrue(placement.geometry.isFullCircle)
            XCTAssertFalse(placement.hasOverflow)
            XCTAssertEqual(placement.visibleSlotCount, count)
            XCTAssertEqual(placement.anchor, anchor)
            XCTAssertEqual(placement.safeFrame, safeFrame)
            XCTAssertEqual(placement.frame, CGRect(x: anchor.x - expected.outerRadius - 22,
                                                  y: anchor.y - expected.outerRadius - 22,
                                                  width: expected.diameter + 44, height: expected.diameter + 44))
        }
    }

    func testFullPlacementRequiresItsExistingPaddingToFit() {
        let safeFrame = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let touching = RingPlacement(slotCount: 8, anchor: CGPoint(x: 146, y: 400), safeFrame: safeFrame)
        XCTAssertTrue(touching.geometry.isFullCircle)
        let clippedPadding = RingPlacement(slotCount: 8, anchor: CGPoint(x: 145.5, y: 400), safeFrame: safeFrame)
        XCTAssertFalse(clippedPadding.geometry.isFullCircle)
        XCTAssertEqual(clippedPadding.anchor, CGPoint(x: 145.5, y: 400))
        assertSafeAdaptivePlacement(clippedPadding)
    }

    func testAllEdgesAndCornersKeepLabelsAndHighlightsInsideSafeFrame() {
        let safeFrame = CGRect(x: 0, y: 80, width: 1440, height: 794)
        let anchors = edgeAnchors(in: safeFrame)
        for count in [4, 6, 8, 10, 12] {
            for anchor in anchors {
                let placement = RingPlacement(slotCount: count, anchor: anchor, safeFrame: safeFrame)
                XCTAssertEqual(placement.anchor, anchor)
                XCTAssertEqual(placement.safeFrame, safeFrame)
                XCTAssertEqual(placement.visibleSlotCount, placement.geometry.slotCount)
                XCTAssertLessThanOrEqual(placement.visibleSlotCount, count)
                XCTAssertEqual(placement.hasOverflow, placement.visibleSlotCount < count)
                XCTAssertEqual(placement, RingPlacement(slotCount: count, anchor: anchor, safeFrame: safeFrame))
                assertSafeAdaptivePlacement(placement)
            }
        }
    }

    func testCornerMovesFourthSlotIntoMoreInsteadOfExpandingRadius() {
        let safeFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)
        for anchor in Array(edgeAnchors(in: safeFrame).suffix(4)) {
            let placement = RingPlacement(slotCount: 4, anchor: anchor, safeFrame: safeFrame)
            XCTAssertEqual(placement.visibleSlotCount, 3)
            XCTAssertTrue(placement.hasOverflow)
            assertSafeAdaptivePlacement(placement)
        }
    }

    func testExactCornersKeepEverySelectableDirectionInsideSafeFrame() {
        let safeFrame = CGRect(x: 0, y: 80, width: 1440, height: 794)
        let corners: [(anchor: CGPoint, start: Double)] = [
            (CGPoint(x: safeFrame.minX, y: safeFrame.maxY), 0),
            (CGPoint(x: safeFrame.maxX, y: safeFrame.maxY), 90),
            (CGPoint(x: safeFrame.maxX, y: safeFrame.minY), 180),
            (CGPoint(x: safeFrame.minX, y: safeFrame.minY), 270),
        ]
        for count in [4, 6, 8, 10, 12] {
            for corner in corners {
                let placement = RingPlacement(slotCount: count, anchor: corner.anchor, safeFrame: safeFrame)
                XCTAssertEqual(placement.anchor, corner.anchor)
                XCTAssertEqual(placement.visibleSlotCount, 3)
                XCTAssertTrue(placement.hasOverflow)
                XCTAssertNil(placement.geometry.slot(at: offset(angle: corner.start - 1, radius: 10_000)))
                XCTAssertNil(placement.geometry.slot(at: offset(angle: corner.start + 91, radius: 10_000)))
                assertSafeAdaptivePlacement(placement)
            }
        }
    }

    func testHeldDragTowardMenuBarAtExactTopLeftDoesNotSelect() {
        let safeFrame = CGRect(x: 0, y: 80, width: 1440, height: 794)
        let placement = RingPlacement(slotCount: 4, anchor: CGPoint(x: safeFrame.minX, y: safeFrame.maxY),
                                      safeFrame: safeFrame)
        // -1° 朝向菜单栏，即使只比可见扇形向外偏一点，也不能选中第一格。
        XCTAssertNil(placement.geometry.slot(at: offset(angle: -1, radius: placement.geometry.labelRadius)))
        XCTAssertNil(placement.geometry.slot(at: offset(angle: -1, radius: 10_000)))
        XCTAssertEqual(placement.geometry.slot(at: placement.geometry.slotCenterOffset(0, radius: 10_000)), 0)
        assertSafeAdaptivePlacement(placement)
    }

    func testCornerOverflowDoesNotShrinkTargetsOrExceedRadiusLimit() {
        let placement = RingPlacement(slotCount: 12, anchor: CGPoint(x: 2, y: 2),
                                      safeFrame: CGRect(x: 0, y: 0, width: 1440, height: 900))
        XCTAssertTrue(placement.hasOverflow)
        XCTAssertGreaterThanOrEqual(placement.visibleSlotCount, 2)
        XCTAssertLessThan(placement.visibleSlotCount, 12)
        XCTAssertEqual(placement.labelFrame(0, hoverSafe: false).size, CGSize(width: 66, height: 40))
        XCTAssertEqual(placement.labelFrame(0).size, CGSize(width: 80, height: 52))
        assertSafeAdaptivePlacement(placement)
    }

    func testEdgeRadiusGrowsWithSlotCountThenStopsAtMore() {
        let safeFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)
        for anchor in Array(edgeAnchors(in: safeFrame).prefix(4)) {
            var previousRadius: CGFloat = 0
            var capped: RingGeometry?
            for count in 1...12 {
                let placement = RingPlacement(slotCount: count, anchor: anchor, safeFrame: safeFrame)
                XCTAssertLessThanOrEqual(placement.geometry.outerRadius, 240)
                XCTAssertGreaterThanOrEqual(placement.geometry.outerRadius, previousRadius)
                XCTAssertEqual(placement.visibleSlotCount, min(count, 6))
                XCTAssertEqual(placement.hasOverflow, count > 6)
                if count <= 2 { XCTAssertLessThanOrEqual(placement.geometry.outerRadius, 150) }
                if count >= 3 && count <= 6 {
                    XCTAssertGreaterThan(placement.geometry.outerRadius, previousRadius)
                }
                if count == 6 { capped = placement.geometry }
                if count > 6 { XCTAssertEqual(placement.geometry, capped) }
                previousRadius = placement.geometry.outerRadius
                assertSafeAdaptivePlacement(placement)
            }
        }
    }

    func testNarrowScreenFallbackKeepsSingleEntryCompactAndVisible() {
        for safeFrame in [CGRect(x: 0, y: 0, width: 80, height: 900),
                          CGRect(x: -1000, y: 40, width: 1440, height: 52)] {
            let anchor = CGPoint(x: safeFrame.minX, y: safeFrame.midY)
            let placement = RingPlacement(slotCount: 12, anchor: anchor, safeFrame: safeFrame)
            XCTAssertEqual(placement.visibleSlotCount, 1)
            XCTAssertTrue(placement.hasOverflow)
            XCTAssertLessThanOrEqual(placement.geometry.outerRadius, 240)
            // 极窄区域的标签恰好贴边，极坐标往返会产生浮点尾差。
            XCTAssertTrue(safeFrame.insetBy(dx: -0.000_001, dy: -0.000_001).contains(placement.labelFrame(0)))
            XCTAssertTrue(placement.frame.insetBy(dx: -0.000_001, dy: -0.000_001).contains(placement.labelFrame(0)))
            XCTAssertGreaterThan(placement.geometry.labelRadius, placement.geometry.innerRadius)
        }
    }

    func testOneTwoAndThreeSlotsAlsoUseSafeClockwiseArcs() {
        let safeFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)
        for count in 1...3 {
            for anchor in edgeAnchors(in: safeFrame) {
                let placement = RingPlacement(slotCount: count, anchor: anchor, safeFrame: safeFrame)
                XCTAssertEqual(placement.visibleSlotCount, count)
                XCTAssertFalse(placement.hasOverflow)
                assertSafeAdaptivePlacement(placement)
            }
        }
    }

    func testAnchorMayBeInDockOrMenuBarOutsideSafeFrame() {
        let safeFrame = CGRect(x: 0, y: 96, width: 1440, height: 776)
        let anchors = [CGPoint(x: 1, y: 1), CGPoint(x: 1439, y: 1),
                       CGPoint(x: 1, y: 899), CGPoint(x: 1439, y: 899),
                       CGPoint(x: 720, y: 1), CGPoint(x: 720, y: 899)]
        for count in [4, 6, 8, 10, 12] {
            for anchor in anchors {
                let placement = RingPlacement(slotCount: count, anchor: anchor, safeFrame: safeFrame)
                XCTAssertEqual(placement.anchor, anchor)
                XCTAssertFalse(safeFrame.contains(anchor))
                XCTAssertNotEqual(CGPoint(x: placement.frame.midX, y: placement.frame.midY), anchor)
                assertSafeAdaptivePlacement(placement)
            }
        }
    }

    func testTranslatedAndFractionalMonitorCoordinatesPreserveGeometry() {
        let safeFrame = CGRect(x: 0, y: 80, width: 1440, height: 794)
        let shifts = [CGVector(dx: -2560, dy: 400), CGVector(dx: 1440, dy: -900),
                      CGVector(dx: -1728.5, dy: -1117.25)]
        for count in [4, 6, 8, 10, 12] {
            for anchor in edgeAnchors(in: safeFrame) {
                let original = RingPlacement(slotCount: count, anchor: anchor, safeFrame: safeFrame)
                for shift in shifts {
                    let translated = RingPlacement(slotCount: count,
                                                   anchor: CGPoint(x: anchor.x + shift.dx, y: anchor.y + shift.dy),
                                                   safeFrame: safeFrame.offsetBy(dx: shift.dx, dy: shift.dy))
                    XCTAssertEqual(translated.geometry, original.geometry)
                    XCTAssertEqual(translated.visibleSlotCount, original.visibleSlotCount)
                    XCTAssertEqual(translated.hasOverflow, original.hasOverflow)
                    XCTAssertEqual(translated.frame.minX, original.frame.minX + shift.dx, accuracy: 0.000_001)
                    XCTAssertEqual(translated.frame.minY, original.frame.minY + shift.dy, accuracy: 0.000_001)
                    XCTAssertEqual(translated.frame.width, original.frame.width, accuracy: 0.000_001)
                    XCTAssertEqual(translated.frame.height, original.frame.height, accuracy: 0.000_001)
                    assertSafeAdaptivePlacement(translated)
                }
            }
        }
    }

    func testCompactAreaKeepsOneFullSizeOverflowEntry() {
        let placement = RingPlacement(slotCount: 12, anchor: CGPoint(x: 2, y: 2),
                                      safeFrame: CGRect(x: 0, y: 0, width: 160, height: 120))
        XCTAssertEqual(placement.visibleSlotCount, 1)
        XCTAssertTrue(placement.hasOverflow)
        assertSafeAdaptivePlacement(placement)
    }

    func testImpossibleTinyAreaDoesNotMoveAnchorOrShrinkLabel() {
        let anchor = CGPoint(x: 10, y: 10)
        let safeFrame = CGRect(x: 0, y: 0, width: 20, height: 20)
        let placement = RingPlacement(slotCount: 12, anchor: anchor, safeFrame: safeFrame)
        XCTAssertEqual(placement.visibleSlotCount, 1)
        XCTAssertTrue(placement.hasOverflow)
        XCTAssertEqual(placement.anchor, anchor)
        XCTAssertEqual(placement.frame, safeFrame)
        XCTAssertEqual(placement.labelFrame(0).size, CGSize(width: 80, height: 52))
        XCTAssertEqual(placement, RingPlacement(slotCount: 12, anchor: anchor, safeFrame: safeFrame))
    }

    func testPartialArcSharesRenderingAndHitBoundaries() {
        let geometry = RingGeometry(slotCount: 4, outerRadius: 200,
                                    arcStartDegrees: -60, arcSweepDegrees: 120, labelRadius: 140)
        XCTAssertFalse(geometry.isFullCircle)
        XCTAssertEqual(geometry.slotStep, .pi / 6, accuracy: 0.000_001)
        XCTAssertEqual(geometry.highlightArcSpanDegrees, 18.6, accuracy: 0.000_001)
        for index in 0..<4 {
            let sector = geometry.sectorDegrees(index)
            XCTAssertEqual(sector.start, -60 + Double(index) * 30)
            XCTAssertEqual(sector.end, -30 + Double(index) * 30)
            XCTAssertEqual(geometry.slotCenterDegrees(index), (sector.start + sector.end) / 2)
            XCTAssertEqual(geometry.slot(at: offset(angle: sector.start + 0.001, radius: 140)), index)
            XCTAssertEqual(geometry.slot(at: offset(angle: sector.end - 0.001, radius: 140)), index)
            XCTAssertEqual(geometry.slot(at: geometry.slotCenterOffset(index)), index)
            XCTAssertEqual(geometry.slot(at: geometry.slotCenterOffset(index, radius: 10_000)), index)
            XCTAssertNil(geometry.slot(at: geometry.slotCenterOffset(index, radius: 37.99)))
            XCTAssertEqual(geometry.slot(at: geometry.slotCenterOffset(index, radius: 38.01)), index)
        }
        XCTAssertNil(geometry.slot(at: offset(angle: -60.001, radius: 140)))
        XCTAssertNil(geometry.slot(at: offset(angle: 60.001, radius: 140)))
        XCTAssertNil(geometry.slot(at: CGVector(dx: -1000, dy: 0)))
        XCTAssertNil(geometry.slot(at: CGVector(dx: 0, dy: 1000)))
        XCTAssertNil(geometry.slot(at: CGVector(dx: 0, dy: -1000)))
        XCTAssertNil(geometry.slot(at: .zero))
    }

    func testPartialArcCanCrossZeroDegreesWithoutWrappingToFirstSlot() {
        let geometry = RingGeometry(slotCount: 3, arcStartDegrees: 330, arcSweepDegrees: 120, labelRadius: 140)
        for index in 0..<3 {
            XCTAssertEqual(geometry.slotCenterDegrees(index), 350 + Double(index) * 40)
            XCTAssertEqual(geometry.slot(at: geometry.slotCenterOffset(index)), index)
        }
        XCTAssertNil(geometry.slot(at: offset(angle: 329.99, radius: 1000)))
        XCTAssertNil(geometry.slot(at: offset(angle: 450.01, radius: 1000)))
    }

    func testEdgeStatusFitsInsideOpeningWithoutCoveringCancelZoneOrSlots() {
        let safeFrame = CGRect(x: 0, y: 80, width: 1440, height: 794)
        var statusCount = 0
        for count in [4, 6, 8, 10, 12] {
            for anchor in edgeAnchors(in: safeFrame) {
                let placement = RingPlacement(slotCount: count, anchor: anchor, safeFrame: safeFrame)
                guard let status = placement.statusFrame else { continue }
                statusCount += 1
                XCTAssertTrue(safeFrame.contains(status))
                XCTAssertTrue(placement.frame.contains(status))
                let cancelZone = CGRect(x: anchor.x - 38, y: anchor.y - 38, width: 76, height: 76)
                XCTAssertFalse(status.intersects(cancelZone))
                for index in 0..<placement.visibleSlotCount {
                    XCTAssertFalse(status.intersects(placement.labelFrame(index)))
                }
                for x in [status.minX, status.maxX] {
                    for y in [status.minY, status.maxY] {
                        XCTAssertLessThan(hypot(x - anchor.x, y - anchor.y),
                                          placement.geometry.labelRadius - placement.geometry.bandHalfWidth)
                    }
                }
            }
        }
        XCTAssertGreaterThan(statusCount, 0, "常见边缘布局应有可读的提示，不能全部省略")
    }

    func testRoundedBandKeepsItsEndsAndInnerAndOuterEdgesOnScreen() {
        let safeFrame = CGRect(x: 0, y: 80, width: 1440, height: 794)
        for count in [1, 2, 3, 4, 6, 8, 10, 12] {
            for anchor in edgeAnchors(in: safeFrame) {
                let placement = RingPlacement(slotCount: count, anchor: anchor, safeFrame: safeFrame)
                let geometry = placement.geometry
                for sample in 0...100 {
                    let angle = geometry.bandStartDegrees + (geometry.bandEndDegrees - geometry.bandStartDegrees) * Double(sample) / 100
                    for radius in [geometry.labelRadius - geometry.bandHalfWidth, geometry.labelRadius + geometry.bandHalfWidth] {
                        let vector = offset(angle: angle, radius: radius)
                        let point = CGPoint(x: anchor.x + vector.dx, y: anchor.y + vector.dy)
                        XCTAssertTrue(safeFrame.contains(point), "弧带越过屏幕边界")
                        XCTAssertTrue(placement.frame.contains(point), "弧带越过窗口边界")
                    }
                }
                for index in [0, placement.visibleSlotCount - 1] {
                    let center = geometry.slotCenterOffset(index)
                    let cap = CGRect(x: anchor.x + center.dx - geometry.bandHalfWidth,
                                     y: anchor.y + center.dy - geometry.bandHalfWidth,
                                     width: geometry.bandHalfWidth * 2, height: geometry.bandHalfWidth * 2)
                    XCTAssertTrue(safeFrame.contains(cap), "圆头不能被屏幕裁切")
                    XCTAssertTrue(placement.frame.contains(cap))
                }
            }
        }
    }

    func testStatusIsOmittedWhenOpeningIsTooSmallOrMenuIsFullCircle() {
        let safeFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)
        XCTAssertNil(RingPlacement(slotCount: 8, anchor: CGPoint(x: 720, y: 450), safeFrame: safeFrame).statusFrame)
        XCTAssertNil(RingPlacement(slotCount: 1, anchor: CGPoint(x: 2, y: 450), safeFrame: safeFrame).statusFrame)
        XCTAssertNil(RingPlacement(slotCount: 12, anchor: CGPoint(x: 2, y: 2),
                                   safeFrame: CGRect(x: 0, y: 0, width: 160, height: 120)).statusFrame)
    }

    func testEmptyGeometryAndInvalidPointerDoNotSelect() {
        XCTAssertNil(RingGeometry(slotCount: 0).slot(at: CGVector(dx: 100, dy: 100)))
        XCTAssertNil(RingGeometry(slotCount: 3, arcSweepDegrees: 0).slot(at: CGVector(dx: 100, dy: 100)))
        XCTAssertNil(ring.slot(at: CGVector(dx: CGFloat.infinity, dy: 100)))
        XCTAssertNil(ring.slot(at: CGVector(dx: CGFloat.nan, dy: 100)))
    }

    private func edgeAnchors(in frame: CGRect) -> [CGPoint] {
        [CGPoint(x: frame.minX + 2, y: frame.midY), CGPoint(x: frame.maxX - 2, y: frame.midY),
         CGPoint(x: frame.midX, y: frame.minY + 2), CGPoint(x: frame.midX, y: frame.maxY - 2),
         CGPoint(x: frame.minX + 2, y: frame.minY + 2), CGPoint(x: frame.maxX - 2, y: frame.minY + 2),
         CGPoint(x: frame.maxX - 2, y: frame.maxY - 2), CGPoint(x: frame.minX + 2, y: frame.maxY - 2)]
    }

    private func offset(angle: Double, radius: CGFloat) -> CGVector {
        let radians = CGFloat(angle) * .pi / 180
        return CGVector(dx: cos(radians) * radius, dy: -sin(radians) * radius)
    }

    /// 一次性核对屏幕边界、标签自己的命中扇区、间距和高亮轮廓。
    private func assertSafeAdaptivePlacement(_ placement: RingPlacement, file: StaticString = #filePath, line: UInt = #line) {
        let geometry = placement.geometry
        let tolerance: CGFloat = 0.000_001
        let safe = placement.safeFrame.insetBy(dx: -tolerance, dy: -tolerance)
        let frame = placement.frame.insetBy(dx: -tolerance, dy: -tolerance)
        XCTAssertFalse(geometry.isFullCircle, file: file, line: line)
        XCTAssertEqual(geometry.innerRadius, 38, file: file, line: line)
        XCTAssertLessThanOrEqual(geometry.labelRadius, RingPlacement.maximumLabelRadius, file: file, line: line)
        XCTAssertGreaterThanOrEqual(geometry.highlightRadius * 2, 44, file: file, line: line)
        XCTAssertTrue(safe.contains(placement.frame), file: file, line: line)
        XCTAssertNil(geometry.slot(at: .zero), file: file, line: line)
        let opposite = geometry.startDegrees + geometry.sweepDegrees / 2 + 180
        XCTAssertNil(geometry.slot(at: offset(angle: opposite, radius: 10_000)), file: file, line: line)
        for index in 0..<placement.visibleSlotCount {
            let sector = geometry.sectorDegrees(index)
            for sample in 0...40 {
                let angle = sector.start + (sector.end - sector.start) * Double(sample) / 40
                let vector = offset(angle: angle, radius: geometry.labelRadius)
                let point = CGPoint(x: placement.anchor.x + vector.dx, y: placement.anchor.y + vector.dy)
                XCTAssertTrue(safe.contains(point), "可选方向不能越过可见扇形的屏幕边界", file: file, line: line)
                XCTAssertTrue(frame.contains(point), "可选方向不能越过可见扇形的窗口边界", file: file, line: line)
                if sample > 0 && sample < 40 {
                    XCTAssertEqual(geometry.slot(at: vector), index, file: file, line: line)
                    XCTAssertEqual(geometry.slot(at: offset(angle: angle, radius: 10_000)), index, file: file, line: line)
                }
            }
            let label = placement.labelFrame(index)
            XCTAssertTrue(safe.contains(label), "标签越过屏幕：\(label)", file: file, line: line)
            XCTAssertTrue(frame.contains(label), "标签越过窗口：\(label)", file: file, line: line)
            for x in [label.minX, label.maxX] {
                for y in [label.minY, label.maxY] {
                    let vector = CGVector(dx: x - placement.anchor.x, dy: y - placement.anchor.y)
                    XCTAssertEqual(geometry.slot(at: vector), index, "标签角落必须仍属于自己的格子", file: file, line: line)
                    XCTAssertLessThanOrEqual(hypot(vector.dx, vector.dy), geometry.outerRadius, file: file, line: line)
                }
            }
            let center = geometry.slotCenterOffset(index)
            XCTAssertEqual(geometry.slot(at: center), index, file: file, line: line)
            XCTAssertEqual(geometry.slot(at: geometry.slotCenterOffset(index, radius: 10_000)), index, file: file, line: line)
            let highlight = CGRect(x: placement.anchor.x + center.dx - geometry.highlightRadius - 1,
                                   y: placement.anchor.y + center.dy - geometry.highlightRadius - 1,
                                   width: (geometry.highlightRadius + 1) * 2, height: (geometry.highlightRadius + 1) * 2)
            XCTAssertTrue(safe.contains(highlight), file: file, line: line)
            for sample in 0...20 {
                let angle = geometry.slotCenterDegrees(index) - geometry.highlightArcSpanDegrees / 2
                    + geometry.highlightArcSpanDegrees * Double(sample) / 20
                let rim = offset(angle: angle, radius: geometry.outerRadius - 5)
                let glow = CGRect(x: placement.anchor.x + rim.dx - 7, y: placement.anchor.y + rim.dy - 7,
                                  width: 14, height: 14)
                XCTAssertTrue(safe.contains(glow), "外圈高亮越过屏幕", file: file, line: line)
                XCTAssertTrue(frame.contains(glow), "外圈高亮越过窗口", file: file, line: line)
            }
            if index > 0 {
                let previous = geometry.slotCenterOffset(index - 1)
                XCTAssertGreaterThanOrEqual(hypot(center.dx - previous.dx, center.dy - previous.dy),
                                            72 - tolerance, file: file, line: line)
                XCTAssertGreaterThan(geometry.slotCenterDegrees(index), geometry.slotCenterDegrees(index - 1),
                                     file: file, line: line)
            }
            for other in 0..<index {
                XCTAssertFalse(label.intersects(placement.labelFrame(other)), "悬停标签不能重叠", file: file, line: line)
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
