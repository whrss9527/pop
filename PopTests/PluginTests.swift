import AppKit
import XCTest
@testable import Pop

final class RouterTests: XCTestCase {
    private let catalog = BuiltinPlugins.make().map(\.info)

    private func decide(_ text: String, settings: AppSettings = AppSettings(), catalog: [PluginInfo]? = nil) -> Router.Decision {
        Router.decide(ContentClassifier.classify(.text(text)), settings: settings, catalog: catalog ?? self.catalog)
    }

    func testDefaultRules() {
        XCTAssertEqual(decide("Good morning, everyone"), .direct(pluginID: BuiltinPluginID.translate))
        XCTAssertEqual(decide("1 + 2 * 3"), .direct(pluginID: BuiltinPluginID.calculate))
        XCTAssertEqual(decide("#FF8800"), .direct(pluginID: BuiltinPluginID.colorConvert))
        // 单个英文单词默认还是翻译（查词典的规则默认关闭）
        XCTAssertEqual(decide("serendipity"), .direct(pluginID: BuiltinPluginID.translate))
        // 中文、链接、数字默认不直达
        XCTAssertEqual(decide("今天天气很好"), .ring)
        XCTAssertEqual(decide("https://example.com"), .ring)
        XCTAssertEqual(decide("12345"), .ring)
        XCTAssertEqual(Router.decide(.empty, settings: AppSettings(), catalog: catalog), .ring)
        // 带单位的数值直接换算
        XCTAssertEqual(decide("5 km"), .direct(pluginID: BuiltinPluginID.unitConvert))
    }

    func testImageGoesToOCR() {
        let content = ContentClassifier.classify(.image(Data([0x89, 0x50])))
        XCTAssertEqual(Router.decide(content, settings: AppSettings(), catalog: catalog), .direct(pluginID: BuiltinPluginID.ocr))
    }

    func testDisabledRuleOrUninstalledPluginFallsBackToRing() {
        var settings = AppSettings()
        settings.setInstalled(BuiltinPluginID.translate, false)
        XCTAssertEqual(decide("Good morning, everyone", settings: settings), .ring)

        settings = AppSettings()
        if let index = settings.rules.firstIndex(where: { $0.condition == .foreignText }) {
            settings.rules[index].enabled = false
        }
        XCTAssertEqual(decide("Good morning, everyone", settings: settings), .ring)
    }

    func testCustomRule() {
        var settings = AppSettings()
        if let index = settings.rules.firstIndex(where: { $0.condition == .url }) {
            settings.rules[index].enabled = true
        }
        XCTAssertEqual(decide("https://example.com", settings: settings), .direct(pluginID: BuiltinPluginID.openURL))

        // 单个词的规则排在外文前面，打开后优先查词典
        settings = AppSettings()
        if let index = settings.rules.firstIndex(where: { $0.condition == .word }) {
            settings.rules[index].enabled = true
        }
        XCTAssertEqual(decide("serendipity", settings: settings), .direct(pluginID: BuiltinPluginID.dictionary))
        XCTAssertEqual(decide("Good morning, everyone", settings: settings), .direct(pluginID: BuiltinPluginID.translate))
    }

    func testRuleCanTargetUserPlugin() {
        let manifest = PluginManifest(id: "user-test", name: "测试插件", match: .init(kinds: [.text]))
        let catalog = self.catalog + [ManifestPlugin(manifest: manifest).info]
        var settings = AppSettings()
        settings.setInstalled("user-test", true)
        if let index = settings.rules.firstIndex(where: { $0.condition == .anyText }) {
            settings.rules[index].pluginID = "user-test"
            settings.rules[index].enabled = true
        }
        XCTAssertEqual(decide("今天天气很好", settings: settings, catalog: catalog), .direct(pluginID: "user-test"))
    }

    func testPluginMatching() {
        let content = ContentClassifier.classify(.text("https://example.com"))
        let matching = catalog.filter { $0.canHandle(content) }.map(\.id)
        XCTAssertTrue(matching.contains(BuiltinPluginID.openURL))
        XCTAssertTrue(matching.contains(BuiltinPluginID.search))
        XCTAssertTrue(matching.contains(BuiltinPluginID.settings))
        XCTAssertFalse(matching.contains(BuiltinPluginID.copyPath))
        // 什么都没选中时只有不需要内容的功能可用
        XCTAssertEqual(Set(catalog.filter { $0.canHandle(.empty) }.map(\.id)), [
            BuiltinPluginID.random, BuiltinPluginID.screenshotOCR, BuiltinPluginID.colorPicker,
            BuiltinPluginID.clipboardHistory, BuiltinPluginID.allPlugins, BuiltinPluginID.settings,
            BuiltinPluginID.screenshotTranslate, BuiltinPluginID.pin, BuiltinPluginID.windowLayout,
            BuiltinPluginID.snippets, BuiltinPluginID.annotate, BuiltinPluginID.scanCode, BuiltinPluginID.keepAwake,
            BuiltinPluginID.shelf, BuiltinPluginID.ruler, BuiltinPluginID.timer, BuiltinPluginID.tableOCR,
            BuiltinPluginID.vocabulary, BuiltinPluginID.sendToPhone,
        ])
    }

