import XCTest
@testable import Pop

/// 界面文字的英文翻译。编译器抽得出来的文字由 scripts/check-localization.py 检查，这里查运行时才拼出来的那些。
@MainActor
final class LocalizationTests: XCTestCase {
    private func englishBundle() throws -> Bundle {
        let path = try XCTUnwrap(Bundle.main.path(forResource: "en", ofType: "lproj"), "App 里没有 en.lproj")
        return try XCTUnwrap(Bundle(path: path))
    }

    private func assertTranslated(_ texts: [String], in bundle: Bundle, file: StaticString = #filePath, line: UInt = #line) {
        let missing = "\u{0}"
        for text in texts where text.unicodeScalars.contains(where: { (0x3400...0x9FFF).contains($0.value) }) {
            let english = bundle.localizedString(forKey: text, value: missing, table: nil)
            XCTAssertNotEqual(english, missing, "「\(text)」没有英文翻译", file: file, line: line)
        }
    }

    func testTestsRunWithTheChineseInterface() {
        XCTAssertTrue(Localization.isChinese, "单元测试要用中文界面跑（scheme 的测试语言是 zh-Hans）")
        XCTAssertEqual(Localization.listSeparator, "、")
    }

    func testAppHasBothLanguages() {
        let localizations = Set(Bundle.main.localizations)
        XCTAssertTrue(localizations.isSuperset(of: ["zh-Hans", "en"]), "\(localizations)")
    }

    func testBuiltinActionsHaveEnglishNames() throws {
        let bundle = try englishBundle()
        let infos = BuiltinPlugins.make().map(\.info)
        XCTAssertGreaterThan(infos.count, 50)
        assertTranslated(infos.flatMap { [$0.name, $0.summary] }, in: bundle)
        assertTranslated(BuiltinCategory.allCases.map(\.title), in: bundle)
    }

    func testSettingsAndUnitsHaveEnglishNames() throws {
        let bundle = try englishBundle()
        assertTranslated(SettingsTab.allCases.map(\.title), in: bundle)
        assertTranslated(UnitConverter.units.map(\.name), in: bundle)
        assertTranslated(ContentKind.allCases.map(\.title), in: bundle)
    }
}
