import CoreGraphics
import XCTest
@testable import Pop

/// 只调用生产模型，不创建窗口、系统事件或插件服务。
@MainActor
final class RingPixelLayoutInteractionTests: XCTestCase {
    private func makeRing(content: ClassifiedContent? = .empty) -> RingViewModel {
        let catalog = (0..<8).map {
            PluginInfo(id: "pixel-action-\($0)", name: "测试功能\($0 + 1)", symbol: "star", summary: "", accepts: [])
        }
        return RingViewModel(layout: RingLayout(slots: catalog.map { Optional($0.id) }), catalog: catalog,
                             installed: Set(catalog.map(\.id)), content: content)
    }

    private func rotatedRing(content: ClassifiedContent? = .empty) throws -> RingViewModel {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let ring = makeRing(content: content)
        ring.freezePlacement(anchor: CGPoint(x: screen.minX, y: screen.midY), safeFrame: screen, displayScale: 2)
        let placement = try XCTUnwrap(ring.placement)
        XCTAssertFalse(placement.hasOverflow, "普通屏幕有实际空间时保留全部八个入口")
        XCTAssertNotEqual(placement.displayOrder, Array(0..<8),
                          "固定左边缘场景必须覆盖物理顺序与原始编号不同的交互")
        return ring
    }

    func testCyclicDisplayOrderKeepsKeyboardAndPointerOnTheSameOriginalPlugin() throws {
        let ring = try rotatedRing()
        let placement = try XCTUnwrap(ring.placement)
        let visibleIDs = ring.visibleSlots.map(\.id)
        XCTAssertEqual(visibleIDs, placement.displayOrder)
        XCTAssertEqual(Set(visibleIDs), Set(0..<8))

        // 顺时针、逆时针都完整绕两圈，不把物理序号当作原始槽位编号。
        for delta in [1, -1] {
            ring.resetSelection()
            var visited: [Int] = []
            for _ in 0..<(visibleIDs.count * 2) {
                let next = ring.nextVisibleSlot(by: delta)
                ring.setHovered(next)
                visited.append(next)
                XCTAssertEqual(ring.selectablePlugin(at: next)?.id, "pixel-action-\(next)")
            }
            let cycle = delta > 0 ? visibleIDs : Array(visibleIDs.reversed())
            XCTAssertEqual(visited, cycle + cycle)
        }

        for (position, originalID) in visibleIDs.enumerated() {
            let center = ring.geometry.slotCenterOffset(position)
            ring.updateHover(offset: center)
            XCTAssertEqual(ring.hovered, originalID)
            XCTAssertEqual(ring.selectablePlugin(at: ring.hovered)?.id, "pixel-action-\(originalID)")
            XCTAssertEqual(ring.highlightAngle,
                           RingGeometry.continuousAngle(ring.geometry.slotCenterDegrees(position), near: ring.highlightAngle),
                           accuracy: 0.000_001, "方向提示必须指向实际显示的按钮")
            ring.updateHover(offset: CGVector(dx: center.dx * 3, dy: center.dy * 3))
            XCTAssertEqual(ring.hovered, originalID, "按住远划仍选择渲染在这个方向的原功能")
        }
    }

    func testLoadingCommitAndReturnPreserveTheOriginalSlotAndFrozenPlacement() throws {
        let ring = try rotatedRing(content: nil)
        let placement = try XCTUnwrap(ring.placement)
        let ids = ring.visibleSlots.map(\.id)
        let position = try XCTUnwrap(ids.indices.last)
        let target = ids[position]
        let center = ring.geometry.slotCenterOffset(position)
        ring.updateHover(offset: center)
        let angle = ring.highlightAngle
        XCTAssertEqual(RingReleaseAction.decide(hovered: ring.pluginSlot(ring.hovered), selectable: nil,
                                               isLoading: ring.isLoading, closesOnRelease: true), .runWhenLoaded(target))
        var intent = RingLoadingIntent()
        intent.waitForSlot(target)

        ring.update(content: ContentClassifier.classify(.text("hello")))
        XCTAssertEqual(ring.placement, placement)
        XCTAssertEqual(ring.visibleSlots.map(\.id), ids)
        XCTAssertEqual(ring.hovered, target)
        XCTAssertEqual(ring.highlightAngle, angle)
        XCTAssertEqual(ring.selectablePlugin(at: intent.pendingSlot)?.id, "pixel-action-\(target)")

        // 点击确认后冻结原编号，不因后续指针进入另一个物理位置而换目标。
        ring.commit(target)
        ring.updateHover(offset: ring.geometry.slotCenterOffset(0))
        XCTAssertEqual(ring.committed, target)
        XCTAssertEqual(ring.hovered, target)
        ring.resetSelection()
        intent.navigateMenu()
        XCTAssertNil(intent.pendingSlot)
        XCTAssertTrue(intent.preservesMenu)
        XCTAssertNil(ring.hovered)
        XCTAssertNil(ring.committed)
        ring.freezePlacement(anchor: CGPoint(x: 900, y: 300),
                             safeFrame: CGRect(x: -1920, y: -1000, width: 3840, height: 2160),
                             excludedFrames: [CGRect(x: 0, y: 0, width: 100, height: 100)], displayScale: 1)
        XCTAssertEqual(ring.placement, placement, "返回圆盘复用第一次唤起的位置、屏幕与禁区")
        XCTAssertEqual(ring.visibleSlots.map(\.id), ids)
        ring.updateHover(offset: .zero)
        XCTAssertEqual(RingReleaseAction.decide(hovered: ring.hovered, selectable: nil,
                                               isLoading: false, closesOnRelease: true), .close)
    }

