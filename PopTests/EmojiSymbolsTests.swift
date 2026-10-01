import AppKit
import XCTest
@testable import Pop

@MainActor
final class EmojiSymbolsTests: XCTestCase {
    private func freshDefaults() -> UserDefaults {
        let suite = "PopEmojiSymbolsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func key(_ code: UInt16, _ characters: String = "", modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0, context: nil,
                         characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!
    }

    // MARK: - 数据

    func testTableParses() throws {
        let emoji = EmojiSymbols.items.filter(\.isEmoji)
        XCTAssertEqual(emoji.count, EmojiSymbols.showsEmoji16 ? 1906 : 1898)
        XCTAssertEqual(EmojiSymbols.items.count - emoji.count, 398)
        for category in EmojiSymbols.Category.allCases {
            XCTAssertFalse(EmojiSymbols.items(in: category).isEmpty, category.rawValue)
            XCTAssertFalse(category.title.isEmpty)
        }
        XCTAssertTrue(EmojiSymbols.items.allSatisfy { !$0.chineseName.isEmpty && !$0.englishName.isEmpty })
        XCTAssertTrue(EmojiSymbols.items.allSatisfy { $0.tones.isEmpty || $0.tones.count == 5 })
        // 肤色、发型这些零件不列出来
        XCTAssertNil(EmojiSymbols.item("🏻"))

        let grin = try XCTUnwrap(EmojiSymbols.item("😄"))
        XCTAssertEqual(grin.chineseName, "大笑")
        XCTAssertEqual(grin.englishName, "grinning face with smiling eyes")
        XCTAssertEqual(grin.category, .smileys)
        XCTAssertEqual(grin.name, "大笑")
        XCTAssertEqual(grin.codePoints, "U+1F604")
        XCTAssertEqual(try XCTUnwrap(EmojiSymbols.item("✓")).category, .shapes)
        XCTAssertEqual(try XCTUnwrap(EmojiSymbols.item("①")).englishName, "circled number 1")
    }

    func testSkinTones() throws {
        let wave = try XCTUnwrap(EmojiSymbols.item("👋"))
        XCTAssertEqual(wave.text(tone: 0), "👋")
        XCTAssertEqual(wave.text(tone: 1), "👋🏻")
        XCTAssertEqual(wave.text(tone: 3), "👋🏽")
        XCTAssertEqual(wave.text(tone: 5), "👋🏿")
        // 没有肤色的照原样
        XCTAssertEqual(try XCTUnwrap(EmojiSymbols.item("😄")).text(tone: 3), "😄")
    }

    // MARK: - 搜索

    func testSearch() {
        func first(_ query: String) -> String? { EmojiSymbols.search(query).first?.id }
        XCTAssertEqual(first("大笑"), "😄")
        XCTAssertEqual(EmojiSymbols.search("猫").first?.chineseName, "猫")
        XCTAssertTrue(EmojiSymbols.search("猫").prefix(2).contains { $0.id == "🐱" })
        XCTAssertEqual(first("smile"), "😀")
        XCTAssertEqual(first("对勾"), "✓")
        XCTAssertTrue(EmojiSymbols.search("check").contains { $0.id == "✓" })
        XCTAssertEqual(first("人民币"), "¥")
        XCTAssertEqual(first("平方米"), "㎡")
        XCTAssertEqual(first("阿尔法"), "α")
        // 拼音、首字母
        XCTAssertEqual(first("daxiao"), "😄")
        XCTAssertTrue(EmojiSymbols.search("dx").contains { $0.id == "😄" })
        // 粘进来的表情：带不带变体选择符都认
        XCTAssertEqual(first("🐱"), "🐱")
        XCTAssertEqual(EmojiSymbols.search("🐈").first.map { EmojiSymbols.withoutVariationSelectors($0.id) }, "🐈")
        XCTAssertTrue(EmojiSymbols.search("xyzzy").isEmpty)
        XCTAssertTrue(EmojiSymbols.search("  ").isEmpty)
        // 同一个只出现一次
        let arrows = EmojiSymbols.search("箭头").map(\.id)
        XCTAssertEqual(arrows.count, Set(arrows).count)
    }

    // MARK: - 最近用过的

