import XCTest
@testable import Pop

@MainActor
final class VocabularyTests: XCTestCase {
    /// 每个测试一个临时文件，测完删掉
    private func makeURL() -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "pop-vocabulary-\(UUID().uuidString).json")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testAddsNewestFirstAndUpdatesDuplicates() {
        let url = makeURL()
        let store = VocabularyStore(url: url)
        XCTAssertTrue(store.add(word: "ephemeral", translation: "短暂的", sourceLanguage: "en", targetLanguage: "zh-Hans",
                                date: Date(timeIntervalSince1970: 1_000)))
        XCTAssertTrue(store.add(word: "resilient", translation: "有韧性的", sourceLanguage: "en", targetLanguage: "zh-Hans",
                                date: Date(timeIntervalSince1970: 2_000)))
        XCTAssertEqual(store.entries.map(\.word), ["resilient", "ephemeral"])
        // 同一个词（不分大小写）只存一次：换成新的释义，挪到最前面，加入时间不变
        XCTAssertFalse(store.add(word: " Ephemeral ", translation: "转瞬即逝的", sourceLanguage: "en", targetLanguage: "zh-Hans"))
        XCTAssertEqual(store.entries.map(\.word), ["Ephemeral", "resilient"])
        XCTAssertEqual(store.entries.first?.translation, "转瞬即逝的")
        XCTAssertEqual(store.entries.first?.added, Date(timeIntervalSince1970: 1_000))
        XCTAssertTrue(store.contains("EPHEMERAL"))
        XCTAssertFalse(store.add(word: "  ", translation: "空的", sourceLanguage: nil, targetLanguage: nil))

        // 存在文件里，重新打开还在
        let reopened = VocabularyStore(url: url)
        XCTAssertEqual(reopened.entries, store.entries)
        reopened.remove([reopened.entries[0].id])
        XCTAssertEqual(VocabularyStore(url: url).entries.map(\.word), ["resilient"])
    }

    func testReviewQueueAndMastery() {
        let store = VocabularyStore(url: makeURL())
        for (offset, word) in ["one", "two", "three"].enumerated() {
            store.add(word: word, translation: word.uppercased(), sourceLanguage: "en", targetLanguage: "zh-Hans",
                      date: Date(timeIntervalSince1970: Double(offset)))
        }
        // 先复习加得早的
        XCTAssertEqual(store.reviewQueue.map(\.word), ["one", "two", "three"])
        let model = VocabularyModel(store: store)
        model.startReview()
        XCTAssertEqual(model.reviewing?.word, "one")
        XCTAssertEqual(model.remaining, 3)
        model.answer(remembered: true)
        XCTAssertEqual(model.reviewing?.word, "two")
        XCTAssertFalse(model.revealed)
        // 还不熟的放到这一轮最后再来一次
        model.answer(remembered: false)
        XCTAssertEqual(model.reviewing?.word, "three")
        model.answer(remembered: true)
        XCTAssertEqual(model.reviewing?.word, "two")
        model.answer(remembered: true)
        XCTAssertNil(model.reviewing)
        XCTAssertTrue(store.entries.allSatisfy(\.mastered))
        XCTAssertEqual(store.entries.first { $0.word == "two" }?.misses, 1)
        XCTAssertTrue(store.reviewQueue.isEmpty)

        // 标回没记住的，点过「还不熟」的排在前面
        for entry in store.entries {
            store.setMastered(entry.id, false)
        }
        XCTAssertEqual(store.reviewQueue.map(\.word), ["two", "one", "three"])

        model.query = "TW"
        XCTAssertEqual(model.visible.map(\.word), ["two"])
    }

    func testExportFormats() {
        let entries = [
            VocabularyEntry(word: "hello, world", translation: "你好，\"世界\"", sourceLanguage: "en", targetLanguage: "zh-Hans",
                            added: Date(timeIntervalSince1970: 1_790_000_000)),
            VocabularyEntry(word: "tab\tword", translation: "第一行\n第二行", sourceLanguage: nil, targetLanguage: nil,
                            added: Date(timeIntervalSince1970: 1_790_000_000)),
        ]
        let csv = [
            "单词,释义,语言,加入日期,已记住",
            #""hello, world","你好，""世界""",en,2026-09-21,否"#,
            "tab\tword,\"第一行\n第二行\",,2026-09-21,否",
        ].joined(separator: "\n") + "\n"
        XCTAssertEqual(VocabularyStore.export(entries, as: .csv), csv)
        XCTAssertEqual(VocabularyStore.export(entries, as: .anki), "hello, world\t你好，\"世界\"\ntab word\t第一行<br>第二行\n")
    }

    func testWordLikeText() {
        XCTAssertTrue(VocabularyStore.isWordLike("serendipity"))
        XCTAssertTrue(VocabularyStore.isWordLike("take it for granted"))
        XCTAssertFalse(VocabularyStore.isWordLike("This is a whole sentence that is much too long to be a word"))
        XCTAssertFalse(VocabularyStore.isWordLike("two\nlines"))
        XCTAssertFalse(VocabularyStore.isWordLike("   "))
    }

    func testDictionaryBrief() {
        XCTAssertEqual(DictionaryPlugin.brief("serendipity | ˌserənˈdipədē |\nnoun the occurrence of events by chance", word: "serendipity"),
                       "ˌserənˈdipədē | noun the occurrence of events by chance")
        XCTAssertEqual(DictionaryPlugin.brief(String(repeating: "长", count: 200), word: "x").count, 121)
    }

    func testPluginOpensTheList() async {
        let outcome = await VocabularyPlugin().run(.empty, context: PluginContext(settings: AppSettings(), openSettings: {}))
        XCTAssertEqual(outcome, .showVocabulary)
    }
}
