import AppKit
import XCTest
@testable import Pop

final class NewFileTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "pop-newfile-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    func testFileNamesGetAnExtensionAndLoseBadCharacters() {
        XCTAssertEqual(NewFileMaker.fileName("笔记", ext: "md"), "笔记.md")
        XCTAssertEqual(NewFileMaker.fileName("  报告.txt  ", ext: "md"), "报告.txt")
        XCTAssertEqual(NewFileMaker.fileName("a/b:c", ext: "txt"), "a-b-c.txt")
        XCTAssertEqual(NewFileMaker.fileName("", ext: "json"), "未命名.json")
        XCTAssertEqual(NewFileMaker.fileName(".env", ext: "txt"), "env.txt")
        XCTAssertEqual(NewFileMaker.Kind.of(extension: "MD"), .markdown)
        XCTAssertEqual(NewFileMaker.Kind.of(extension: "htm"), .html)
        XCTAssertNil(NewFileMaker.Kind.of(extension: "docx"))
    }

    func testBlankFilesHaveUsefulStarts() throws {
        XCTAssertEqual(String(decoding: NewFileMaker.data(kind: .markdown, content: .blank, title: "周报"), as: UTF8.self), "# 周报\n\n")
        XCTAssertEqual(String(decoding: NewFileMaker.data(kind: .json, content: .blank, title: "x"), as: UTF8.self), "{}\n")
        XCTAssertEqual(String(decoding: NewFileMaker.data(kind: .shell, content: .blank, title: "x"), as: UTF8.self), "#!/bin/bash\n\n")
        XCTAssertTrue(NewFileMaker.data(kind: .text, content: .blank, title: "x").isEmpty)
        let html = String(decoding: NewFileMaker.data(kind: .html, content: .blank, title: "A & B"), as: UTF8.self)
        XCTAssertTrue(html.hasPrefix("<!doctype html>\n<html>"))
        XCTAssertTrue(html.contains("<title>A &amp; B</title>"))
        // 富文本是一个 RTF 文稿，读得回来
        let rtf = NewFileMaker.data(kind: .rtf, content: .text("你好，Pop"), title: "x")
        XCTAssertTrue(String(decoding: rtf.prefix(5), as: UTF8.self) == "{\\rtf")
        let read = try NSAttributedString(data: rtf, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
        XCTAssertEqual(read.string.trimmingCharacters(in: .newlines), "你好，Pop")
        // 文字原样存进去
        XCTAssertEqual(String(decoding: NewFileMaker.data(kind: .csv, content: .text("a,b\n1,2"), title: "x"), as: UTF8.self), "a,b\n1,2")
    }

    func testCreateAddsANumberWhenTheNameIsTaken() throws {
        let first = try NewFileMaker.create(in: folder, name: "笔记.md", data: Data("1".utf8))
        let second = try NewFileMaker.create(in: folder, name: "笔记.md", data: Data("2".utf8))
        XCTAssertEqual(first.lastPathComponent, "笔记.md")
        XCTAssertEqual(second.lastPathComponent, "笔记 2.md")
        XCTAssertEqual(try String(contentsOf: first, encoding: .utf8), "1")
        let script = try NewFileMaker.create(in: folder, name: "run.sh", data: Data("#!/bin/bash\n".utf8), executable: true)
        let permissions = try FileManager.default.attributesOfItem(atPath: script.path(percentEncoded: false))[.posixPermissions] as? Int
        XCTAssertEqual(permissions, 0o755)
        XCTAssertThrowsError(try NewFileMaker.create(in: folder.appending(path: "没有这个文件夹", directoryHint: .isDirectory), name: "a.txt", data: Data()))
    }

    @MainActor
    func testCardKeepsKindAndExtensionInStep() throws {
        let key = NewFileModel.kindKey
        let saved = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(saved, forKey: key) }
        UserDefaults.standard.removeObject(forKey: key)

        let model = NewFileModel(folder: folder, selection: nil, clipboardText: "剪贴板", clipboardImage: nil)
        XCTAssertEqual(model.kind, .text)
        XCTAssertEqual(model.name, "未命名.txt")
        XCTAssertEqual(model.source, .blank)
        XCTAssertEqual(model.sources, [.blank, .clipboardText])
        // 换种类，名字的扩展名跟着换
        model.kind = .markdown
        XCTAssertEqual(model.name, "未命名.md")
        // 名字里写上认识的扩展名，种类跟着换
        model.name = "页面.html"
        XCTAssertEqual(model.kind, .html)
        model.name = "说明"
        XCTAssertEqual(model.fileName, "说明.html")

        let url = try XCTUnwrap(model.create())
        XCTAssertEqual(url.lastPathComponent, "说明.html")
        XCTAssertTrue(try String(contentsOf: url, encoding: .utf8).contains("<title>说明</title>"))
        // 记住上次的种类
        XCTAssertEqual(NewFileModel(folder: folder, selection: nil, clipboardText: nil, clipboardImage: nil).kind, .html)
    }

    @MainActor
    func testCardSavesSelectionOrClipboardImage() throws {
        let png = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4,
                                                 hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)?
            .representation(using: .png, properties: [:]))
        let model = NewFileModel(folder: folder, selection: "## 计划\n- 写测试", clipboardText: nil, clipboardImage: png, kind: .markdown)
        // 选中了文字时默认存选中的文字
        XCTAssertEqual(model.source, .selection)
        XCTAssertEqual(model.sources, [.blank, .selection, .clipboardImage])
        XCTAssertEqual(model.previewText, "## 计划\n- 写测试")
        let notes = try XCTUnwrap(model.create())
        XCTAssertEqual(try String(contentsOf: notes, encoding: .utf8), "## 计划\n- 写测试")
        // 剪贴板里的图片存成 PNG
        model.source = .clipboardImage
        XCTAssertEqual(model.name, "未命名.png")
        XCTAssertNil(model.previewText)
        let image = try XCTUnwrap(model.create())
        XCTAssertEqual(image.pathExtension, "png")
        XCTAssertEqual(try Data(contentsOf: image), png)
        // 换回文字时扩展名回到 Markdown
        model.source = .blank
        XCTAssertEqual(model.name, "未命名.md")
        // 只有空白的选中文字不算
        XCTAssertEqual(NewFileModel(folder: folder, selection: "  \n", clipboardText: "", clipboardImage: nil).sources, [.blank])
    }

    @MainActor
    func testFolderComesFromTheSelection() throws {
        let file = folder.appending(path: "a.txt")
        try Data().write(to: file)
        XCTAssertEqual(NewFilePlugin.folder(for: [folder], sourcePID: nil), folder)
        XCTAssertEqual(NewFilePlugin.folder(for: [file], sourcePID: nil).standardizedFileURL, folder.standardizedFileURL)
        // 什么都没选、不在访达里时是桌面
        XCTAssertEqual(NewFilePlugin.folder(for: [], sourcePID: nil), FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first)
    }

    func testPluginNeedsNoSelection() {
        let plugin = NewFilePlugin().info
        XCTAssertTrue(plugin.canHandle(.empty))
        XCTAssertTrue(plugin.canHandle(ContentClassifier.classify(.text("随便一段文字"))))
        XCTAssertTrue(plugin.canHandle(ContentClassifier.classify(.files([URL(fileURLWithPath: "/tmp")]))))
    }
}