    func testPatternAndLengthConstraints() {
        let info = PluginInfo(id: "x", name: "x", symbol: "x", summary: "", accepts: [.text], pattern: "^[0-9]+$", maxLength: 5)
        XCTAssertTrue(info.canHandle(ContentClassifier.classify(.text("123"))))
        XCTAssertFalse(info.canHandle(ContentClassifier.classify(.text("abc"))))
        XCTAssertFalse(info.canHandle(ContentClassifier.classify(.text("1234567"))))
        XCTAssertFalse(info.canHandle(.empty))
        // 大小写转换只在有字母时出现
        let changeCase = ChangeCasePlugin().info
        XCTAssertTrue(changeCase.canHandle(ContentClassifier.classify(.text("hello"))))
        XCTAssertFalse(changeCase.canHandle(ContentClassifier.classify(.text("你好"))))
    }

    /// 设置里按分类显示：只有剪贴板、全部功能、设置归到「其他」
    func testEveryBuiltinHasACategory() {
        let others = catalog.map(\.id).filter { BuiltinCategory.of($0) == .other }
        XCTAssertEqual(Set(others), [BuiltinPluginID.clipboardHistory, BuiltinPluginID.allPlugins, BuiltinPluginID.settings])
        for category in BuiltinCategory.allCases {
            XCTAssertTrue(catalog.contains { BuiltinCategory.of($0.id) == category }, category.title)
        }
    }

    /// 每个内置功能的图标在这个系统上都有：新系统才有的图标在 macOS 15 上会显示成空白
    func testEveryBuiltinSymbolExists() {
        for info in catalog {
            XCTAssertNotNil(NSImage(systemSymbolName: info.symbol, accessibilityDescription: nil), "\(info.id)：没有 \(info.symbol) 这个图标")
        }
    }

    func testPluginIDsAreUniqueAndCoverDefaults() {
        let ids = catalog.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertEqual(Set(ids), Set(BuiltinPluginID.all))
        for slot in RingLayout.default.slots.compactMap({ $0 }) {
            XCTAssertTrue(ids.contains(slot), slot)
        }
        for rule in DirectRule.defaults {
            if let pluginID = rule.pluginID {
                XCTAssertTrue(ids.contains(pluginID), pluginID)
            }
        }
    }
}

final class BuiltinPluginTests: XCTestCase {
    @MainActor
    private func run(_ plugin: any PopPlugin, _ text: String) async -> PluginOutcome {
        await plugin.run(ContentClassifier.classify(.text(text)), context: PluginContext(settings: AppSettings(), openSettings: {}))
    }

    @MainActor
    private func card(_ plugin: any PopPlugin, _ text: String, file: StaticString = #filePath, line: UInt = #line) async -> ResultCard? {
        let outcome = await run(plugin, text)
        guard case .card(let card) = outcome else {
            XCTFail("应该返回结果卡片：\(outcome)", file: file, line: line)
            return nil
        }
        return card
    }

    private func value(_ card: ResultCard?, _ label: String) -> String? {
        card?.rows.first { $0.label == label }?.value
    }

    @MainActor
    func testCalculator() async {
        let card = await card(CalculatorPlugin(), "(1 + 2) * 3")
        XCTAssertEqual(card?.body, "9")
        XCTAssertEqual(card?.copyText, "9")
        XCTAssertEqual(card?.replaceText, "9")
    }

    @MainActor
    func testTranslateHandsOffText() async {
        let outcome = await run(TranslatePlugin(), "  Good morning  ")
        guard case .translate(let text, _) = outcome else { return XCTFail("应该交给翻译卡片：\(outcome)") }
        XCTAssertEqual(text, "Good morning")
    }

