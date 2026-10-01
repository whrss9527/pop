import AppKit
import SwiftUI
import XCTest
@testable import Pop

final class FontPreviewTests: XCTestCase {
    override func setUp() {
        UserDefaults.standard.removeObject(forKey: FontPreviewModel.favoritesKey)
        UserDefaults.standard.removeObject(forKey: FontPreviewModel.sizeKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: FontPreviewModel.favoritesKey)
        UserDefaults.standard.removeObject(forKey: FontPreviewModel.sizeKey)
    }

    private func family(_ name: String, chinese: Bool = false, mono: Bool = false) -> FontCatalog.Family {
        FontCatalog.Family(name: name, displayName: name, postScriptName: name, styles: 1, isChinese: chinese, isMonospaced: mono, file: nil)
    }

    func testReadsTheInstalledFonts() throws {
        let families = FontCatalog.installed()
        XCTAssertGreaterThan(families.count, 20)
        XCTAssertFalse(families.contains { $0.name.hasPrefix(".") })
        let menlo = try XCTUnwrap(families.first { $0.name == "Menlo" })
        XCTAssertTrue(menlo.isMonospaced)
        XCTAssertFalse(menlo.isChinese)
        XCTAssertGreaterThan(menlo.styles, 1)
        XCTAssertTrue(menlo.isSystem)
        let pingFang = try XCTUnwrap(families.first { $0.name == "PingFang SC" })
        XCTAssertTrue(pingFang.isChinese)
        XCTAssertFalse(pingFang.isMonospaced)

        let menloFont = CTFontCreateWithName(menlo.postScriptName as CFString, 16, nil)
        XCTAssertTrue(FontCatalog.covers(menloFont, "Hello, world 123"))
        XCTAssertFalse(FontCatalog.covers(menloFont, "你好"))
        XCTAssertTrue(FontCatalog.covers(CTFontCreateWithName(pingFang.postScriptName as CFString, 16, nil), "你好，世界"))
        // 空格和换行不算
        XCTAssertTrue(FontCatalog.covers(menloFont, " \n "))

        // 字体文件不装也能读出每一款
        let file = try XCTUnwrap(menlo.file)
        let faces = FontCatalog.faces(in: file)
        XCTAssertTrue(faces.contains { $0.postScriptName == menlo.postScriptName })
        XCTAssertTrue(FontCatalog.isFontFile(file))
        XCTAssertFalse(FontCatalog.isFontFile(URL(fileURLWithPath: "/tmp/a.txt")))
        XCTAssertTrue(FontCatalog.faces(in: URL(fileURLWithPath: "/tmp/没有这个.ttf")).isEmpty)
    }

    func testFiltersBySearchFavoritesAndCoverage() {
        let families = [family("Songti SC", chinese: true), family("Menlo", mono: true), family("Georgia"), family("Kaiti SC", chinese: true)]
        let coverage = ["Songti SC": true, "Menlo": false, "Georgia": false, "Kaiti SC": false]
        func names(_ filter: FontCatalog.Filter, search: String = "", text: String? = nil, favorites: Set<String> = []) -> [String] {
            FontCatalog.filter(families, by: filter, favorites: favorites, search: search, covering: text, coverage: coverage).map(\.name)
        }
        XCTAssertEqual(names(.all), ["Songti SC", "Menlo", "Georgia", "Kaiti SC"])
        XCTAssertEqual(names(.chinese), ["Songti SC", "Kaiti SC"])
        XCTAssertEqual(names(.western), ["Menlo", "Georgia"])
        XCTAssertEqual(names(.monospaced), ["Menlo"])
        XCTAssertEqual(names(.favorites, favorites: ["Georgia"]), ["Georgia"])
        XCTAssertEqual(names(.all, search: "sc"), ["Songti SC", "Kaiti SC"])
        // 只看能完整显示这段文字的
        XCTAssertEqual(names(.all, text: "你好"), ["Songti SC"])
        XCTAssertEqual(FontCatalog.css(families[0]), "font-family: \"Songti SC\";")
        XCTAssertEqual(FontCatalog.Filter.allCases.map(\.title), ["全部", "中文", "西文", "等宽", "收藏"])
    }

    @MainActor
    func testCardStartsWithTheSelectionAndRemembersChoices() throws {
        let families = FontCatalog.installed()
        let model = FontPreviewModel(text: "  落霞与孤鹜齐飞  ", families: families)
        XCTAssertEqual(model.text, "落霞与孤鹜齐飞")
        XCTAssertEqual(model.filter, .chinese)
        XCTAssertEqual(model.size, 24)
        XCTAssertTrue(model.shown.allSatisfy(\.isChinese))
        XCTAssertTrue(model.shown.contains { $0.name == "PingFang SC" })
        XCTAssertFalse(model.shown.contains { $0.name == "Menlo" })
        XCTAssertEqual(model.summary, "\(model.shown.count) 种字体能完整显示这段文字")
        model.onlyCovering = false
        XCTAssertEqual(model.summary, "\(model.shown.count) 种字体")

        let pingFang = try XCTUnwrap(families.first { $0.name == "PingFang SC" })
        model.toggleFavorite(pingFang)
        XCTAssertEqual(UserDefaults.standard.stringArray(forKey: FontPreviewModel.favoritesKey), ["PingFang SC"])
        model.filter = .favorites
        XCTAssertEqual(model.shown.map(\.name), ["PingFang SC"])
        model.size = 40
        XCTAssertEqual(FontPreviewModel(text: nil, families: families).size, 40)
        model.toggleFavorite(pingFang)
        XCTAssertTrue(model.shown.isEmpty)

        // 没选中文字时用示例，看全部字体
        let sample = FontPreviewModel(text: nil, families: families)
        XCTAssertEqual(sample.text, FontCatalog.sample)
        XCTAssertEqual(sample.filter, .all)
        XCTAssertFalse(sample.onlyCovering)
        XCTAssertTrue(sample.shown.contains { $0.name == "Menlo" })
        // 没有一个字体能完整显示时说明怎么办
        model.filter = .monospaced
        model.onlyCovering = true
        XCTAssertEqual(model.summary, "没有能完整显示这段文字的字体，取消「只看能显示的」再看看")
        // 复制成图片
        let png = try XCTUnwrap(model.image(.custom(pingFang.postScriptName, size: 24)))
        XCTAssertNotNil(NSImage(data: png))
    }

    @MainActor
    func testInstallsFontFiles() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "pop-fonts-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appending(path: "来源/示例字体.ttf")
        try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("不是真的字体".utf8).write(to: source)
        let fonts = folder.appending(path: "Fonts", directoryHint: .isDirectory)
        XCTAssertEqual(try FontCatalog.install([source], into: fonts).map(\.lastPathComponent), ["示例字体.ttf"])
        // 已经有了就不再复制
        XCTAssertEqual(try FontCatalog.install([source], into: fonts).count, 1)

        let model = FontPreviewModel(text: nil, families: [], files: [source])
        model.install(into: fonts)
        XCTAssertEqual(model.installed?.map(\.lastPathComponent), ["示例字体.ttf"])
        XCTAssertNil(model.installError)
    }

    func testPluginWorksWithOrWithoutASelection() {
        let plugin = FontPreviewPlugin().info
        XCTAssertTrue(plugin.canHandle(.empty))
        XCTAssertTrue(plugin.canHandle(ContentClassifier.classify(.text("你好"))))
        XCTAssertTrue(plugin.canHandle(ContentClassifier.classify(.files([URL(fileURLWithPath: "/tmp/字体.otf")]))))
    }
}
