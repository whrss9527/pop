import AppKit
import XCTest
@testable import Pop

@MainActor
final class RingAppearanceInteractionTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private var catalog: [PluginInfo] {
        (0..<8).map { PluginInfo(id: "appearance-\($0)", name: "原名称\($0)", symbol: "star", summary: "", accepts: []) }
    }

    private func model(_ layout: RingLayout, content: ClassifiedContent? = .empty) -> RingViewModel {
        RingViewModel(layout: layout, catalog: catalog, installed: Set(catalog.map(\.id)), content: content,
                      hapticFeedback: {})
    }

    private func layout(_ appearance: RingAppearance = .default, alias: String = "我的功能") -> RingLayout {
        RingLayout(slots: catalog.map { Optional($0.id) }, appearance: appearance, customNames: ["appearance-0": alias])
    }

    func testAliasChangesRingAndCenterWithoutRenamingTheExecutablePlugin() {
        let ring = model(layout(alias: "  我的功能  "), content: nil)
        XCTAssertEqual(ring.slots[0].displayName, "我的功能")
        XCTAssertEqual(ring.slots[1].displayName, "原名称1")
        ring.setHovered(0)
        XCTAssertEqual(ring.center.title, "我的功能")
        XCTAssertNil(ring.selectablePlugin(at: 0))
        ring.update(content: .empty)
        XCTAssertEqual(ring.center.title, "我的功能")
        XCTAssertEqual(ring.selectablePlugin(at: 0)?.id, "appearance-0")
        XCTAssertEqual(ring.selectablePlugin(at: 0)?.name, "原名称0")
        XCTAssertEqual(ring.configuredSlotIDs, catalog.map { Optional($0.id) })
    }

    func testAppearanceAndAliasStayFrozenThroughContentCommitAndReturn() throws {
        var configuration = layout(RingAppearance(shape: .circle, scale: 1.2))
        let ring = model(configuration, content: nil)
        ring.freezePlacement(anchor: CGPoint(x: 0, y: 450), safeFrame: screen, displayScale: 2)
        let frozen = try XCTUnwrap(ring.placement)
        let ids = ring.visibleSlots.map(\.id)
        XCTAssertEqual(frozen.appearance, configuration.appearance.normalized)
        XCTAssertEqual(frozen.buttonSize, RingButtonMetrics(slotCount: 8, appearance: ring.appearance).bodySize)
        configuration.appearance = RingAppearance(shape: .square, scale: 0.8)
        configuration.setCustomName("后来改名", for: "appearance-0")
        ring.update(content: .empty)
        XCTAssertEqual(ring.appearance, RingAppearance(shape: .circle, scale: 1.2))
        XCTAssertEqual(ring.slots[0].displayName, "我的功能")
        for (physical, originalID) in ids.enumerated() {
            ring.updateHover(offset: ring.geometry.slotCenterOffset(physical))
            XCTAssertEqual(ring.hovered, originalID)
            XCTAssertEqual(ring.selectablePlugin(at: originalID)?.id, "appearance-\(originalID)")
        }
        ring.commit(0)
        ring.resetSelection()
        ring.freezePlacement(anchor: CGPoint(x: 720, y: 450), safeFrame: screen,
                             displayScale: 1, appearance: configuration.appearance)
        XCTAssertEqual(ring.placement, frozen)
        XCTAssertEqual(ring.visibleSlots.map(\.id), ids)
    }

    func testNewInvocationAndResetApplyOnlyTheNewPresentation() throws {
        var configuration = layout(RingAppearance(shape: .circle, scale: 1.6))
        let first = model(configuration)
        first.freezePlacement(anchor: CGPoint(x: 720, y: 450), safeFrame: screen)
        configuration.appearance = RingAppearance(shape: .square, scale: 0.8)
        configuration.setCustomName("方形功能", for: "appearance-0")
        let second = model(configuration)
        second.freezePlacement(anchor: CGPoint(x: 720, y: 450), safeFrame: screen)
        XCTAssertEqual(second.placement?.appearance.shape, .square)
        XCTAssertNotEqual(first.placement?.buttonSize, second.placement?.buttonSize)
        XCTAssertEqual(first.configuredSlotIDs, second.configuredSlotIDs)
        XCTAssertEqual(second.slots[0].displayName, "方形功能")
        configuration.resetAppearance()
        configuration.setCustomName(nil, for: "appearance-0")
        let reset = model(configuration)
        XCTAssertEqual(reset.appearance, .default)
        XCTAssertEqual(reset.slots[0].displayName, "原名称0")
        XCTAssertEqual(reset.selectablePlugin(at: 0)?.name, "原名称0")
        XCTAssertEqual(reset.configuredSlotIDs, second.configuredSlotIDs)
    }

    func testPendingImplementationKeepsAliasAndCannotBecomeExecutable() {
        let id = PluginCatalog.packages[0].functions[0]
        let configuration = RingLayout(slots: [id, nil, nil, nil], customNames: [id: "我的待更新功能"])
        let ring = RingViewModel(layout: configuration, catalog: [], installed: [id], content: nil, hapticFeedback: {})
        XCTAssertNotNil(ring.slots[0].pendingPackage)
        XCTAssertEqual(ring.slots[0].displayName, "我的待更新功能")
        ring.setHovered(0)
        XCTAssertEqual(ring.center.title, "我的待更新功能")
        XCTAssertFalse(ring.center.enabled)
        ring.update(content: .empty)
        XCTAssertNil(ring.selectablePlugin(at: 0))
        XCTAssertEqual(ring.slots[0].displayName, "我的待更新功能")
    }

    func testActualContentLayoutFitsAllShapesAndKeepsReadableCaptionMetrics() {
        for shape in RingButtonShape.allCases {
            for count in [4, 8, 12] {
                for scale in [0.8, 1, 1.6] {
                    let appearance = RingAppearance(shape: shape, scale: scale)
                    let metrics = RingButtonMetrics(slotCount: count, appearance: appearance)
                    let content = RingLabelContentLayout(metrics: metrics, appearance: appearance, slotCount: count)
                    XCTAssertGreaterThanOrEqual(content.captionSize, 9)
                    XCTAssertGreaterThanOrEqual(content.glyphSize, 9)
                    XCTAssertLessThanOrEqual(content.glyphHeight + content.captionHeight + content.spacing,
                                             content.contentSize.height + 0.000_001)
                    XCTAssertLessThanOrEqual(content.contentSize.width, metrics.bodySize.width)
                    XCTAssertLessThanOrEqual(content.contentSize.height, metrics.bodySize.height)
                    XCTAssertLessThanOrEqual(content.glyphSize * 1.06, content.glyphHeight + 0.000_001)
                    let font = NSFont.systemFont(ofSize: content.captionSize, weight: .medium)
                    XCTAssertLessThanOrEqual(font.ascender - font.descender + font.leading, content.captionHeight)
                    if shape == .circle {
                        XCTAssertLessThanOrEqual(hypot(content.contentSize.width / 2, content.contentSize.height / 2),
                                                 metrics.bodySize.width / 2 + 0.000_001,
                                                 "图标与文字的整个矩形都需留在真实圆形内")
                    }
                }
            }
        }
    }

    func testInjectedFeedbackTracksOnlyNewEnabledSelections() {
        let enabled = PluginInfo(id: "enabled", name: "可用", symbol: "star", summary: "", accepts: [])
        let disabled = PluginInfo(id: "disabled", name: "需文件", symbol: "doc", summary: "", accepts: [.files])
        var feedback = 0
        let ring = RingViewModel(layout: RingLayout(slots: [enabled.id, disabled.id, nil, nil]),
                                 catalog: [enabled, disabled], installed: [enabled.id, disabled.id], content: nil,
                                 hapticFeedback: { feedback += 1 })
        ring.setHovered(0)
        XCTAssertEqual(feedback, 0, "读取中不能自动反馈")
        ring.update(content: .empty)
        ring.setHovered(0)
        XCTAssertEqual(feedback, 0, "内容到达和同编号重绘不触发反馈")
        ring.setHovered(nil)
        ring.setHovered(0)
        XCTAssertEqual(feedback, 1)
        ring.setHovered(0)
        ring.setHovered(1)
        XCTAssertEqual(feedback, 1, "重复高亮和不可用目标不触发反馈")
        ring.setHovered(0)
        XCTAssertEqual(feedback, 2)
        ring.commit(0)
        ring.setHovered(1)
        XCTAssertEqual(feedback, 2, "确认冻结后不因指针变化再反馈")
        ring.resetSelection()
        ring.setHovered(0)
        XCTAssertEqual(feedback, 3)
    }
}
