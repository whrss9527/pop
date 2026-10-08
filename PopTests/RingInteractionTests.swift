import AppKit
import SwiftUI
import XCTest
@testable import Pop

final class RingInteractionTests: XCTestCase {
    private func decide(hovered: Int?, selectable: String? = nil, loading: Bool = false, closes: Bool) -> RingReleaseAction {
        RingReleaseAction.decide(hovered: hovered, selectable: selectable, isLoading: loading, closesOnRelease: closes)
    }

    func testReleaseOnSelectableSlotRuns() {
        XCTAssertEqual(decide(hovered: 2, selectable: BuiltinPluginID.translate, closes: true), .run(BuiltinPluginID.translate))
        XCTAssertEqual(decide(hovered: 2, selectable: BuiltinPluginID.translate, closes: false), .run(BuiltinPluginID.translate))
    }

    /// 在圆心、或者不能处理当前内容的格子上松开：默认关闭圆盘，打开「保持圆盘打开」时改用点击选择
    func testReleaseElsewhereClosesUnlessKeptOpen() {
        XCTAssertEqual(decide(hovered: nil, closes: true), .close)
        XCTAssertEqual(decide(hovered: 3, closes: true), .close)
        XCTAssertEqual(decide(hovered: nil, closes: false), .keepOpen)
        XCTAssertEqual(decide(hovered: 3, closes: false), .keepOpen)
    }

    /// 内容还在读取时就划到了某一格：读到后执行那一格，而不是把这一划丢掉
    func testReleaseWhileLoading() {
        XCTAssertEqual(decide(hovered: 5, loading: true, closes: true), .runWhenLoaded(5))
        XCTAssertEqual(decide(hovered: 5, loading: true, closes: false), .runWhenLoaded(5))
        XCTAssertEqual(decide(hovered: nil, loading: true, closes: true), .close)
        XCTAssertEqual(decide(hovered: nil, loading: true, closes: false), .keepOpen)
    }

    @MainActor
    func testPluginSlotsAndSelection() {
        let catalog = BuiltinPlugins.make().map(\.info)
        let layout = RingLayout(slots: [BuiltinPluginID.translate, nil, BuiltinPluginID.search, BuiltinPluginID.copyPath])
        let ring = RingViewModel(layout: layout, catalog: catalog,
                                 installed: [BuiltinPluginID.translate, BuiltinPluginID.search], content: nil)
        XCTAssertEqual(ring.pluginSlot(0), 0)
        XCTAssertNil(ring.pluginSlot(1), "空格子")
        XCTAssertEqual(ring.pluginSlot(2), 2)
        XCTAssertNil(ring.pluginSlot(3), "没安装的功能")
        XCTAssertNil(ring.pluginSlot(nil))
        XCTAssertNil(ring.pluginSlot(9))

        // 读取中什么都不能直接执行
        XCTAssertTrue(ring.isLoading)
        XCTAssertNil(ring.selectablePlugin(at: 0))
        ring.update(content: ContentClassifier.classify(.text("Good morning")))
        XCTAssertEqual(ring.selectablePlugin(at: 0)?.id, BuiltinPluginID.translate)
        XCTAssertNil(ring.selectablePlugin(at: 1))
    }

    /// 高亮在格子之间滑动时走近路：从最后一格到第一格是往前 45°，不是倒回去转一圈
    func testHighlightTakesTheShortWayRound() {
        let ring = RingGeometry(slotCount: 8)
        XCTAssertEqual(ring.slotCenterDegrees(0), -90)
        XCTAssertEqual(ring.slotCenterDegrees(2), 0)
        XCTAssertEqual(ring.slotCenterDegrees(7), 225)
        XCTAssertEqual(RingGeometry.continuousAngle(-90, near: 225), 270)
        XCTAssertEqual(RingGeometry.continuousAngle(225, near: -90), -135)
        XCTAssertEqual(RingGeometry.continuousAngle(0, near: 10), 0)
        XCTAssertGreaterThan(ring.highlightRadius, 12)
        XCTAssertLessThan(ring.highlightRadius, 2 * ring.labelRadius * sin(ring.slotStep / 2) / 2)
    }

    @MainActor
    func testHoverSlidesAndCommitFreezesTheRing() {
        let catalog = BuiltinPlugins.make().map(\.info)
        let layout = RingLayout.default
        let ring = RingViewModel(layout: layout, catalog: catalog, installed: Set(layout.slots.compactMap { $0 }),
                                 content: ContentClassifier.classify(.text("Good morning")))
        ring.setHovered(7)
        XCTAssertEqual(ring.highlightAngle, -135)
        let firstHighlight = ring.highlightID
        ring.setHovered(0)
        XCTAssertEqual(ring.highlightAngle, -90, "从最后一格滑到第一格走近路")
        XCTAssertEqual(ring.highlightID, firstHighlight, "格子之间滑动时还是同一块高亮")
        ring.setHovered(nil)
        ring.setHovered(4)
        XCTAssertEqual(ring.highlightID, firstHighlight + 1, "从圆心重新指向时换一块新的高亮，不从旧位置滑过来")
        ring.commit(4)
        XCTAssertEqual(ring.committed, 4)
        ring.setHovered(5)
        XCTAssertEqual(ring.hovered, 4, "选中后高亮不再跟着指针变")
    }