    func testOriginalNumberedSlotsRemainAddressableAfterPhysicalRotation() throws {
        let ring = try rotatedRing()
        let placement = ring.placement
        XCTAssertNotEqual(ring.visibleSlots.map(\.id), Array(0..<8))
        for originalID in 0..<8 {
            ring.resetSelection()
            XCTAssertEqual(ring.pluginSlot(originalID), originalID)
            XCTAssertEqual(ring.selectablePlugin(at: originalID)?.id, "pixel-action-\(originalID)",
                           "数字键查询的是原编号，不是重排后的可见数组下标")
            ring.commit(originalID)
            XCTAssertEqual(ring.committed, originalID)
            XCTAssertEqual(ring.hovered, originalID)
            let physicalPosition = try XCTUnwrap(ring.visibleSlots.firstIndex { $0.id == originalID })
            XCTAssertEqual(ring.highlightAngle,
                           RingGeometry.continuousAngle(ring.geometry.slotCenterDegrees(physicalPosition), near: ring.highlightAngle),
                           accuracy: 0.000_001, "原编号的确认反馈也必须落在重排后的位置")
            XCTAssertEqual(ring.placement, placement)
        }
    }

    func testExcludedZoneCannotActivateTheButtonItPreviouslyCovered() throws {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let anchor = CGPoint(x: screen.midX, y: screen.midY)
        let baseline = RingPlacement(slotCount: 8, anchor: anchor, safeFrame: screen, displayScale: 2)
        let originalOffset = baseline.geometry.slotCenterOffset(0)
        let coveredCenter = CGPoint(x: anchor.x + originalOffset.dx, y: anchor.y + originalOffset.dy)
        let exclusion = CGRect(x: coveredCenter.x - baseline.buttonSize.width / 2 - 4,
                               y: coveredCenter.y - baseline.buttonSize.height / 2 - 4,
                               width: baseline.buttonSize.width + 8, height: baseline.buttonSize.height + 8)
        let ring = makeRing()
        ring.freezePlacement(anchor: anchor, safeFrame: screen, excludedFrames: [exclusion], displayScale: 2)
        let placement = try XCTUnwrap(ring.placement)
        XCTAssertFalse(placement.hasOverflow)
        for position in ring.visibleSlots.indices {
            let offset = ring.geometry.slotCenterOffset(position)
            XCTAssertFalse(exclusion.contains(CGPoint(x: anchor.x + offset.dx, y: anchor.y + offset.dy)))
            ring.updateHover(offset: offset)
            XCTAssertEqual(ring.hovered, ring.visibleSlots[position].id)
        }
        for x in [exclusion.minX + 1, exclusion.midX, exclusion.maxX - 1] {
            for y in [exclusion.minY + 1, exclusion.midY, exclusion.maxY - 1] {
                ring.updateHover(offset: CGVector(dx: x - anchor.x, dy: y - anchor.y))
                XCTAssertNil(ring.hovered, "被遮挡区域的指针不能暗中触发某个功能")
            }
        }
    }

    func testFarDragThroughExcludedZoneClearsHoverEvenWhenItsDirectionIsSelectable() throws {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let anchor = CGPoint(x: screen.midX, y: screen.midY)
        let exclusion = CGRect(x: 690, y: 820, width: 60, height: 80)
        let ring = makeRing()
        ring.freezePlacement(anchor: anchor, safeFrame: screen, excludedFrames: [exclusion], displayScale: 2)
        let blockedOffset = CGVector(dx: exclusion.midX - anchor.x, dy: exclusion.midY - anchor.y)
        let position = try XCTUnwrap(ring.geometry.slot(at: blockedOffset), "此场景必须区分方向命中和实际禁区过滤")
        let visibleOffset = ring.geometry.slotCenterOffset(position)
        let target = ring.visibleSlots[position].id
        ring.updateHover(offset: visibleOffset)
        XCTAssertEqual(ring.hovered, target)
        ring.updateHover(offset: blockedOffset)
        XCTAssertNil(ring.hovered)
        XCTAssertEqual(RingReleaseAction.decide(hovered: ring.hovered, selectable: nil,
                                               isLoading: false, closesOnRelease: true), .close)
        ring.updateHover(offset: visibleOffset)
        XCTAssertEqual(ring.hovered, target, "离开禁区后仍能重新选择原功能")
    }
}
