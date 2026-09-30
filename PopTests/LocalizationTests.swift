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

    /// 设置里的界面语言：用单独的 UserDefaults，不改测试进程自己的语言
    func testInterfaceLanguageSetting() throws {
        let suite = "pop.tests.language.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertEqual(InterfaceLanguage.stored(in: defaults, domain: suite), .system)

        InterfaceLanguage.store(.english, in: defaults)
        XCTAssertEqual(defaults.persistentDomain(forName: suite)?["AppleLanguages"] as? [String], ["en"])
        XCTAssertEqual(InterfaceLanguage.stored(in: defaults, domain: suite), .english)

        InterfaceLanguage.store(.simplifiedChinese, in: defaults)
        XCTAssertEqual(defaults.persistentDomain(forName: suite)?["AppleLanguages"] as? [String], ["zh-Hans"])
        XCTAssertEqual(InterfaceLanguage.stored(in: defaults, domain: suite), .simplifiedChinese)

        InterfaceLanguage.store(.system, in: defaults)
        XCTAssertNil(defaults.persistentDomain(forName: suite)?["AppleLanguages"])
        XCTAssertEqual(InterfaceLanguage.stored(in: defaults, domain: suite), .system)

        // 系统设置里给 Pop 单独选的其他语言、带地区的写法
        defaults.set(["zh-Hans-CN", "en"], forKey: "AppleLanguages")
        XCTAssertEqual(InterfaceLanguage.stored(in: defaults, domain: suite), .simplifiedChinese)
        defaults.set(["ja"], forKey: "AppleLanguages")
        XCTAssertEqual(InterfaceLanguage.stored(in: defaults, domain: suite), .system)
        XCTAssertEqual(InterfaceLanguage.stored(in: defaults, domain: nil), .system)
    }

    /// 系统语言既不是中文也不是英文（比如只有日语）时用英文界面
    func testOtherSystemLanguagesFallBackToEnglish() {
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "CFBundleDevelopmentRegion") as? String, "en")
        XCTAssertEqual(Bundle.preferredLocalizations(from: Bundle.main.localizations, forPreferences: ["ja"]).first, "en")
        XCTAssertEqual(Bundle.preferredLocalizations(from: Bundle.main.localizations, forPreferences: ["zh-Hans-CN"]).first, "zh-Hans")
    }

    /// 测试进程用启动参数指定中文界面，Pop 自己的偏好设置里没有选语言
    func testLaunchArgumentsAreNotAChosenLanguage() {
        XCTAssertEqual(InterfaceLanguage.atLaunch, InterfaceLanguage.stored())
        XCTAssertEqual(InterfaceLanguage.english.title, "English")
        XCTAssertEqual(InterfaceLanguage.system.title, "跟随系统")
    }
}