    @MainActor
    func testFormatJSONAndTimestamp() async {
        let jsonCard = await card(FormatJSONPlugin(), #"{"a": 1, "b": [1, 2]}"#)
        XCTAssertEqual(jsonCard?.monospaced, true)
        XCTAssertEqual(jsonCard?.body.contains("\"a\""), true)
        XCTAssertEqual(jsonCard?.buttons.first?.action, .copy(#"{"a":1,"b":[1,2]}"#))

        let timeCard = await card(TimestampPlugin(), "1727510400")
        XCTAssertEqual(value(timeCard, "UTC"), "2024-09-28T08:00:00Z")
        XCTAssertEqual(value(timeCard, "Unix 毫秒"), "1727510400000")
        XCTAssertEqual(timeCard?.rowsReplaceable, true)
    }

    @MainActor
    func testConversionPlugins() async {
        let caseCard = await card(ChangeCasePlugin(), "hello world")
        XCTAssertEqual(value(caseCard, "camelCase"), "helloWorld")
        XCTAssertEqual(value(caseCard, "snake_case"), "hello_world")
        XCTAssertEqual(caseCard?.rowsReplaceable, true)

        let codecCard = await card(EncodeDecodePlugin(), "aGVsbG8=")
        XCTAssertEqual(codecCard?.rows.first?.label, "Base64 解码")
        XCTAssertEqual(codecCard?.rows.first?.value, "hello")

        let numberCard = await card(NumberConvertPlugin(), "255")
        XCTAssertEqual(value(numberCard, "十六进制"), "0xFF")
        XCTAssertEqual(value(numberCard, "人民币大写"), "贰佰伍拾伍元整")

        let colorCard = await card(ColorConvertPlugin(), "#FF8800")
        XCTAssertEqual(colorCard?.swatchHex, "#FF8800")
        XCTAssertEqual(value(colorCard, "RGB"), "rgb(255, 136, 0)")
    }

    @MainActor
    func testUnitConversionAndCleanup() async {
        let unitCard = await card(UnitConvertPlugin(), "5 km")
        XCTAssertEqual(value(unitCard, "英里"), "3.10686 mi")
        XCTAssertEqual(unitCard?.detail, "长度：5 km")
        XCTAssertEqual(unitCard?.rowsReplaceable, true)

        let cleanupCard = await card(TextCleanupPlugin(), "用React写\n组件")
        XCTAssertEqual(value(cleanupCard, "合并换行"), "用React写组件")
        XCTAssertEqual(value(cleanupCard, "中英文空格"), "用 React 写\n组件")
        XCTAssertEqual(cleanupCard?.rowLineLimit, 2)
    }

    @MainActor
    func testHashAndStatistics() async {
        let hashCard = await card(HashPlugin(), "abc")
        XCTAssertEqual(value(hashCard, "SHA-256"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")

        let statsCard = await card(TextStatsPlugin(), "你好 world")
        XCTAssertEqual(value(statsCard, "字符"), "8")
        XCTAssertEqual(value(statsCard, "汉字"), "2")
    }

    @MainActor
    func testQRCodeRoundTrip() async throws {
        let text = "https://github.com/whrss9527/pop"
        let qrCard = await card(QRCodePlugin(), text)
        let png = try XCTUnwrap(qrCard?.image)
        let image = try XCTUnwrap(TextRecognizer.cgImage(from: png))
        XCTAssertEqual(QRCode.decode(image), [text])
    }

    @MainActor
    func testPanelsAndGenerators() async {
        let empty = PluginContext(settings: AppSettings(), openSettings: {})
        let all = await AllPluginsPlugin().run(.empty, context: empty)
        XCTAssertEqual(all, .showAllPlugins)
        let history = await ClipboardHistoryPlugin().run(.empty, context: empty)
        XCTAssertEqual(history, .showClipboardHistory)
        let random = await RandomPlugin().run(.empty, context: empty)
        guard case .card(let card) = random else { return XCTFail("应该返回结果卡片") }
        XCTAssertEqual(card.rows.count, 5)
        XCTAssertEqual(UUID(uuidString: card.rows[0].value) != nil, true)
    }

    @MainActor
    func testFailureWhenContentDoesNotFit() async {
        let outcome = await run(CalculatorPlugin(), "not math")
        XCTAssertEqual(outcome, .failure("无法计算这个算式"))
    }

    func testQuickNoteAppends() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "pop-note-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "notes.md")
        try QuickNotePlugin.append("first line", source: "Safari", to: url)
        try QuickNotePlugin.append("second line", source: nil, to: url)
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.hasPrefix("# Pop 收集箱\n"))
        XCTAssertTrue(text.contains("· Safari\n\nfirst line\n"))
        XCTAssertTrue(text.contains("second line"))
    }
}
