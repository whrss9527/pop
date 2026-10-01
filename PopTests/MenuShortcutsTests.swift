import AppKit
import XCTest
@testable import Pop

final class MenuShortcutsTests: XCTestCase {
    func testWritesShortcutsInMenuOrder() {
        XCTAssertEqual(MenuShortcuts.shortcut(character: "s", modifiers: 0, glyph: nil), "⌘S")
        XCTAssertEqual(MenuShortcuts.shortcut(character: "S", modifiers: 1, glyph: nil), "⇧⌘S")
        XCTAssertEqual(MenuShortcuts.shortcut(character: "f", modifiers: 4 | 2, glyph: nil), "⌃⌥⌘F")
        XCTAssertEqual(MenuShortcuts.shortcut(character: ",", modifiers: 0, glyph: nil), "⌘,")
        // 特殊键用图形编号给出：⌘⌫、⌃⌘␣
        XCTAssertEqual(MenuShortcuts.shortcut(character: "\u{8}", modifiers: 0, glyph: 0x17), "⌘⌫")
        XCTAssertEqual(MenuShortcuts.shortcut(character: " ", modifiers: 4, glyph: 0x09), "⌃⌘␣")
        // 方向键、功能键是私用区的字符
        XCTAssertEqual(MenuShortcuts.shortcut(character: "\u{F702}", modifiers: 2, glyph: nil), "⌥⌘←")
        XCTAssertEqual(MenuShortcuts.shortcut(character: "\u{F704}", modifiers: 8, glyph: nil), "F1")
        // 没有快捷键
        XCTAssertNil(MenuShortcuts.shortcut(character: nil, modifiers: 0, glyph: nil))
        XCTAssertNil(MenuShortcuts.shortcut(character: "", modifiers: 0, glyph: nil))
        XCTAssertNil(MenuShortcuts.shortcut(character: "\u{F8FF}", modifiers: 0, glyph: nil))
    }

    func testFlattensMenusIntoRows() {
        let items = MenuShortcuts.flatten(Self.menus)
        XCTAssertEqual(items.map(\.path), [["文件", "新建窗口"], ["文件", "导出为", "PDF…"], ["文件", "关闭"],
                                           ["编辑", "撤销"], ["编辑", "查找"]])
        XCTAssertEqual(items[1].menu, "文件 › 导出为")
        XCTAssertEqual(items[1].title, "PDF…")
        XCTAssertEqual(items.map(\.shortcut), ["⌘N", "⌥⌘P", "⌘W", "⌘Z", nil])
        XCTAssertFalse(items[3].enabled)
        XCTAssertEqual(Set(items.map(\.id)).count, items.count)
    }

    @MainActor
    func testSearchesAndSwitchesScope() throws {
        let model = MenuShortcutsModel(appName: "文本编辑")
        XCTAssertTrue(model.isLoading)
        model.load(Self.menus)
        XCTAssertFalse(model.isLoading)
        XCTAssertEqual(model.shortcutCount, 4)
        XCTAssertEqual(model.totalCount, 5)
        // 默认只列有快捷键的
        XCTAssertEqual(model.results.map(\.title), ["新建窗口", "PDF…", "关闭", "撤销"])
        model.query = "xjck"
        XCTAssertEqual(model.results.map(\.title), ["新建窗口"])
        model.query = "导出"
        XCTAssertEqual(model.results.map(\.title), ["PDF…"])
        model.query = "⌘z"
        XCTAssertEqual(model.results.map(\.title), ["撤销"])
        model.query = "查找"
        XCTAssertTrue(model.results.isEmpty)
        // ⇥ 切到全部菜单项
        XCTAssertTrue(model.handleKey(try Self.key(48, "\t")))
        XCTAssertEqual(model.scope, .all)
        XCTAssertEqual(model.results.map(\.title), ["查找"])
    }

    @MainActor
    func testRunsTheChosenItemButNotDisabledOnes() throws {
        let model = MenuShortcutsModel(appName: "文本编辑")
        model.load(Self.menus)
        var ran: [String] = []
        model.onRun = { ran.append($0.title) }
        XCTAssertTrue(model.handleKey(try Self.key(125, "")))
        XCTAssertTrue(model.handleKey(try Self.key(36, "\r")))
        XCTAssertEqual(ran, ["PDF…"])
        // 「撤销」现在是灰的
        model.query = "撤销"
        XCTAssertTrue(model.handleKey(try Self.key(36, "\r")))
        XCTAssertEqual(ran, ["PDF…"])
    }

    @MainActor
    func testFallsBackToAllItemsOrExplainsWhatWentWrong() {
        let plain = MenuShortcutsModel(appName: "小工具")
        plain.load([MenuShortcuts.Node(title: "工具", shortcut: nil, enabled: true,
                                       children: [MenuShortcuts.Node(title: "刷新", shortcut: nil, enabled: true)])])
        XCTAssertEqual(plain.scope, .all)
        XCTAssertEqual(plain.results.map(\.title), ["刷新"])

        let empty = MenuShortcutsModel(appName: "小工具")
        empty.load([])
        XCTAssertEqual(empty.failure, "没读到「小工具」的菜单")
    }

    @MainActor
    func testPluginOpensTheList() async {
        let outcome = await MenuShortcutsPlugin().run(.empty, context: PluginContext(settings: AppSettings(), openSettings: {}))
        guard case .present = outcome else { return XCTFail("应该弹出快捷键一览") }
    }

    // MARK: - 示例菜单

    private static let menus: [MenuShortcuts.Node] = [
        MenuShortcuts.Node(title: "文件", shortcut: nil, enabled: true, children: [
            MenuShortcuts.Node(title: "新建窗口", shortcut: "⌘N", enabled: true),
            MenuShortcuts.Node(title: "", shortcut: nil, enabled: true),
            MenuShortcuts.Node(title: "导出为", shortcut: nil, enabled: true, children: [
                MenuShortcuts.Node(title: "PDF…", shortcut: "⌥⌘P", enabled: true),
            ]),
            MenuShortcuts.Node(title: "关闭", shortcut: "⌘W", enabled: true),
            // 重名的只留第一个
            MenuShortcuts.Node(title: "关闭", shortcut: "⌥⌘W", enabled: true),
        ]),
        MenuShortcuts.Node(title: "编辑", shortcut: nil, enabled: true, children: [
            MenuShortcuts.Node(title: "撤销", shortcut: "⌘Z", enabled: false),
            MenuShortcuts.Node(title: "查找", shortcut: nil, enabled: true),
        ]),
    ]

    private static func key(_ code: UInt16, _ characters: String) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                       context: nil, characters: characters, charactersIgnoringModifiers: characters,
                                       isARepeat: false, keyCode: code))
    }
}