    func testRecents() {
        let recents = EmojiRecents(defaults: freshDefaults())
        XCTAssertEqual(recents.ids, [])
        recents.record("😄")
        recents.record("✓")
        recents.record("😄")
        XCTAssertEqual(recents.ids, ["😄", "✓"])
        for item in EmojiSymbols.items(in: .greek) {
            recents.record(item.id)
        }
        XCTAssertEqual(recents.ids.count, EmojiRecents.limit)
        XCTAssertEqual(recents.ids.first, "Ω")
    }

    // MARK: - 卡片

    func testCardBrowsingAndKeyboard() throws {
        let defaults = freshDefaults()
        var inserted: [String] = []
        var copied: [String] = []
        let model = EmojiSymbolsModel(defaults: defaults)
        model.onInsert = { inserted.append($0) }
        model.onCopy = { copied.append($0) }
        // 没用过时先看表情
        XCTAssertEqual(model.section, .emoji)
        XCTAssertEqual(model.visibleItems, EmojiSymbols.items(in: .smileys))
        XCTAssertEqual(model.focused?.id, "😀")

        // ↓ 往下一行，→ 往右一个，回车插入
        XCTAssertTrue(model.handleKey(key(125)))
        XCTAssertEqual(model.selection, EmojiSymbolsModel.columns)
        XCTAssertTrue(model.handleKey(key(124)))
        XCTAssertEqual(model.selection, EmojiSymbolsModel.columns + 1)
        XCTAssertTrue(model.handleKey(key(126)))
        XCTAssertTrue(model.handleKey(key(123)))
        XCTAssertEqual(model.selection, 0)
        XCTAssertTrue(model.handleKey(key(123)))
        XCTAssertEqual(model.selection, 0)
        XCTAssertTrue(model.handleKey(key(36, "\r")))
        XCTAssertEqual(inserted, ["😀"])

        // 换到符号
        model.section = .symbols
        model.symbolCategory = .arrows
        XCTAssertEqual(model.visibleItems.first?.id, "←")
        XCTAssertTrue(model.handleKey(key(8, "c", modifiers: .command)))
        XCTAssertEqual(copied, ["←"])

        // 搜索：左右键留给输入框
        model.query = "笑"
        XCTAssertTrue(model.isSearching)
        XCTAssertEqual(model.visibleItems, EmojiSymbols.search("笑"))
        XCTAssertFalse(model.handleKey(key(124)))
        XCTAssertTrue(model.handleKey(key(125)))
        model.query = "xyzzy"
        XCTAssertTrue(model.visibleItems.isEmpty)
        XCTAssertNil(model.focused)
        XCTAssertEqual(model.emptyText, "没有找到，换个说法试试：中文、拼音或者英文")
        XCTAssertTrue(model.handleKey(key(36, "\r")))
        XCTAssertEqual(inserted, ["😀"])

        // 再打开：先看最近用过的，最近的在前
        let reopened = EmojiSymbolsModel(defaults: defaults)
        XCTAssertEqual(reopened.section, .recent)
        XCTAssertEqual(reopened.visibleItems.map(\.id), ["←", "😀"])
    }

    func testSkinTonePreference() throws {
        let defaults = freshDefaults()
        var inserted: [String] = []
        let model = EmojiSymbolsModel(defaults: defaults)
        model.onInsert = { inserted.append($0) }
        model.tone = 2
        model.insert(try XCTUnwrap(EmojiSymbols.item("👋")))
        XCTAssertEqual(inserted, ["👋🏼"])
        XCTAssertEqual(EmojiSymbolsModel(defaults: defaults).tone, 2)
        defaults.set(9, forKey: EmojiSymbolsModel.toneKey)
        XCTAssertEqual(EmojiSymbolsModel(defaults: defaults).tone, 5)
    }

    func testSelectedTextBecomesTheSearch() {
        XCTAssertEqual(EmojiSymbolsPlugin.query(from: " 猫 "), "猫")
        XCTAssertEqual(EmojiSymbolsPlugin.query(from: nil), "")
        XCTAssertEqual(EmojiSymbolsPlugin.query(from: "第一行\n第二行"), "")
        XCTAssertEqual(EmojiSymbolsPlugin.query(from: String(repeating: "长", count: 21)), "")
        let demo = EmojiSymbolsPlugin.demoModel()
        XCTAssertTrue(demo.isSearching)
        XCTAssertFalse(demo.visibleItems.isEmpty)
    }
}
