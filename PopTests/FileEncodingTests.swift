import XCTest
@testable import Pop

final class FileEncodingTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "pop-encoding-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    /// 一段 Windows 上常见的中文：GBK 存的时候是这样
    private let chinese = "这是一个用记事本保存的中文文件，里面有常用的汉字、标点符号和数字 2026 年 9 月 30 日。\r\n第二行：订单已经发货，请注意查收。\r\n"

    func testDetectsBOMsUTF8AndChineseEncodings() throws {
        XCTAssertEqual(TextEncodingTools.detect(Data("plain ascii\n".utf8)), .utf8)
        XCTAssertEqual(TextEncodingTools.detect(Data("中文 UTF-8".utf8)), .utf8)
        XCTAssertEqual(TextEncodingTools.detect(Data([0xEF, 0xBB, 0xBF]) + Data("带 BOM".utf8)), .utf8BOM)
        let utf16 = try XCTUnwrap(TextEncodingTools.encode("你好", as: .utf16LE))
        XCTAssertEqual(Array(utf16.prefix(2)), [0xFF, 0xFE])
        XCTAssertEqual(TextEncodingTools.detect(utf16), .utf16LE)
        let gbk = try XCTUnwrap(TextEncodingTools.encode(chinese, as: .gb18030))
        XCTAssertNil(String(data: gbk, encoding: .utf8))
        XCTAssertEqual(TextEncodingTools.detect(gbk), .gb18030)
        XCTAssertEqual(TextEncodingTools.decode(gbk, as: .gb18030), chinese)
        // 读的时候去掉 BOM
        XCTAssertEqual(TextEncodingTools.decode(Data([0xEF, 0xBB, 0xBF]) + Data("abc".utf8), as: .utf8), "abc")
        XCTAssertEqual(TextEncodingTools.decode(utf16, as: .utf16LE), "你好")
    }

    func testLineEndings() {
        XCTAssertEqual(TextEncodingTools.lineEnding(of: "a\nb\n"), .lf)
        XCTAssertEqual(TextEncodingTools.lineEnding(of: "a\r\nb\r\n"), .crlf)
        XCTAssertEqual(TextEncodingTools.lineEnding(of: "a\rb"), .cr)
        XCTAssertEqual(TextEncodingTools.lineEnding(of: "a\r\nb\nc"), .mixed)
        XCTAssertEqual(TextEncodingTools.lineEnding(of: "一行"), .none)
        XCTAssertEqual(TextEncodingTools.normalize("a\r\nb\rc\n", to: .lf), "a\nb\nc\n")
        XCTAssertEqual(TextEncodingTools.normalize("a\nb\r\n", to: .crlf), "a\r\nb\r\n")
        XCTAssertEqual(TextEncodingTools.normalize("a\r\nb", to: .keep), "a\r\nb")
        XCTAssertEqual(TextEncodingTools.firstLine("\n\n  第一行  \n第二行"), "第一行")
    }

    func testConvertsGBKWithCRLFToUTF8WithBOMAndLF() throws {
        let gbk = try XCTUnwrap(TextEncodingTools.encode(chinese, as: .gb18030))
        let converted = try TextEncodingTools.convert(gbk, from: .gb18030, to: .utf8BOM, lines: .lf)
        XCTAssertEqual(Array(converted.prefix(3)), [0xEF, 0xBB, 0xBF])
        XCTAssertEqual(String(data: converted.dropFirst(3), encoding: .utf8), chinese.replacingOccurrences(of: "\r\n", with: "\n"))
        // 再转回 GBK 和原来一样
        XCTAssertEqual(try TextEncodingTools.convert(converted, from: .utf8BOM, to: .gb18030, lines: .crlf), gbk)
        XCTAssertThrowsError(try TextEncodingTools.convert(Data([0xFF, 0xFF, 0xFF]), from: .utf8, to: .gb18030, lines: .keep))
        XCTAssertEqual(TextEncodingTools.Encoding.targets, [.utf8, .utf8BOM, .gb18030])
    }

    func testTextFilesByExtension() {
        XCTAssertTrue(TextEncodingTools.isTextFile("/tmp/订单.csv"))
        XCTAssertTrue(TextEncodingTools.isTextFile("/tmp/字幕.srt"))
        XCTAssertTrue(TextEncodingTools.isTextFile("/tmp/main.swift"))
        XCTAssertTrue(TextEncodingTools.isTextFile("/tmp/notes.TXT"))
        XCTAssertFalse(TextEncodingTools.isTextFile("/tmp/photo.jpg"))
        XCTAssertFalse(TextEncodingTools.isTextFile("/tmp/没有扩展名"))
        let plugin = FileEncodingPlugin().info
        XCTAssertTrue(plugin.canHandle(ContentClassifier.classify(.files([URL(fileURLWithPath: "/tmp/订单.csv")]))))
        XCTAssertFalse(plugin.canHandle(ContentClassifier.classify(.files([URL(fileURLWithPath: "/tmp/photo.jpg")]))))
        XCTAssertFalse(plugin.canHandle(.empty))
    }

    @MainActor
    func testCardConvertsChangedFilesAndUndoes() async throws {
        let keys = [FileEncodingModel.targetKey, FileEncodingModel.linesKey]
        let saved = keys.map { UserDefaults.standard.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, saved) {
                UserDefaults.standard.set(value, forKey: key)
            }
        }
        let gbkFile = folder.appending(path: "订单.csv")
        let gbk = try XCTUnwrap(TextEncodingTools.encode(chinese, as: .gb18030))
        try gbk.write(to: gbkFile)
        let utf8File = folder.appending(path: "说明.md")
        try Data("# 已经是 UTF-8\n".utf8).write(to: utf8File)
        let rows = [gbkFile, utf8File].map(FileEncodingModel.inspect)
        XCTAssertEqual(rows.map(\.source), [.gb18030, .utf8])
        XCTAssertEqual(rows.map(\.lineEnding), [.crlf, .lf])
        XCTAssertEqual(rows[0].text.map { TextEncodingTools.firstLine($0, limit: 8) }, "这是一个用记事本…")
        let model = FileEncodingModel(rows: rows, target: .utf8, lines: .keep)
        // UTF-8 的那个不用转
        XCTAssertEqual(model.pending, [gbkFile])
        XCTAssertEqual(model.summary, "会把 1 个文件转成 UTF-8，原来的内容记着，转完可以撤销")
        model.target = .utf8BOM
        XCTAssertEqual(model.pending, [gbkFile, utf8File])
        XCTAssertTrue(model.summary.hasPrefix("带 BOM 的 UTF-8 用 Excel 打开 CSV 不会乱码；"))
        model.target = .utf8
        model.lines = .lf

        model.convert()
        for _ in 0..<200 where model.phase == .working {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(model.phase, .done(converted: [gbkFile], unchanged: 1, failed: []))
        XCTAssertEqual(try String(contentsOf: gbkFile, encoding: .utf8), chinese.replacingOccurrences(of: "\r\n", with: "\n"))

        model.undo()
        for _ in 0..<200 where model.phase == .working {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(model.phase, .choosing)
        XCTAssertEqual(try Data(contentsOf: gbkFile), gbk)
    }

    @MainActor
    func testReadingWithAnotherEncoding() throws {
        let gbk = try XCTUnwrap(TextEncodingTools.encode(chinese, as: .gb18030))
        let row = FileEncodingModel.Row(url: folder.appending(path: "a.txt"), original: gbk, source: .gb18030)
        let model = FileEncodingModel(rows: [row], target: .utf8, lines: .keep)
        XCTAssertEqual(model.pending.count, 1)
        // 按 UTF-8 读不出来：这一行不转
        model.setSource(.utf8, for: row)
        XCTAssertEqual(model.rows[0].problem, "按 UTF-8 读不出来")
        XCTAssertEqual(model.pending, [])
        XCTAssertEqual(model.summary, "选中的文件已经是这种编码和换行了")
        model.setSource(.gb18030, for: row)
        XCTAssertNil(model.rows[0].problem)
        XCTAssertEqual(model.pending.count, 1)
        // 认不出编码的文件
        XCTAssertEqual(FileEncodingModel.Row(url: folder.appending(path: "b.txt"), original: Data(), source: nil).problem, "认不出是什么编码")
    }

    func testDemoRows() {
        let rows = FileEncodingPlugin.demoRows()
        XCTAssertEqual(rows.map(\.source), [.gb18030, .gb18030, .utf8])
        XCTAssertEqual(rows.map(\.lineEnding), [.crlf, .crlf, .lf])
        XCTAssertTrue(rows.allSatisfy { $0.problem == nil })
    }
}
