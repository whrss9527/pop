import XCTest
@testable import Pop

final class OnDeviceAITests: XCTestCase {
    private func settings(provider: AIProvider, configured: Bool) -> AISettings {
        var ai = AISettings()
        ai.provider = provider
        if configured {
            ai.baseURL = "https://example.com/v1"
            ai.model = "m"
        }
        return ai
    }

    /// 选了系统内置：能用就用；用不了时改用填好的接口，接口也没填就提示
    func testOnDeviceFallsBackToTheCustomInterface() {
        XCTAssertEqual(AIService.backend(for: settings(provider: .onDevice, configured: false), onDevice: .available), .onDevice)
        XCTAssertEqual(AIService.backend(for: settings(provider: .onDevice, configured: true), onDevice: .available), .onDevice)
        XCTAssertEqual(AIService.backend(for: settings(provider: .onDevice, configured: true), onDevice: .unsupported), .custom)
        XCTAssertEqual(AIService.backend(for: settings(provider: .onDevice, configured: true), onDevice: .unavailable("没打开")), .custom)
        XCTAssertEqual(AIService.backend(for: settings(provider: .onDevice, configured: false), onDevice: .unsupported), AIService.Backend.unavailable)
    }

    /// 选了自己的接口：只用接口，不会因为系统模型能用就换过去
    func testCustomNeverSwitchesToOnDevice() {
        XCTAssertEqual(AIService.backend(for: settings(provider: .custom, configured: true), onDevice: .available), .custom)
        XCTAssertEqual(AIService.backend(for: settings(provider: .custom, configured: false), onDevice: .available), AIService.Backend.unavailable)
    }

    func testMessagesExplainWhatToDo() {
        let off = AIService.unavailableMessage(for: settings(provider: .onDevice, configured: false), onDevice: .unavailable("要先打开 Apple 智能"))
        XCTAssertTrue(off.contains("要先打开 Apple 智能"), off)
        XCTAssertTrue(AIService.unavailableMessage(for: settings(provider: .onDevice, configured: false), onDevice: .unsupported)
            .contains("设置 → AI"))
        XCTAssertTrue(AIService.unavailableMessage(for: settings(provider: .custom, configured: false), onDevice: .available)
            .contains("设置 → AI"))
    }

    /// 新装默认用系统内置；以前填过接口的设置升级后继续用接口；选了什么就存什么
    func testProviderDefaultsAndMigration() throws {
        XCTAssertEqual(AISettings().provider, .onDevice)
        let fresh = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(fresh.ai.provider, .onDevice)
        let upgraded = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"ai": {"baseURL": "https://example.com/v1", "model": "m"}}"#.utf8))
        XCTAssertEqual(upgraded.ai.provider, .custom)
        let half = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"ai": {"baseURL": "https://example.com/v1"}}"#.utf8))
        XCTAssertEqual(half.ai.provider, .onDevice, "只填了一半不算填过")
        var chosen = AppSettings()
        chosen.ai = settings(provider: .onDevice, configured: true)
        XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(chosen)).ai.provider, .onDevice)
    }

    /// 系统模型能处理的内容短：指令在前，选中的文字只取前面一部分，并且记下截断了
    func testPromptIsTruncated() {
        let short = OnDeviceModel.prompt(from: [.system("你是助手"), .user("总结\n\nabc")], limit: 100)
        XCTAssertEqual(short.text, "你是助手\n\n总结\n\nabc")
        XCTAssertFalse(short.truncated)
        let long = OnDeviceModel.prompt(from: [.system("你是助手"), .user(String(repeating: "字", count: 50))], limit: 10)
        XCTAssertEqual(long.text, "你是助手\n\n" + String(repeating: "字", count: 10))
        XCTAssertTrue(long.truncated)
    }

    /// 测试机上没有系统模型（或者用不了）时，AI 卡片照旧提示去设置
    @MainActor
    func testCardUsesTheFallbackMessage() {
        let model = AIChatModel(source: "hello", settings: AppSettings(), keyProvider: { nil }, onDeviceStatus: { .unsupported })
        XCTAssertFalse(model.isConfigured)
        model.run(.polish)
        guard case .failed(let message) = model.phase else { return XCTFail("应该提示") }
        XCTAssertTrue(message.contains("设置 → AI"), message)

        let waiting = AIChatModel(source: "hello", settings: AppSettings(), keyProvider: { nil },
                                  onDeviceStatus: { .unavailable("系统模型还在下载，稍后再试") })
        waiting.run(.summarize)
        guard case .failed(let reason) = waiting.phase else { return XCTFail("应该提示") }
        XCTAssertTrue(reason.contains("还在下载"), reason)
    }
}
