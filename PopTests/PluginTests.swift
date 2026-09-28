import XCTest
@testable import Pop

final class RouterTests: XCTestCase {
    private let catalog = BuiltinPlugins.make().map(\.info)

    private func decide(_ text: String, settings: AppSettings = AppSettings()) -> Router.Decision {
        Router.decide(ContentClassifier.classify(.text(text)), settings: settings, catalog: catalog)
    }

    func testDefaultRules() {
        XCTAssertEqual(decide("Good morning, everyone"), .direct(pluginID: BuiltinPluginID.translate))
        XCTAssertEqual(decide("1 + 2 * 3"), .direct(pluginID: BuiltinPluginID.calculate))
        // 中文、链接默认不直达
        XCTAssertEqual(decide("今天天气很好"), .ring)
        XCTAssertEqual(decide("https://example.com"), .ring)
        XCTAssertEqual(Router.decide(.empty, settings: AppSettings(), catalog: catalog), .ring)
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
    }

    func testPluginMatching() {
        let content = ContentClassifier.classify(.text("https://example.com"))
        let matching = catalog.filter { $0.canHandle(content) }.map(\.id)
        XCTAssertTrue(matching.contains(BuiltinPluginID.openURL))
        XCTAssertTrue(matching.contains(BuiltinPluginID.search))
        XCTAssertTrue(matching.contains(BuiltinPluginID.settings))
        XCTAssertFalse(matching.contains(BuiltinPluginID.copyPath))
        // 什么都没选中时只有不需要内容的功能可用
        XCTAssertEqual(catalog.filter { $0.canHandle(.empty) }.map(\.id), [BuiltinPluginID.settings])
    }

    func testPluginIDsAreUniqueAndCoverDefaults() {
        let ids = catalog.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertEqual(Set(ids), Set(BuiltinPluginID.all))
        for slot in RingLayout.default.slots.compactMap({ $0 }) {
            XCTAssertTrue(ids.contains(slot), slot)
        }
    }
}

final class BuiltinPluginTests: XCTestCase {
    @MainActor
    private func run(_ plugin: any PopPlugin, _ text: String) async -> PluginOutcome {
        await plugin.run(ContentClassifier.classify(.text(text)), context: PluginContext(settings: AppSettings(), openSettings: {}))
    }

    @MainActor
    func testCalculator() async {
        let outcome = await run(CalculatorPlugin(), "(1 + 2) * 3")
        guard case .card(let card) = outcome else { return XCTFail("应该返回结果卡片：\(outcome)") }
        XCTAssertEqual(card.body, "9")
        XCTAssertEqual(card.copyText, "9")
    }

    @MainActor
    func testTranslateHandsOffText() async {
        let outcome = await run(TranslatePlugin(), "  Good morning  ")
        guard case .translate(let text, _) = outcome else { return XCTFail("应该交给翻译卡片：\(outcome)") }
        XCTAssertEqual(text, "Good morning")
    }

    @MainActor
    func testFormatJSONAndTimestamp() async {
        let json = await run(FormatJSONPlugin(), #"{"a":1}"#)
        guard case .card(let jsonCard) = json else { return XCTFail("应该返回结果卡片") }
        XCTAssertTrue(jsonCard.monospaced)
        XCTAssertTrue(jsonCard.body.contains("\"a\""))

        let timestamp = await run(TimestampPlugin(), "1727510400")
        guard case .card(let timeCard) = timestamp else { return XCTFail("应该返回结果卡片") }
        XCTAssertEqual(timeCard.detail, "UTC 2024-09-28T08:00:00Z")
    }

    @MainActor
    func testFailureWhenContentDoesNotFit() async {
        let outcome = await run(CalculatorPlugin(), "not math")
        XCTAssertEqual(outcome, .failure("无法计算这个算式"))
    }
}
