import XCTest
@testable import Pop

/// 主线程不能被很大的内容卡住：圆盘、分发规则、工具条、「全部功能」都只查后台看好的结果
@MainActor
final class MainThreadTests: XCTestCase {
    /// 选中了 5 MB 的 JSON：识别、数字数、每个功能能不能处理都在后台看好（有 checked），
    /// 主线程上建圆盘、走分发规则、排工具条、列「全部功能」加起来不到 0.1 秒
    func testLongSelectionIsCheckedOffTheMainThread() async throws {
        let catalog = TestCatalog.infos()
        let installed = Set(catalog.map(\.id))
        let line = #"{"name": "Pop", "tags": ["ring", "card"], "count": 12345, "note": "hello world, 你好"},"# + "\n"
        let text = "[" + String(repeating: line, count: 60_000) + "{}]"
        XCTAssertGreaterThan(text.utf8.count, 5_000_000)

        let content = await ContentClassifier.classifyOffMain(.text(text), catalog: catalog)
        XCTAssertTrue(content.kinds.contains(.json))
        let checked = try XCTUnwrap(content.checked)
        XCTAssertEqual(Set(checked.handled.keys), installed)

        let started = Date()
        let ring = RingViewModel(layout: .default, catalog: catalog, installed: installed, content: content)
        let decision = Router.decide(content, settings: AppSettings(), catalog: catalog)
        let toolbar = SelectionToolbarLogic.items(layout: .default, catalog: catalog, installed: installed, content: content)
        let chooser = catalog.filter { $0.id != BuiltinPluginID.allPlugins && $0.canHandle(content) }
        let elapsed = Date().timeIntervalSince(started)
        XCTAssertLessThan(elapsed, 0.1)

        // 查的是后台看好的结果，和当场看的一样
        XCTAssertEqual(chooser.map(\.id), catalog.filter { info in
            info.id != BuiltinPluginID.allPlugins && checked.handled[info.id] == true
        }.map(\.id))
        XCTAssertFalse(chooser.isEmpty)
        XCTAssertEqual(ring.slots.filter(\.enabled).count, ring.slots.filter { $0.info.map { checked.handled[$0.id] == true } ?? false }.count)
        XCTAssertEqual(ring.center.title, "JSON")
        _ = decision
        _ = toolbar
    }
}
