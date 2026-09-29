import XCTest
@testable import Pop

final class TableConverterTests: XCTestCase {
    func testParsingEachFormat() throws {
        let tsv = try XCTUnwrap(TableConverter.parse("名字\t城市\n小明\t上海\n小红\t北京"))
        XCTAssertEqual(tsv.source, .tsv)
        XCTAssertEqual(tsv.rows, [["名字", "城市"], ["小明", "上海"], ["小红", "北京"]])

        let csv = try XCTUnwrap(TableConverter.parse("name,note\nPop,\"a, b\"\nApp,\"say \"\"hi\"\"\""))
        XCTAssertEqual(csv.source, .csv)
        XCTAssertEqual(csv.rows[1], ["Pop", "a, b"])
        XCTAssertEqual(csv.rows[2], ["App", "say \"hi\""])

        let markdown = try XCTUnwrap(TableConverter.parse("| a | b |\n| --- | :-: |\n| 1 | x\\|y |"))
        XCTAssertEqual(markdown.source, .markdown)
        XCTAssertEqual(markdown.rows, [["a", "b"], ["1", "x|y"]])

        // 不是表格：一行、列数对不上、普通文字
        XCTAssertNil(TableConverter.parse("a,b,c"))
        XCTAssertNil(TableConverter.parse("a,b\nc"))
        XCTAssertNil(TableConverter.parse("今天天气很好\n我们出去走走"))
    }

    func testRendering() {
        let rows = [["name", "note"], ["Pop", "a, b"], ["x|y", "line"]]
        XCTAssertEqual(TableConverter.render(rows, as: .markdown),
                       "| name | note |\n| --- | --- |\n| Pop | a, b |\n| x\\|y | line |")
        XCTAssertEqual(TableConverter.render(rows, as: .csv), "name,note\nPop,\"a, b\"\nx|y,line")
        XCTAssertEqual(TableConverter.render(rows, as: .tsv), "name\tnote\nPop\ta, b\nx|y\tline")
        XCTAssertEqual(TableConverter.render([["k", "v"], ["a/b", "\"q\""]], as: .json),
                       "[\n  {\"k\": \"a/b\", \"v\": \"\\\"q\\\"\"}\n]")
        let table = TableConverter.Table(rows: rows, source: .csv)
        XCTAssertEqual(TableConverter.conversions(table).map(\.label), ["Markdown", "制表符分隔", "JSON"])
    }

    @MainActor
    func testPlugin() async {
        let content = ContentClassifier.classify(.text("a\tb\n1\t2"))
        XCTAssertTrue(TableConvertPlugin().info.canHandle(content))
        XCTAssertFalse(TableConvertPlugin().info.canHandle(ContentClassifier.classify(.text("hello world"))))
        let outcome = await TableConvertPlugin().run(content, context: PluginContext(settings: AppSettings(), openSettings: {}))
        guard case .card(let card) = outcome else { return XCTFail("应该返回结果卡片") }
        XCTAssertEqual(card.rows.first { $0.label == "CSV" }?.value, "a,b\n1,2")
        XCTAssertEqual(card.rowsReplaceable, true)
    }
}

final class ZipTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "pop-zip-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    func testAvailableNames() throws {
        XCTAssertEqual(FileNames.available(in: folder, base: "a", extension: "zip").lastPathComponent, "a.zip")
        try Data().write(to: folder.appending(path: "a.zip"))
        XCTAssertEqual(FileNames.available(in: folder, base: "a", extension: "zip").lastPathComponent, "a 2.zip")
        XCTAssertEqual(FileNames.available(in: folder, base: "dir").lastPathComponent, "dir")
    }

    @MainActor
    func testZipAndUnzipRoundTrip() async throws {
        let first = folder.appending(path: "one.txt")
        let second = folder.appending(path: "two.txt")
        try Data("hello".utf8).write(to: first)
        try Data("world".utf8).write(to: second)
        let context = PluginContext(settings: AppSettings(), openSettings: {})

        let zipped = await ZipPlugin(reveal: { _ in }).run(ContentClassifier.classify(.files([first, second])), context: context)
        XCTAssertEqual(zipped, .done(toast: "已压缩成 归档.zip"))
        let archive = folder.appending(path: "归档.zip")
        XCTAssertTrue(FileManager.default.fileExists(atPath: archive.path(percentEncoded: false)))

        let unzipped = await UnzipPlugin(reveal: { _ in }).run(ContentClassifier.classify(.files([archive])), context: context)
        XCTAssertEqual(unzipped, .done(toast: "已解压到「归档」"))
        let restored = folder.appending(path: "归档/one.txt")
        XCTAssertEqual(try String(contentsOf: restored, encoding: .utf8), "hello")

        XCTAssertTrue(UnzipPlugin().info.canHandle(ContentClassifier.classify(.files([archive]))))
        XCTAssertFalse(UnzipPlugin().info.canHandle(ContentClassifier.classify(.files([first]))))
    }
}
