import XCTest
@testable import Pop

@MainActor
final class HeadlessRunnerTests: XCTestCase {
    private func services(ready: Set<TranslationEngine> = [.ai], reply: String = "你好") -> TranslationServices {
        TranslationServices(
            unavailableReason: { engine in ready.contains(engine) || engine == .system ? nil : "先设置好\(engine.longTitle)" },
            translate: { engine, _, target in
                AsyncThrowingStream { continuation in
                    continuation.yield("\(reply)（\(engine.title)→\(target)）")
                    continuation.finish()
                }
            },
            checkSystem: { _, _, _ in .needsDownload }
        )
    }

    func testTextFunctions() {
        let registry = PluginRegistry()
        let ids = Set(HeadlessRunner.textFunctions(in: registry.catalog).map(\.id))
        XCTAssertTrue(ids.contains(BuiltinPluginID.translate))
        XCTAssertTrue(ids.contains(BuiltinPluginID.calculate))
        XCTAssertTrue(ids.contains(BuiltinPluginID.textStats))
        // 只处理文件的、不用选中内容的、打开列表的不算
        XCTAssertFalse(ids.contains(BuiltinPluginID.revealInFinder))
        XCTAssertFalse(ids.contains(BuiltinPluginID.settings))
        XCTAssertFalse(ids.contains(BuiltinPluginID.allPlugins))
    }

    func testRunsFunctionsAndReturnsText() async {
        let registry = PluginRegistry()
        let settings = AppSettings()
        let sum = await HeadlessRunner.run(pluginID: BuiltinPluginID.calculate, text: "1+2*3", registry: registry,
                                           settings: settings, services: services())
        XCTAssertEqual(sum, .success("7"))

        // 每一行「名称：值」
        guard case .success(let stats) = await HeadlessRunner.run(pluginID: BuiltinPluginID.textStats, text: "Hello world",
                                                                   registry: registry, settings: settings, services: services()) else {
            return XCTFail("字数统计应该有结果")
        }
        XCTAssertTrue(stats.contains("："), stats)

        let unknown = await HeadlessRunner.run(pluginID: "nothing", text: "hi", registry: registry, settings: settings, services: services())
        XCTAssertEqual(unknown, .failure(HeadlessRunner.Failure("没有「nothing」这个功能")))
        let unfit = await HeadlessRunner.run(pluginID: BuiltinPluginID.calculate, text: "hello", registry: registry,
                                             settings: settings, services: services())
        XCTAssertEqual(unfit, .failure(HeadlessRunner.Failure("「计算」处理不了这段文字")))
    }

    func testTranslation() async {
        var settings = AppSettings()
        settings.translation.foreignTarget = "zh-Hans"
        settings.translation.chineseTarget = "ja"

        // 默认的系统翻译在快捷指令里用不了
        let system = await HeadlessRunner.translate("Hello", language: nil, settings: settings, services: services())
        guard case .failure(let failure) = system else { return XCTFail("系统翻译应该提示换引擎") }
        XCTAssertTrue(failure.message.contains("AI 或 DeepL"), failure.message)

        // 选了 AI：按原文选目标语言
        let english = await HeadlessRunner.translate("Hello", language: nil, settings: settings, services: services(), engine: .ai)
        XCTAssertEqual(english, .success("你好（AI→zh-Hans）"))
        let chinese = await HeadlessRunner.translate("你好", language: nil, settings: settings, services: services(), engine: .ai)
        XCTAssertEqual(chinese, .success("你好（AI→ja）"))
        let chosen = await HeadlessRunner.translate("Hello", language: nil, settings: settings, services: services(), engine: .ai,
                                                    target: "ko")
        XCTAssertEqual(chosen, .success("你好（AI→ko）"))

        // DeepL 没填 Key
        let deepL = await HeadlessRunner.translate("Hello", language: nil, settings: settings, services: services(), engine: .deepL)
        XCTAssertEqual(deepL, .failure(HeadlessRunner.Failure("先设置好DeepL")))

        // 默认引擎改成 AI 后，「翻译」功能也能在快捷指令里用
        settings.translation.engine = .ai
        let viaPlugin = await HeadlessRunner.run(pluginID: BuiltinPluginID.translate, text: "Good morning", registry: PluginRegistry(),
                                                 settings: settings, services: services())
        XCTAssertEqual(viaPlugin, .success("你好（AI→zh-Hans）"))
    }

    func testCardText() {
        XCTAssertEqual(HeadlessRunner.text(of: ResultCard(title: "标题", body: "正文", copyText: "复制的")), "复制的")
        XCTAssertEqual(HeadlessRunner.text(of: ResultCard(title: "标题", body: "正文")), "正文")
        XCTAssertEqual(HeadlessRunner.text(of: ResultCard(title: "标题", tabs: [ResultCard.Tab(title: "Swift", text: "struct A {}")])),
                       "struct A {}")
        XCTAssertEqual(HeadlessRunner.text(of: ResultCard(title: "标题", rows: [ResultCard.Row(label: "字符", value: "5"),
                                                                                 ResultCard.Row(label: "行", value: "1")])),
                       "字符：5\n行：1")
        XCTAssertEqual(HeadlessRunner.text(of: ResultCard(title: "标题", detail: "说明")), "说明")
        XCTAssertEqual(HeadlessRunner.text(of: ResultCard(title: "标题")), "标题")
    }

    func testAIWithoutAnInstruction() async {
        let open = await HeadlessRunner.ai(AIRequestSpec(text: "hi"), name: "AI 助手", settings: AppSettings())
        guard case .failure(let failure) = open else { return XCTFail("没有指令时应该提示去 AI 卡片") }
        XCTAssertTrue(failure.message.contains("AI 卡片"), failure.message)
    }

    func testAIActionMessagesMatchTheCard() {
        var translation = TranslationSettings()
        translation.foreignTarget = "zh-Hans"
        translation.chineseTarget = "en"
        let messages = AIPrompt.messages(for: .translate, text: "你好", translation: translation)
        XCTAssertEqual(messages.first?.content, AIPrompt.system)
        XCTAssertTrue(messages.last?.content.contains("English") == true, messages.last?.content ?? "")
        XCTAssertTrue(messages.last?.content.hasSuffix("你好") == true)
    }
}
