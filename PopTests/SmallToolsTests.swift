import XCTest
@testable import Pop

final class SmallToolsTests: XCTestCase {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }

    func testColorScaleGoesFromLightToDark() throws {
        let red = try XCTUnwrap(ColorValue.parse("#FF0000"))
        XCTAssertEqual(red.scale().map(\.hexString),
                       ["#FFCCCC", "#FF9999", "#FF6666", "#FF3333", "#FF0000", "#CC0000", "#990000", "#660000", "#330000"])
    }

    @MainActor
    func testColorCardShowsTheScale() async {
        let outcome = await ColorConvertPlugin().run(ContentClassifier.classify(.text("#FF8800")),
                                                     context: PluginContext(settings: AppSettings(), openSettings: {}))
        guard case .card(let card) = outcome else { return XCTFail("应该返回结果卡片") }
        XCTAssertEqual(card.palette.count, 9)
        XCTAssertEqual(card.palette[4], "#FF8800")
    }

    func testDateSpan() throws {
        let result = try XCTUnwrap(DateSpan.find(in: "2026-09-29 到 2026-12-25", calendar: utc))
        XCTAssertEqual(result.days, 87)
        XCTAssertEqual(result.workdays, 63)
        XCTAssertEqual(DateSpan.rows(for: result, calendar: utc).map(\.value),
                       ["87 天", "12 周 3 天", "2 个月 26 天", "88 天", "63 天（周一到周五，不算节假日）"])
        // 先写后面的日期也行，中文写法、两行各一个也行
        XCTAssertEqual(DateSpan.find(in: "2026年12月25日 - 2026年9月29日", calendar: utc)?.days, 87)
        let long = try XCTUnwrap(DateSpan.find(in: "2026-01-01\n2027/3/15", calendar: utc))
        XCTAssertEqual(long.days, 438)
        XCTAssertEqual(long.workdays, 312)
        XCTAssertEqual(DateSpan.rows(for: long, calendar: utc).map(\.value)[1...2], ["62 周 4 天", "1 年 2 个月 14 天"])
        // 不存在的日子、只有一个或者三个日期
        XCTAssertNil(DateSpan.find(in: "2026-02-30 到 2026-03-01", calendar: utc))
        XCTAssertNil(DateSpan.find(in: "2026-09-29", calendar: utc))
        XCTAssertNil(DateSpan.find(in: "2026-01-01 2026-02-01 2026-03-01", calendar: utc))
    }

    func testFolderTree() throws {
        let base = FileManager.default.temporaryDirectory.appending(path: "pop-tree-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: base) }
        let root = base.appending(path: "root")
        let manager = FileManager.default
        for folder in ["B/D/F", "node_modules"] {
            try manager.createDirectory(at: root.appending(path: folder), withIntermediateDirectories: true)
        }
        for file in ["a.txt", "B/c.txt", "B/D/e.txt", "B/D/F/g.txt", "node_modules/x.js", ".hidden"] {
            try Data("x".utf8).write(to: root.appending(path: file))
        }
        XCTAssertTrue(FolderTree.isFolder(root.path(percentEncoded: false)))
        XCTAssertFalse(FolderTree.isFolder(root.appending(path: "a.txt").path(percentEncoded: false)))

        let result = FolderTree.build(root)
        XCTAssertEqual(result.tree, """
        root/
        ├── B/
        │   ├── D/
        │   │   ├── F/ …
        │   │   └── e.txt
        │   └── c.txt
        ├── node_modules/ …
        └── a.txt
        """)
        XCTAssertEqual(result.markdown, """
        - root/
          - B/
            - D/
              - F/ …
              - e.txt
            - c.txt
          - node_modules/ …
          - a.txt
        """)
        XCTAssertEqual(result.folders, 4)
        XCTAssertEqual(result.files, 3)
        XCTAssertFalse(result.truncated)
        XCTAssertTrue(FolderTree.build(root, maxEntries: 2).truncated)
    }

    func testMarkdownTableOfContents() {
        let markdown = """
        # Pop 使用说明
        ## 安装
        ```bash
        # 不是标题
        ```
        ## 功能
        ### 翻译 & 词典
        ## 功能 ##
        #### [链接](https://example.com) 和 `代码`
        #没有空格不算
        """
        let headings = MarkdownTOC.headings(in: markdown)
        XCTAssertEqual(headings.map(\.anchor), ["pop-使用说明", "安装", "功能", "翻译--词典", "功能-1", "链接-和-代码"])
        XCTAssertEqual(MarkdownTOC.toc(for: headings), """
        - [Pop 使用说明](#pop-使用说明)
          - [安装](#安装)
          - [功能](#功能)
            - [翻译 & 词典](#翻译--词典)
          - [功能](#功能-1)
              - [链接 和 代码](#链接-和-代码)
        """)
    }

    func testRecognizedTextCanBeJoined() {
        let card = TextRecognizer.card(title: "识别文字", text: "Pop reads the selec-\ntion and shows\na card.")
        XCTAssertEqual(card.buttons.map(\.title), ["翻译", "合并换行后复制"])
        XCTAssertEqual(card.buttons.last?.action, .copy("Pop reads the selection and shows a card."))
        XCTAssertEqual(TextRecognizer.card(title: "识别文字", text: "一行").buttons.map(\.title), ["翻译"])
    }

    @MainActor
    func testPluginsAppearOnlyForTheirContent() async {
        let context = PluginContext(settings: AppSettings(), openSettings: {})
        let dates = ContentClassifier.classify(.text("2026-09-29 到 2026-12-25"))
        XCTAssertTrue(DateSpanPlugin().info.canHandle(dates))
        XCTAssertFalse(DateSpanPlugin().info.canHandle(ContentClassifier.classify(.text("2026-09-29"))))
        guard case .card(let card) = await DateSpanPlugin().run(dates, context: context) else { return XCTFail("应该返回结果卡片") }
        XCTAssertEqual(card.rows.first?.value, "87 天")

        let markdown = ContentClassifier.classify(.text("# 标题\n正文\n## 小标题"))
        XCTAssertTrue(MarkdownTOCPlugin().info.canHandle(markdown))
        XCTAssertFalse(MarkdownTOCPlugin().info.canHandle(ContentClassifier.classify(.text("# 只有一个标题"))))
        guard case .card(let toc) = await MarkdownTOCPlugin().run(markdown, context: context) else { return XCTFail("应该返回结果卡片") }
        XCTAssertEqual(toc.copyText, "- [标题](#标题)\n  - [小标题](#小标题)")
    }
}
