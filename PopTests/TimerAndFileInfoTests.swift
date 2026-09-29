import XCTest
@testable import Pop

final class DurationParserTests: XCTestCase {
    func testFormats() {
        XCTAssertEqual(DurationParser.parse("25 分钟"), 1500)
        XCTAssertEqual(DurationParser.parse("25min"), 1500)
        XCTAssertEqual(DurationParser.parse("1h30m"), 5400)
        XCTAssertEqual(DurationParser.parse("1小时30分"), 5400)
        XCTAssertEqual(DurationParser.parse("1.5 hours"), 5400)
        XCTAssertEqual(DurationParser.parse("90s"), 90)
        XCTAssertEqual(DurationParser.parse("1:30"), 90)
        XCTAssertEqual(DurationParser.parse("01:30:00"), 5400)
    }

    func testNotDurations() {
        XCTAssertNil(DurationParser.parse("hello"))
        XCTAssertNil(DurationParser.parse("5 km"))
        XCTAssertNil(DurationParser.parse("等 5 分钟再说"))
        XCTAssertNil(DurationParser.parse("1:3"))
        XCTAssertNil(DurationParser.parse("0 分钟"))
    }
}

@MainActor
final class CountdownTimerTests: XCTestCase {
    func testTitlesAndStatus() throws {
        XCTAssertEqual(CountdownTimer.title(seconds: 1500), "25 分钟")
        XCTAssertEqual(CountdownTimer.title(seconds: 90), "1 分 30 秒")
        XCTAssertEqual(CountdownTimer.title(seconds: 5400), "1 小时 30 分钟")
        XCTAssertEqual(CountdownTimer.clock(90), "1:30")
        XCTAssertEqual(CountdownTimer.clock(3700), "1:01:40")

        let countdown = CountdownTimer()
        XCTAssertNil(countdown.statusText())
        countdown.start(seconds: 600)
        XCTAssertTrue(countdown.isRunning)
        let status = try XCTUnwrap(countdown.statusText())
        XCTAssertTrue(status.hasPrefix("计时还剩 10:00"), status)
        countdown.cancel()
        XCTAssertFalse(countdown.isRunning)
    }

    func testPluginOffersPresetsOrStartsFromSelection() async {
        let context = PluginContext(settings: AppSettings(), openSettings: {})
        let outcome = await TimerPlugin().run(.empty, context: context)
        guard case .card(let card) = outcome else { return XCTFail("应该返回结果卡片") }
        XCTAssertEqual(card.buttons.first?.action, .startTimer(seconds: 60))
        XCTAssertEqual(card.buttons.map(\.title).prefix(3), ["1 分钟", "3 分钟", "5 分钟"])

        let started = await TimerPlugin().run(ContentClassifier.classify(.text("1:30")), context: context)
        XCTAssertEqual(started, .done(toast: "开始计时 1 分 30 秒"))
        XCTAssertTrue(CountdownTimer.shared.isRunning)
        CountdownTimer.shared.cancel()
    }
}

final class FileInfoTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "pop-info-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder.appending(path: "sub"), withIntermediateDirectories: true)
        try Data(repeating: 1, count: 1000).write(to: folder.appending(path: "a.bin"))
        try Data(repeating: 2, count: 234).write(to: folder.appending(path: "sub/b.bin"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    func testFolderSizeCountsNestedFiles() {
        XCTAssertEqual(FileInfo.folderSize(folder), FileInfo.FolderSize(bytes: 1234, files: 2, truncated: false))
        XCTAssertEqual(FileInfo.folderSize(folder, limit: 1).truncated, true)
    }

    func testFormatting() {
        XCTAssertTrue(FileInfo.describe(bytes: 1234).hasSuffix("（1,234 字节）"), FileInfo.describe(bytes: 1234))
        XCTAssertFalse(FileInfo.describe(bytes: 999).contains("字节"))
        XCTAssertEqual(FileInfo.duration(3725), "1:02:05")
        XCTAssertEqual(FileInfo.duration(65), "1:05")
    }

    func testRowsAndSummary() async {
        let rows = await FileInfo.rows(for: folder.appending(path: "a.bin"))
        XCTAssertTrue(rows.contains { $0.label == "大小" })
        XCTAssertTrue(rows.contains { $0.label == "修改时间" })
        let folderRows = await FileInfo.rows(for: folder)
        XCTAssertEqual(folderRows.first { $0.label == "文件数" }?.value, "2 个")
        let summary = FileInfo.summary(for: [folder, folder.appending(path: "a.bin")])
        XCTAssertEqual(summary.first?.value, "2 项")
        XCTAssertEqual(summary[1].value, "3 个")
    }
}

final class CodeImageTests: XCTestCase {
    func testNormalizing() {
        // 去掉共同缩进和首尾空行，Tab 换成 4 个空格
        XCTAssertEqual(CodeImage.normalized("\n    if x {\n        y()\n    }\n\n"), "if x {\n    y()\n}")
        XCTAssertEqual(CodeImage.normalized("\tlet a = 1"), "let a = 1")
        let long = String(repeating: "x", count: 300)
        XCTAssertEqual(CodeImage.normalized(long).count, CodeImage.maxColumns)
    }

    func testHighlighting() {
        let code = #"let url = "https://a.b" // note"#
        let tokens = CodeImage.tokens(in: code).map { ((code as NSString).substring(with: $0.range), $0.kind) }
        XCTAssertEqual(tokens.map { $0.0 }, ["let", #""https://a.b""#, "// note"])
        XCTAssertEqual(tokens.map { $0.1 }, [.keyword, .string, .comment])
        let python = CodeImage.tokens(in: "return None if x else 0x1F  # done").map(\.kind)
        XCTAssertEqual(python, [.keyword, .keyword, .keyword, .keyword, .number, .comment])
    }

    func testRendering() throws {
        let png = try XCTUnwrap(CodeImage.render("func hello() {\n    print(\"hi\")\n}"))
        let image = try XCTUnwrap(NSBitmapImageRep(data: png))
        // 至少 240 点宽的窗口，加上两边 48 点的背景，2 倍像素
        XCTAssertGreaterThanOrEqual(image.pixelsWide, (240 + 96) * 2)
        XCTAssertGreaterThan(image.pixelsHigh, 96 * 2)
        XCTAssertNil(CodeImage.render("   \n  "))
    }
}
