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
            XCTAssertTrue(english != missing || matchesFormattedKey(text, in: bundle), "「\(text)」没有英文翻译", file: file, line: line)
        }
    }

    /// 带参数的文字拿到的是填好参数的中文（「计算选中的算式，支持 + - × ÷ ^ % 和括号」），
    /// 看它是不是翻译文件里哪个带 %@、%lld 的 key（「计算选中的算式，支持 %@ 和括号」）填上参数的样子
    private func matchesFormattedKey(_ text: String, in bundle: Bundle) -> Bool {
        let url = URL(fileURLWithPath: bundle.bundlePath).appendingPathComponent("Localizable.strings")
        guard let table = NSDictionary(contentsOf: url) as? [String: String] else { return false }
        let range = NSRange(text.startIndex..., in: text)
        return table.keys.contains { key in
            guard key.contains("%@") || key.contains("%lld") else { return false }
            let pattern = key.components(separatedBy: "%@")
                .map { $0.components(separatedBy: "%lld").map(NSRegularExpression.escapedPattern(for:)).joined(separator: ".+") }
                .joined(separator: ".+")
            return (try? NSRegularExpression(pattern: "^" + pattern + "$"))?.firstMatch(in: text, range: range) != nil
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
