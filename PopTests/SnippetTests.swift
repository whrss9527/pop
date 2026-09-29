import XCTest
@testable import Pop

final class SnippetTests: XCTestCase {
    func testExpandingPlaceholders() throws {
        let utc = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let date = Date(timeIntervalSince1970: 1_790_000_000) // 2026-09-21 14:13:20 UTC，星期一
        let text = "{date} {time} {datetime} {weekday} [{clipboard}] [{selection}]"
        XCTAssertEqual(SnippetExpander.expand(text, date: date, timeZone: utc, clipboard: "剪贴板", selection: "选中"),
                       "2026-09-21 14:13 2026-09-21 14:13 星期一 [剪贴板] [选中]")
        XCTAssertEqual(SnippetExpander.expand("{clipboard}{selection}", date: date, timeZone: utc), "")
        XCTAssertEqual(SnippetExpander.expand("没有占位符"), "没有占位符")
        XCTAssertEqual(SnippetExpander.expand("{unknown}"), "{unknown}")
    }

    func testDisplayTitleAndDecoding() throws {
        XCTAssertEqual(Snippet(title: "  签名 ", text: "x").displayTitle, "签名")
        XCTAssertEqual(Snippet(title: "", text: "第一行\n第二行").displayTitle, "第一行")
        // 新装时带两个例子；删光以后不会再冒出来
        XCTAssertEqual(AppSettings().snippets, Snippet.examples)
        var settings = AppSettings()
        settings.snippets = []
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertTrue(decoded.snippets.isEmpty)
        // 缺了内容的那条跳过，没有 id 的补一个
        let lossy = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"snippets": [{"title": "坏的"}, {"title": "好的", "text": "hi"}]}"#.utf8))
        XCTAssertEqual(lossy.snippets.map(\.title), ["好的"])
        XCTAssertFalse(lossy.snippets[0].id.isEmpty)
    }

    @MainActor
    func testPickerSearchAndKeys() throws {
        let model = SnippetPickerModel(snippets: [Snippet(title: "邮件结尾", text: "祝好"), Snippet(title: "地址", text: "上海市")])
        XCTAssertEqual(model.results.count, 2)
        model.query = "yj"
        XCTAssertEqual(model.results.map(\.title), ["邮件结尾"])
        model.query = "上海"
        XCTAssertEqual(model.results.map(\.title), ["地址"])
        model.query = ""
        var pasted: Snippet?
        model.onPaste = { pasted = $0 }
        let down = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                                  context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false,
                                                  keyCode: 125))
        XCTAssertTrue(model.handleKey(down))
        XCTAssertEqual(model.selection, 1)
        let enter = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                                   context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false,
                                                   keyCode: 36))
        XCTAssertTrue(model.handleKey(enter))
        XCTAssertEqual(pasted?.title, "地址")
    }

    @MainActor
    func testPluginOpensThePicker() async {
        let outcome = await SnippetsPlugin().run(.empty, context: PluginContext(settings: AppSettings(), openSettings: {}))
        XCTAssertEqual(outcome, .showSnippets)
    }
}
