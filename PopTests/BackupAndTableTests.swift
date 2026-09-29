import XCTest
@testable import Pop

final class SettingsBackupTests: XCTestCase {
    func testRoundTrip() throws {
        var settings = AppSettings()
        settings.snippets = [Snippet(title: "签名", text: "Pop 团队")]
        settings.searchEngine = .bing
        let plugin = PluginManifest(id: "user-github", name: "GitHub 搜索", match: .init(kinds: [.text]))
        let backup = SettingsBackup(settings: settings, plugins: [plugin], appVersion: "0.14.0",
                                    exportedAt: Date(timeIntervalSince1970: 1_790_000_000))
        let data = try backup.encoded()
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains(#""format" : "pop-settings""#), text)

        let decoded = try SettingsBackup.decode(data)
        XCTAssertEqual(decoded.settings.snippets, settings.snippets)
        XCTAssertEqual(decoded.settings.searchEngine, .bing)
        XCTAssertEqual(decoded.plugins.map(\.id), ["user-github"])
        XCTAssertEqual(decoded.appVersion, "0.14.0")
        XCTAssertEqual(decoded.summary, "圆盘、直达规则、唤起方式和快捷键、翻译、剪贴板、AI 接口设置、1 条常用短语、1 个自己写的插件")
    }

    func testRejectsOtherFiles() {
        XCTAssertThrowsError(try SettingsBackup.decode(Data("{}".utf8)))
        XCTAssertThrowsError(try SettingsBackup.decode(Data(#"{"format": "other", "version": 1}"#.utf8)))
        XCTAssertThrowsError(try SettingsBackup.decode(Data("not json".utf8)))
    }

    func testFileName() {
        XCTAssertEqual(SettingsBackup.suggestedFileName(date: Date(timeIntervalSince1970: 1_790_000_000)), "Pop 设置 2026-09-21.json")
    }
}

final class TableOCRTests: XCTestCase {
    func testGridPlacesCellsByRowAndColumn() {
        let cells = [
            TableOCR.Cell(row: 0, column: 0, text: "功能"), TableOCR.Cell(row: 0, column: 1, text: "分类"),
            TableOCR.Cell(row: 1, column: 0, text: "按行\n处理"), TableOCR.Cell(row: 1, column: 1, text: " 文字 "),
            // 同一个格子出现两次只取一次
            TableOCR.Cell(row: 1, column: 1, text: "重复"),
            TableOCR.Cell(row: 3, column: 1, text: "只有第二列"),
        ]
        XCTAssertEqual(TableOCR.grid(cells), [["功能", "分类"], ["按行 处理", "文字"], ["", "只有第二列"]])
        XCTAssertEqual(TableOCR.grid([]), [])
    }
}
