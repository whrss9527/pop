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
        // 单独发布的插件包查它自己带的翻译（下面那个测试）
        let infos = TestCatalog.infos().filter { !TestCatalog.publishedFunctionIDs.contains($0.id) }
        XCTAssertGreaterThan(infos.count, 50)
        assertTranslated(infos.flatMap { [$0.name, $0.summary] }, in: bundle)
        assertTranslated(BuiltinCategory.allCases.map(\.title), in: bundle)
    }

    /// 单独发布的插件包：功能的名字、介绍在它自己的 en.lproj 里（PluginBundles/<文件夹>/en.lproj，直接读源码里的）
    func testPublishedActionsHaveEnglishNames() throws {
        XCTAssertFalse(TestCatalog.published.isEmpty)
        for (folder, entry) in TestCatalog.published {
            let bundle = try XCTUnwrap(TestCatalog.publishedEnglishBundle(folder), "PluginBundles/\(folder)/en.lproj")
            assertTranslated(entry.makePlugins().flatMap { [$0.info.name, $0.info.summary] }, in: bundle)
        }
    }

    func testSettingsAndUnitsHaveEnglishNames() throws {
        let bundle = try englishBundle()
        assertTranslated(SettingsTab.allCases.map(\.title), in: bundle)
        assertTranslated(UnitConverter.units.map(\.name), in: bundle)
        assertTranslated(ContentKind.allCases.map(\.title), in: bundle)
    }

    /// 英文的单复数（en.lproj/Localizable.stringsdict）：数量都是 2 时和 Localizable.strings 里的英文一样，
    /// 都是 1 时换成单数（每一条至少有一处不一样），占位符都填上了
    func testEnglishPluralsFollowTheStringsFile() throws {
        let bundle = try englishBundle()
        let folder = URL(fileURLWithPath: bundle.bundlePath)
        let plurals = try XCTUnwrap(NSDictionary(contentsOf: folder.appendingPathComponent("Localizable.stringsdict")) as? [String: Any])
        let table = try XCTUnwrap(NSDictionary(contentsOf: folder.appendingPathComponent("Localizable.strings")) as? [String: String])
        XCTAssertGreaterThan(plurals.count, 50)
        let english = Locale(identifier: "en_US")
        for key in plurals.keys.sorted() {
            let plain = try XCTUnwrap(table[key], "Localizable.strings 里没有「\(key)」")
            // key 里的占位符按顺序：%lld 填数量，%@ 填一个词
            var integers: [Bool] = []
            var rest = Substring(key)
            while let mark = rest.firstIndex(of: "%") {
                rest = rest[rest.index(after: mark)...]
                if rest.hasPrefix("lld") {
                    integers.append(true)
                } else if rest.hasPrefix("@") {
                    integers.append(false)
                }
            }
            func arguments(_ count: Int) -> [CVarArg] {
                integers.map { $0 ? count as CVarArg : "x" as CVarArg }
            }
            let format = bundle.localizedString(forKey: key, value: nil, table: nil)
            let one = String(format: format, locale: english, arguments: arguments(1))
            let two = String(format: format, locale: english, arguments: arguments(2))
            XCTAssertEqual(two, String(format: plain, locale: english, arguments: arguments(2)), key)
            XCTAssertNotEqual(one, two, key)
            XCTAssertFalse(one.contains("%") || two.contains("%"), "「\(key)」→「\(one)」「\(two)」")
        }
        // 用的时候（String(localized:)）也是这样。单复数按 locale 的语言分，英文界面时 Locale.current 的语言就是英文；
        // 测试用中文跑，这里写明
        XCTAssertEqual(String(localized: "\(1) 个文件", bundle: bundle, locale: english), "1 file")
        XCTAssertEqual(String(localized: "\(3) 个文件", bundle: bundle, locale: english), "3 files")
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
