import XCTest
@testable import Pop

final class FileDiffTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "FileDiffTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func write(_ name: String, _ data: Data, modified: Date? = nil) throws -> URL {
        let url = folder.appending(path: name)
        try data.write(to: url)
        if let modified {
            try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path(percentEncoded: false))
        }
        return url
    }

    func testRecognizesTextFiles() throws {
        XCTAssertTrue(FileDiff.isTextFile(try write("a.swift", Data("let a = 1\n".utf8))))
        XCTAssertTrue(FileDiff.isTextFile(try write("notes.md", Data("# 标题\n".utf8))))
        XCTAssertTrue(FileDiff.isTextFile(try write("data.json", Data("{}".utf8))))
        XCTAssertTrue(FileDiff.isTextFile(try write("Makefile", Data("all:\n\techo hi\n".utf8))))
        XCTAssertTrue(FileDiff.isTextFile(try write("app.popconfig", Data("name = \"pop\"\n".utf8))))
        XCTAssertFalse(FileDiff.isTextFile(try write("image.png", Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]))))
        XCTAssertFalse(FileDiff.isTextFile(try write("blob", Data([0x00, 0x01, 0x02, 0x03]))))
        XCTAssertFalse(FileDiff.isTextFile(folder))
        XCTAssertFalse(FileDiff.isTextFile(folder.appending(path: "missing.txt")))
    }

    func testDecodesCommonEncodings() throws {
        XCTAssertEqual(FileDiff.decode(Data("你好".utf8)), "你好")
        XCTAssertEqual(FileDiff.decode(Data([0xEF, 0xBB, 0xBF]) + Data("hi".utf8)), "hi")
        let gb18030 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        XCTAssertEqual(FileDiff.decode(try XCTUnwrap("你好，世界".data(using: gb18030))), "你好，世界")
        XCTAssertEqual(FileDiff.decode(try XCTUnwrap("hi".data(using: .utf16))), "hi")
        XCTAssertNil(FileDiff.decode(Data([0x41, 0x00, 0x42])))
        XCTAssertEqual(FileDiff.decode(Data()), "")
    }

    func testRejectsFilesThatAreTooLong() throws {
        let long = try write("long.txt", Data(String(repeating: "a", count: FileDiff.maxCharacters + 1).utf8))
        XCTAssertThrowsError(try FileDiff.read(long)) { error in
            XCTAssertEqual((error as? FileDiff.Failure)?.message, "「long.txt」太大了，只能对比 30 万字以内的文本文件")
        }
    }

    func testOlderFileComesFirst() throws {
        let now = Date()
        let newer = try write("new.txt", Data("b".utf8), modified: now)
        let older = try write("old.txt", Data("a".utf8), modified: now.addingTimeInterval(-3600))
        XCTAssertEqual(FileDiff.ordered(newer, older).old, older)
        XCTAssertEqual(FileDiff.ordered(older, newer).old, older)
    }

    @MainActor
    func testPluginComparesTwoTextFiles() async throws {
        let now = Date()
        let newer = try write("new.txt", Data("第一行\n第二行改了\n第三行\n".utf8), modified: now)
        let older = try write("old.txt", Data("第一行\n第二行\n第三行\n".utf8), modified: now.addingTimeInterval(-3600))
        let plugin = FileComparePlugin()
        let content = ContentClassifier.classify(.files([newer, older]))
        XCTAssertTrue(plugin.info.canHandle(content))
        XCTAssertFalse(plugin.info.canHandle(ContentClassifier.classify(.files([newer]))))
        XCTAssertFalse(plugin.info.canHandle(ContentClassifier.classify(.files([newer, folder]))))
        let image = try write("image.png", Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]))
        XCTAssertFalse(plugin.info.canHandle(ContentClassifier.classify(.files([newer, image]))))

        let context = PluginContext(settings: AppSettings(), openSettings: {})
        guard case .card(let card) = await plugin.run(content, context: context) else { return XCTFail("应该返回结果卡片") }
        XCTAssertEqual(card.title, "对比文件")
        XCTAssertEqual(card.detail, "「old.txt」→「new.txt」（旧的在前）：删去 1 行，新增 1 行")
        XCTAssertEqual(card.diff?.removedCount, 1)
        XCTAssertEqual(card.diff?.addedCount, 1)
        XCTAssertEqual(card.copyText?.contains("- 第二行"), true)

        let same = try write("same.txt", Data("第一行\n第二行\n第三行\n".utf8))
        guard case .done(let toast) = await plugin.run(ContentClassifier.classify(.files([older, same])), context: context) else {
            return XCTFail("内容相同时只提示一句")
        }
        XCTAssertEqual(toast, "两个文件内容相同")
    }
}
