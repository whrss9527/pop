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
}
