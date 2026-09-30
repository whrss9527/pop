import XCTest
@testable import Pop

final class SelectionToolbarTests: XCTestCase {
    /// 单击、拖文件不去读选区；拖着选了一段、双击选词、三击选段才读
    func testOnlyRealSelectionsAreChecked() {
        let origin = CGPoint(x: 100, y: 100)
        XCTAssertFalse(SelectionToolbarLogic.isSelectionGesture(from: origin, to: CGPoint(x: 103, y: 101), clickCount: 1,
                                                                startedDragAndDrop: false), "单击")
        XCTAssertTrue(SelectionToolbarLogic.isSelectionGesture(from: origin, to: CGPoint(x: 160, y: 100), clickCount: 1,
                                                               startedDragAndDrop: false), "拖着选了一段")
        XCTAssertFalse(SelectionToolbarLogic.isSelectionGesture(from: origin, to: CGPoint(x: 160, y: 100), clickCount: 1,
                                                                startedDragAndDrop: true), "拖文件")
        XCTAssertTrue(SelectionToolbarLogic.isSelectionGesture(from: origin, to: origin, clickCount: 2, startedDragAndDrop: false),
                      "双击选词")
        XCTAssertTrue(SelectionToolbarLogic.isSelectionGesture(from: origin, to: origin, clickCount: 3, startedDragAndDrop: false),
                      "三击选段")
        XCTAssertFalse(SelectionToolbarLogic.isSelectionGesture(from: origin, to: origin, clickCount: 4, startedDragAndDrop: false))
    }

    /// 按圆盘的顺序取能处理这段文字的功能；不需要选中内容的（剪贴板）和处理不了的（复制路径）不放
    @MainActor
    func testItemsFollowTheRingAndTheContent() {
        let catalog = BuiltinPlugins.make().map(\.info)
        let layout = RingLayout(slots: [BuiltinPluginID.translate, BuiltinPluginID.clipboardHistory, nil, BuiltinPluginID.search,
                                        BuiltinPluginID.copyPath, BuiltinPluginID.calculate])
        let installed = Set(layout.slots.compactMap { $0 })
        let text = ContentClassifier.classify(.text("Good morning"))
        XCTAssertEqual(SelectionToolbarLogic.items(layout: layout, catalog: catalog, installed: installed, content: text).map(\.id),
                       [BuiltinPluginID.translate, BuiltinPluginID.search])
        XCTAssertEqual(SelectionToolbarLogic.items(layout: layout, catalog: catalog, installed: installed, content: text, limit: 1).map(\.id),
                       [BuiltinPluginID.translate])
        XCTAssertEqual(SelectionToolbarLogic.items(layout: layout, catalog: catalog, installed: [BuiltinPluginID.search], content: text)
                           .map(\.id), [BuiltinPluginID.search], "没装的不放")
        let math = ContentClassifier.classify(.text("12*3"))
        XCTAssertTrue(SelectionToolbarLogic.items(layout: layout, catalog: catalog, installed: installed, content: math).map(\.id)
                          .contains(BuiltinPluginID.calculate))
    }

    /// 放在选区上方正中；顶上放不下放到下面；不出屏幕；选了好几段时对着鼠标
    func testFramePrefersAboveTheSelection() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let size = CGSize(width: 300, height: 60)
        let frame = SelectionToolbarLogic.frame(size: size, selection: CGRect(x: 500, y: 400, width: 200, height: 18),
                                                pointer: CGPoint(x: 700, y: 405), screen: screen)
        XCTAssertEqual(frame, CGRect(x: 450, y: 424, width: 300, height: 60))
        let top = SelectionToolbarLogic.frame(size: size, selection: CGRect(x: 500, y: 860, width: 200, height: 18),
                                              pointer: CGPoint(x: 600, y: 865), screen: screen)
        XCTAssertEqual(top.maxY, 854)
        let left = SelectionToolbarLogic.frame(size: size, selection: CGRect(x: 0, y: 400, width: 40, height: 18),
                                               pointer: CGPoint(x: 10, y: 405), screen: screen)
        XCTAssertEqual(left.minX, 4)
        let tall = SelectionToolbarLogic.frame(size: size, selection: CGRect(x: 100, y: 100, width: 800, height: 400),
                                               pointer: CGPoint(x: 600, y: 120), screen: screen)
        XCTAssertEqual(tall.midX, 600)
        XCTAssertEqual(tall.minY, 136)
        let unknown = SelectionToolbarLogic.frame(size: size, selection: nil, pointer: CGPoint(x: 600, y: 120), screen: screen)
        XCTAssertEqual(unknown, tall)
    }

    func testAccessibilityRectsAndDistance() {
        let rect = SelectionToolbarLogic.appKitRect(fromQuartz: CGRect(x: 10, y: 100, width: 50, height: 20), primaryScreenHeight: 900)
        XCTAssertEqual(rect, CGRect(x: 10, y: 780, width: 50, height: 20))
        XCTAssertTrue(SelectionToolbarLogic.selection(rect, isNear: CGPoint(x: 70, y: 790)))
        XCTAssertFalse(SelectionToolbarLogic.selection(rect, isNear: CGPoint(x: 400, y: 790)), "拖的是别处，选区还是之前那一段")
    }

    /// 默认关闭；旧设置里没有这一项也是关闭；打开后能存能读
    func testSettingsDefaultToOff() throws {
        XCTAssertFalse(AppSettings().toolbar.enabled)
        XCTAssertFalse(try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8)).toolbar.enabled)
        var settings = AppSettings()
        settings.toolbar.enabled = true
        settings.toolbar.excludedBundleIDs = ["com.apple.Terminal"]
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(decoded.toolbar, settings.toolbar)
    }
}
