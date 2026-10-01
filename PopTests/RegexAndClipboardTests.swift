import AppKit
import XCTest
@testable import Pop

final class RegexTesterTests: XCTestCase {
    func testMatchesAndGroups() {
        let result = RegexTester.run(#"(?<year>\d{4})-(\d{2})"#, on: "发布于 2026-09 和 2025-12")
        XCTAssertNil(result.error)
        XCTAssertEqual(result.matches.map(\.text), ["2026-09", "2025-12"])
        XCTAssertEqual(result.matches.first?.groups, ["2026", "09"])
        XCTAssertEqual(result.matches.first?.groupNames, ["year", nil])
        XCTAssertEqual(RegexTester.describe(result.matches[0]), "2026-09 · year = 2026 · $2 = 09")
        // 没参与匹配的分组
        XCTAssertEqual(RegexTester.run("a(b)?", on: "a").matches.first?.groups, [nil])
    }

    func testOptions() {
        XCTAssertEqual(RegexTester.run("pop", on: "Pop POP pop").matches.count, 1)
        XCTAssertEqual(RegexTester.run("pop", on: "Pop POP pop", options: .init(ignoreCase: true)).matches.count, 3)
        // ^ $ 默认匹配每一行
        XCTAssertEqual(RegexTester.run("^a", on: "a\na\nb").matches.count, 2)
        XCTAssertEqual(RegexTester.run("^a", on: "a\na\nb", options: .init(multiline: false)).matches.count, 1)
        XCTAssertEqual(RegexTester.run("a.b", on: "a\nb").matches.count, 0)
        XCTAssertEqual(RegexTester.run("a.b", on: "a\nb", options: .init(dotAll: true)).matches.count, 1)
    }

    func testErrorsAndReplacement() {
        XCTAssertNotNil(RegexTester.run("(unclosed", on: "x").error)
        XCTAssertEqual(RegexTester.run("", on: "x"), RegexTester.Result())
        XCTAssertEqual(RegexTester.replace(#"(\d+)-(\d+)"#, with: "$2/$1", in: "10-20 和 3-4"), "20/10 和 4/3")
        XCTAssertNil(RegexTester.replace("[", with: "", in: "x"))
    }

    func testGroupNames() {
        XCTAssertEqual(RegexTester.groupNames(in: #"(?<a>x)(?:y)(z)(?=w)(?<!v)\((?<b>.)"#, count: 3), ["a", nil, "b"])
        XCTAssertEqual(RegexTester.groupNames(in: #"[(](x)"#, count: 1), [nil])
        // 数不对时不显示名字
        XCTAssertEqual(RegexTester.groupNames(in: "(x)", count: 2), [nil, nil])
    }

    func testTruncatesLongResults() {
        let result = RegexTester.run("a", on: String(repeating: "a", count: RegexTester.maxMatches + 10))
        XCTAssertEqual(result.matches.count, RegexTester.maxMatches)
        XCTAssertTrue(result.truncated)
    }

    func testPresetsCompile() throws {
        for preset in RegexTester.presets {
            XCTAssertNoThrow(try NSRegularExpression(pattern: preset.pattern), preset.title)
        }
        let dates = try XCTUnwrap(RegexTester.presets.first { $0.title == "日期" })
        XCTAssertEqual(RegexTester.run(dates.pattern, on: "2026-09-29").matches.first?.groupNames, ["year", "month", "day"])
    }

    @MainActor
    func testPreviewHeightFollowsTheText() {
        // 至少两行高，最多七行
        XCTAssertEqual(RegexTesterModel.previewHeight(for: "a"), 40)
        XCTAssertEqual(RegexTesterModel.previewHeight(for: "a\nb\nc"), 56)
        XCTAssertEqual(RegexTesterModel.previewHeight(for: String(repeating: "长", count: 2000)), 120)
    }

    @MainActor
    func testPluginOpensTheTester() async {
        let context = PluginContext(settings: AppSettings(), openSettings: {})
        let outcome = await RegexTestPlugin().run(ContentClassifier.classify(.text(" a1 b2 \n")), context: context)
        // 插件包自己弹出正则测试卡片
        guard case .present = outcome else { return XCTFail("\(outcome)") }
    }
}

@MainActor
final class ClipboardHistoryModelTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "pop-history-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func key(_ code: UInt16, characters: String = "", modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0,
                                       context: nil, characters: characters, charactersIgnoringModifiers: characters,
                                       isARepeat: false, keyCode: code))
    }

    func testFiltersAndMergedPaste() throws {
        let store = ClipboardStore(directory: directory)
        let start = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertNotNil(store.add(ClipboardCapture(kind: .text, text: "第一条"), at: start))
        XCTAssertNotNil(store.add(ClipboardCapture(kind: .text, text: "第二条"), at: start + 1))
        XCTAssertNotNil(store.add(ClipboardCapture(kind: .files, text: "/tmp/a.txt"), at: start + 2))
        let model = ClipboardHistoryModel(service: ClipboardService(store: store))
        XCTAssertEqual(model.items.count, 3)
        model.filter = .text
        XCTAssertEqual(model.items.map(\.text), ["第二条", "第一条"])
        model.filter = .files
        XCTAssertEqual(model.items.count, 1)
        model.filter = .pinned
        XCTAssertTrue(model.items.isEmpty)
        model.filter = .all

        var pasted: String?
        model.onPasteText = { pasted = $0 }
        let first = try XCTUnwrap(model.items.first { $0.text == "第一条" })
        let second = try XCTUnwrap(model.items.first { $0.text == "第二条" })
        let file = try XCTUnwrap(model.items.first { $0.kind == .files })
        model.toggleMark(first)
        model.toggleMark(second)
        // 文件不能和文字合在一起
        model.toggleMark(file)
        XCTAssertEqual(model.markNumber(of: first), 1)
        XCTAssertEqual(model.markNumber(of: second), 2)
        XCTAssertNil(model.markNumber(of: file))
        XCTAssertEqual(model.mergedText, "第一条\n第二条")
        XCTAssertTrue(model.handleKey(try key(36, characters: "\r")))
        XCTAssertEqual(pasted, "第一条\n第二条")
        // Esc 先取消多选，没有多选时交给面板关闭
        XCTAssertTrue(model.handleKey(try key(53)))
        XCTAssertTrue(model.marked.isEmpty)
        XCTAssertFalse(model.handleKey(try key(53)))
        // 再点一次移出多选
        model.toggleMark(first)
        model.toggleMark(first)
        XCTAssertTrue(model.marked.isEmpty)
    }
}

final class LinkCleaningTests: XCTestCase {
    func testCleanedLink() {
        XCTAssertEqual(LinkInspector.cleanedLink(in: " https://example.com/a?id=3&utm_source=x \n"), "https://example.com/a?id=3")
        // 留下的参数保持原来的编码
        XCTAssertEqual(LinkInspector.cleanedLink(in: "https://example.com/s?q=a%2Bb&fbclid=1"), "https://example.com/s?q=a%2Bb")
        XCTAssertNil(LinkInspector.cleanedLink(in: "看看 https://example.com/?utm_source=x"))
        XCTAssertNil(LinkInspector.cleanedLink(in: "https://example.com/?q=pop"))
        XCTAssertNil(LinkInspector.cleanedLink(in: "ftp://example.com/?utm_source=x"))
    }

    func testSettingIsOffByDefault() throws {
        XCTAssertFalse(ClipboardSettings().cleanLinks)
        let old = try JSONDecoder().decode(ClipboardSettings.self, from: Data(#"{"enabled": true}"#.utf8))
        XCTAssertFalse(old.cleanLinks)
        let on = try JSONDecoder().decode(ClipboardSettings.self, from: Data(#"{"cleanLinks": true}"#.utf8))
        XCTAssertTrue(on.cleanLinks)
    }
}
