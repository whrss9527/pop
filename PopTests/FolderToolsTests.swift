import XCTest
@testable import Pop

final class DiskUsageTests: XCTestCase {
    private func makeFolder() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "pop-usage-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let files: [(String, Int)] = [("视频/旅行.mov", 300_000), ("视频/剪辑/片段.mp4", 120_000), ("文稿/报告.pdf", 40_000),
                                      ("文稿/笔记.txt", 2_000), ("安装包.dmg", 200_000), (".hidden/缓存.bin", 50_000),
                                      ("空文件夹/.keep", 0)]
        for (path, size) in files {
            let url = root.appending(path: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 1, count: size).write(to: url)
        }
        return root
    }

    func testTotalsAndDrillDown() throws {
        let result = DiskUsage.scan(try makeFolder())
        let root = result.root
        XCTAssertFalse(result.truncated)
        // 隐藏文件也算
        XCTAssertEqual(result.total.files, 7)
        XCTAssertGreaterThanOrEqual(result.total.size, 712_000)
        XCTAssertEqual(result.totals(of: root.appending(path: "视频")).files, 2)
        XCTAssertEqual(result.totals(of: root.appending(path: "视频")).size,
                       result.totals(of: root.appending(path: "视频/剪辑")).size
                           + (DiskUsage.children(of: root.appending(path: "视频"), in: result).first { !$0.isFolder }?.size ?? 0))

        let children = DiskUsage.children(of: root, in: result)
        XCTAssertEqual(children.map(\.url.lastPathComponent), ["视频", "安装包.dmg", ".hidden", "文稿", "空文件夹"])
        XCTAssertEqual(children.map(\.isFolder), [true, false, true, true, true])
        XCTAssertEqual(children.reduce(0) { $0 + $1.size }, result.total.size)
        XCTAssertEqual(result.largest.map(\.url.lastPathComponent).prefix(3), ["旅行.mov", "安装包.dmg", "片段.mp4"])
        XCTAssertEqual(DiskUsage.relativePath(result.largest[2].url, in: root), "视频/剪辑/片段.mp4")
    }

    func testRemovingUpdatesTotals() throws {
        let result = DiskUsage.scan(try makeFolder())
        let root = result.root
        let video = try XCTUnwrap(DiskUsage.children(of: root, in: result).first { $0.url.lastPathComponent == "视频" })
        let updated = DiskUsage.removing(video, from: result)
        XCTAssertEqual(updated.total.files, 5)
        XCTAssertEqual(updated.total.size, result.total.size - video.size)
        XCTAssertNil(updated.folders[DiskUsage.key(root.appending(path: "视频/剪辑"))])
        XCTAssertFalse(updated.largest.contains { $0.url.lastPathComponent == "旅行.mov" })
        XCTAssertEqual(updated.largest.first?.url.lastPathComponent, "安装包.dmg")
    }

    func testCancelStopsEarly() throws {
        let root = try makeFolder()
        let result = DiskUsage.scan(root, isCancelled: { true })
        XCTAssertEqual(result.total.files, 0)
    }
}

final class CodeStatsTests: XCTestCase {
    func testCountsLinesAndBlankLines() {
        XCTAssertEqual(CodeStats.count(Data("a\n\n  \nb".utf8))?.lines, 4)
        XCTAssertEqual(CodeStats.count(Data("a\n\n  \nb".utf8))?.blank, 2)
        XCTAssertEqual(CodeStats.count(Data("a\r\nb\r\n".utf8))?.lines, 2)
        XCTAssertEqual(CodeStats.count(Data())?.lines, 0)
        XCTAssertNil(CodeStats.count(Data([0x50, 0x4B, 0x00, 0x03])))
        XCTAssertEqual(CodeStats.language(of: URL(fileURLWithPath: "/tmp/App.swift")), "Swift")
        XCTAssertEqual(CodeStats.language(of: URL(fileURLWithPath: "/tmp/Makefile")), "Makefile")
        XCTAssertNil(CodeStats.language(of: URL(fileURLWithPath: "/tmp/package-lock.json")))
        XCTAssertNil(CodeStats.language(of: URL(fileURLWithPath: "/tmp/vendor.min.js")))
        XCTAssertNil(CodeStats.language(of: URL(fileURLWithPath: "/tmp/photo.png")))
    }

    func testScanSkipsDependenciesAndHiddenFolders() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "pop-code-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let files: [(String, String)] = [
            ("Sources/App.swift", "import SwiftUI\n\nstruct App {}\n"),
            ("Sources/Model.swift", "struct Model {\n    var name: String\n}\n"),
            ("web/index.js", "console.log(1)\n"),
            ("web/node_modules/lib/index.js", "module.exports = 1\n"),
            (".git/config", "[core]\n"),
            ("build/out.swift", "let x = 1\n"),
            ("README.md", "# Demo\n\nHello\n"),
            ("package-lock.json", "{}\n"),
        ]
        for (path, text) in files {
            let url = root.appending(path: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }
        let result = CodeStats.scan([root])
        XCTAssertEqual(result.languages.map(\.name), ["Swift", "Markdown", "JavaScript"])
        XCTAssertEqual(result.languages.first, CodeStats.Language(name: "Swift", files: 2, lines: 6, blank: 1))
        XCTAssertEqual(result.files, 4)
        XCTAssertEqual(result.lines, 10)
        XCTAssertFalse(result.truncated)
        let table = CodeStats.markdown(result)
        XCTAssertTrue(table.hasPrefix("| 语言 | 文件 | 行数 | 空行 | 代码行 |"), table)
        XCTAssertTrue(table.contains("| Swift | 2 | 6 | 1 | 5 |"), table)
        XCTAssertTrue(table.hasSuffix("| 合计 | 4 | 10 | 2 | 8 |"), table)
    }
}

@MainActor
final class FolderPluginTests: XCTestCase {
    func testPluginsNeedAFolderOrMedia() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "pop-folder-plugins-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appending(path: "Sources"), withIntermediateDirectories: true)
        let source = root.appending(path: "Sources/main.swift")
        try Data("let a = 1\n\nlet b = 2\n".utf8).write(to: source)
        let context = PluginContext(settings: AppSettings(), openSettings: {})
        let folder = ContentClassifier.classify(.files([root]))
        let file = ContentClassifier.classify(.files([source]))
        XCTAssertTrue(DiskUsagePlugin().info.canHandle(folder))
        XCTAssertTrue(CodeStatsPlugin().info.canHandle(folder))
        XCTAssertFalse(DiskUsagePlugin().info.canHandle(file))
        XCTAssertFalse(CodeStatsPlugin().info.canHandle(file))

        let usage = await DiskUsagePlugin().run(folder, context: context)
        XCTAssertEqual(usage, .diskUsage(root))
        let stats = await CodeStatsPlugin().run(folder, context: context)
        guard case .card(let card) = stats else { return XCTFail("应该返回结果卡片") }
        XCTAssertEqual(card.rows.map(\.label), ["Swift"])
        XCTAssertTrue(card.copyText?.contains("| Swift | 1 | 3 | 1 | 2 |") == true, card.copyText ?? "")

        let video = URL(fileURLWithPath: "/tmp/pop-missing-\(UUID().uuidString)/录屏.mov")
        let media = ContentClassifier.classify(.files([video]))
        XCTAssertTrue(TrimMediaPlugin().info.canHandle(media))
        XCTAssertFalse(TrimMediaPlugin().info.canHandle(file))
        let trim = await TrimMediaPlugin().run(media, context: context)
        XCTAssertEqual(trim, .trimMedia(video))
    }
}