    /// 指着哪一格，圆心就显示哪个功能；用不了时说明缺什么，指着空格子时说是空的，没指着时显示读到的内容
    @MainActor
    func testCenterShowsTheHoveredFunction() {
        let catalog = BuiltinPlugins.make().map(\.info)
        let layout = RingLayout(slots: [BuiltinPluginID.translate, nil, BuiltinPluginID.clipboardHistory, BuiltinPluginID.copyPath])
        let installed: Set<String> = [BuiltinPluginID.translate, BuiltinPluginID.clipboardHistory, BuiltinPluginID.copyPath]
        let ring = RingViewModel(layout: layout, catalog: catalog, installed: installed, content: ContentClassifier.classify(.none))
        XCTAssertEqual(ring.center, RingViewModel.Center(title: "未选中内容"))
        ring.setHovered(2)
        XCTAssertEqual(ring.center, RingViewModel.Center(title: "剪贴板", isFunction: true, enabled: true))
        ring.setHovered(0)
        XCTAssertEqual(ring.center, RingViewModel.Center(title: "翻译", detail: "要先选中文字", isFunction: true, enabled: false))
        ring.setHovered(3)
        XCTAssertEqual(ring.center.detail, "要先选中文件")
        ring.setHovered(1)
        XCTAssertEqual(ring.center.title, "空格子")
        XCTAssertFalse(ring.center.enabled)
        ring.setHovered(nil)
        XCTAssertEqual(ring.center, RingViewModel.Center(title: "未选中内容"))

        // 选中了文字：翻译可以用，复制路径还是要选中文件
        ring.update(content: ContentClassifier.classify(.text("Good morning")))
        ring.setHovered(0)
        XCTAssertEqual(ring.center, RingViewModel.Center(title: "翻译", isFunction: true, enabled: true))
        ring.setHovered(3)
        XCTAssertEqual(ring.center, RingViewModel.Center(title: "复制路径", detail: "要先选中文件", isFunction: true, enabled: false))
    }

    /// 卡片从离指针最近的那个角长出来（AppKit 坐标，y 向上）
    @MainActor
    func testCardGrowsFromTheCornerNearestThePointer() {
        let anchor = CGPoint(x: 500, y: 500)
        XCTAssertEqual(OverlayController.growAnchor(frame: CGRect(x: 506, y: 300, width: 400, height: 194), from: anchor), .topLeading)
        XCTAssertEqual(OverlayController.growAnchor(frame: CGRect(x: 90, y: 300, width: 404, height: 194), from: anchor), .topTrailing)
        XCTAssertEqual(OverlayController.growAnchor(frame: CGRect(x: 506, y: 506, width: 400, height: 194), from: anchor), .bottomLeading)
        XCTAssertEqual(OverlayController.growAnchor(frame: CGRect(x: 90, y: 506, width: 404, height: 194), from: anchor), .bottomTrailing)
    }

    func testMoreNavigationDoesNotBecomeAPendingPluginOrCloseWhileLoading() {
        for loading in [true, false] {
            for closes in [true, false] {
                XCTAssertEqual(RingReleaseAction.decide(hovered: nil, selectable: nil, isLoading: loading,
                                                       closesOnRelease: closes, isOverflow: true), .showOverflow)
            }
        }
    }

