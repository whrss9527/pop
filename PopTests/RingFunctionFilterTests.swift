import XCTest
@testable import Pop

/// 设置里圆盘那一页左边的功能列表：搜索、按分类和放没放上圆盘过滤
final class RingFunctionFilterTests: XCTestCase {
    private func info(_ id: String, _ name: String, _ summary: String) -> PluginInfo {
        PluginInfo(id: id, name: name, symbol: "circle", summary: summary, accepts: [])
    }

    private var functions: [PluginInfo] {
        [info(BuiltinPluginID.translate, "翻译", "把选中的外文翻译成中文"),
         info(BuiltinPluginID.search, "搜索", "用搜索引擎搜选中的文字"),
         info(BuiltinPluginID.hash, "哈希", "算 MD5、SHA-256"),
         info(BuiltinPluginID.ocr, "识别文字", "认出图片里的文字")]
    }

    private let layout = RingLayout(slots: [BuiltinPluginID.translate, nil, BuiltinPluginID.hash, nil])

    private func ids(_ query: String, category: BuiltinCategory? = nil, placement: RingFunctionFilter.Placement = .all) -> [String] {
        RingFunctionFilter.sections(functions, layout: layout, query: query, category: category, placement: placement)
            .flatMap(\.functions).map(\.id)
    }

    func testGroupsByCategory() {
        let sections = RingFunctionFilter.sections(functions, layout: layout, query: "", category: nil, placement: .all)
        XCTAssertEqual(sections.map(\.category), [.text, .developer, .screen])
        XCTAssertEqual(sections.first?.functions.map(\.id), [BuiltinPluginID.translate, BuiltinPluginID.search])
    }

    func testSearch() {
        // 拼音首字母、全拼、说明里的字
        XCTAssertEqual(ids("fy"), [BuiltinPluginID.translate])
        XCTAssertEqual(ids("shibie"), [BuiltinPluginID.ocr])
        XCTAssertEqual(ids("SHA-256"), [BuiltinPluginID.hash])
        XCTAssertEqual(ids("  "), [BuiltinPluginID.translate, BuiltinPluginID.search, BuiltinPluginID.hash, BuiltinPluginID.ocr])
        XCTAssertTrue(ids("xyz").isEmpty)
    }

    func testCategoryAndPlacement() {
        XCTAssertEqual(ids("", category: .developer), [BuiltinPluginID.hash])
        XCTAssertTrue(ids("fy", category: .developer).isEmpty)
        XCTAssertEqual(ids("", placement: .unplaced), [BuiltinPluginID.search, BuiltinPluginID.ocr])
        XCTAssertEqual(ids("", placement: .placed), [BuiltinPluginID.translate, BuiltinPluginID.hash])
        XCTAssertEqual(RingFunctionFilter.Placement.allCases.map(\.title), ["全部", "未放置", "已放置"])
    }
}