    @MainActor
    func testEdgeLayoutAndOriginalSlotIDsStayFrozenWhenContentArrives() {
        let layout = RingLayout.default
        let ring = RingViewModel(layout: layout, catalog: BuiltinPlugins.make().map(\.info),
                                 installed: Set(layout.slots.compactMap { $0 }), content: nil)
        let anchor = CGPoint(x: -1280, y: 880)
        ring.freezePlacement(anchor: anchor, safeFrame: CGRect(x: -1280, y: 0, width: 1280, height: 880))
        let before = ring.placement
        let ids = ring.visibleSlots.map(\.id)
        XCTAssertEqual(before?.anchor, anchor)
        XCTAssertFalse(ring.geometry.isFullCircle)
        ring.setHovered(ids[0])
        let angle = ring.highlightAngle
        ring.update(content: ContentClassifier.classify(.text("Good morning")))
        XCTAssertEqual(ring.placement, before)
        XCTAssertEqual(ring.visibleSlots.map(\.id), ids)
        XCTAssertEqual(ring.slots.map(\.id), Array(0..<layout.slots.count))
        XCTAssertEqual(ring.hovered, ids[0])
        XCTAssertEqual(ring.highlightAngle, angle)
        // 返回原菜单也不能用新指针或新屏幕重新排版。
        ring.freezePlacement(anchor: CGPoint(x: 400, y: 400), safeFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        XCTAssertEqual(ring.placement, before)
    }

    @MainActor
    func testOverflowKeepsEveryOriginalSlotAndKeyboardVisitsMore() {
        let layout = RingLayout(slots: Array(repeating: BuiltinPluginID.clipboardHistory, count: 12))
        let ring = RingViewModel(layout: layout, catalog: BuiltinPlugins.make().map(\.info),
                                 installed: [BuiltinPluginID.clipboardHistory], content: nil)
        ring.freezePlacement(anchor: CGPoint(x: 0, y: 600), safeFrame: CGRect(x: 0, y: 0, width: 800, height: 600))
        XCTAssertTrue(ring.placement?.hasOverflow == true)
        XCTAssertEqual(ring.visibleSlots.last?.id, ring.overflowID)
        XCTAssertEqual(ring.slots.count, 12)
        var visited: [Int] = []
        for _ in ring.visibleSlots {
            let next = ring.nextVisibleSlot(by: 1)
            visited.append(next)
            ring.setHovered(next)
        }
        XCTAssertEqual(visited, ring.visibleSlots.map(\.id))
        XCTAssertTrue(ring.isOverflow(ring.hovered))
        XCTAssertNil(ring.pluginSlot(ring.overflowID))
        XCTAssertNil(ring.selectablePlugin(at: ring.overflowID))
        XCTAssertEqual(ring.nextVisibleSlot(by: 1), 0)
        ring.update(content: .empty)
        for id in 0..<12 {
            XCTAssertEqual(ring.selectablePlugin(at: id)?.id, BuiltinPluginID.clipboardHistory,
                           "隐藏在更多里的原始功能仍能执行")
        }
    }

    @MainActor
    func testAdaptiveRenderedPositionsMatchHoverAndDragContinuation() {
        let layout = RingLayout.default
        let ring = RingViewModel(layout: layout, catalog: BuiltinPlugins.make().map(\.info),
                                 installed: Set(layout.slots.compactMap { $0 }), content: .empty)
        ring.freezePlacement(anchor: CGPoint(x: 0, y: 450), safeFrame: CGRect(x: 0, y: 0, width: 1440, height: 900))
        for (position, slot) in ring.visibleSlots.enumerated() {
            let offset = ring.geometry.slotCenterOffset(position)
            ring.updateHover(offset: offset)
            XCTAssertEqual(ring.hovered, slot.id)
            ring.updateHover(offset: CGVector(dx: offset.dx * 3, dy: offset.dy * 3))
            XCTAssertEqual(ring.hovered, slot.id, "按住划出圆弧后仍沿同一方向选择")
        }
        ring.updateHover(offset: .zero)
        XCTAssertNil(ring.hovered)
        ring.updateHover(offset: CGVector(dx: -200, dy: 0))
        XCTAssertNil(ring.hovered, "朝弧外划动不选中")
    }


    func testExplicitMoreNavigationCancelsOldPendingSelectionAndSurvivesBack() {
        var intent = RingLoadingIntent()
        XCTAssertFalse(intent.preservesMenu)
        intent.waitForSlot(3)
        XCTAssertEqual(intent.pendingSlot, 3)
        intent.navigateMenu()
        XCTAssertNil(intent.pendingSlot, "打开更多不能再执行先前等待读取的选择")
        XCTAssertTrue(intent.preservesMenu, "返回圆盘后仍只更新内容，不走直达规则")
        intent.waitForSlot(1)
        XCTAssertEqual(intent.pendingSlot, 1, "返回后明确选择一个新功能仍可以等待执行")
        intent.clearPendingSlot()
        XCTAssertNil(intent.pendingSlot)
        XCTAssertTrue(intent.preservesMenu)
    }


    @MainActor
    func testNativeOverlayKeepsAnchorAndCancelsRingWhenDisplaysChange() {
        let overlay = OverlayController()
        let safeFrame = OverlayController.visibleFrame(containing: .zero)
        let anchor = CGPoint(x: safeFrame.minX + 1, y: safeFrame.maxY - 1)
        let ring = RingViewModel(layout: .default, catalog: [], installed: [], content: .empty)
        var dismissed = false
        overlay.onDismiss = { dismissed = true }
        overlay.showRing(ring, center: anchor)
        XCTAssertEqual(overlay.mode, .ring)
        XCTAssertEqual(overlay.ringCenter, anchor)
        XCTAssertEqual(ring.placement?.anchor, anchor)
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        XCTAssertTrue(dismissed)
        XCTAssertEqual(overlay.mode, .hidden)
        XCTAssertNil(overlay.ringCenter)
        overlay.hide(animated: false)
    }

    @MainActor
    func testNativeOverflowCardCancelsInsteadOfMovingWhenDisplaysChange() {
        let overlay = OverlayController()
        var dismissed = false
        overlay.onDismiss = { dismissed = true }
        overlay.showCard(Text("读取中…"), anchor: CGPoint(x: 100, y: 100), cancelsOnScreenChange: true)
        XCTAssertEqual(overlay.mode, .card)
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        XCTAssertTrue(dismissed)
        XCTAssertEqual(overlay.mode, .hidden)
        overlay.hide(animated: false)
    }

}
