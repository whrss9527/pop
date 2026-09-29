import XCTest
@testable import Pop

/// 假的 AI 服务：把设好的状态码、类型和内容原样返回，不联网。
final class MockAIServer: URLProtocol {
    static var statusCode = 200
    static var contentType = "text/event-stream"
    static var body = Data()
    static var lastRequest: URLRequest?

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockAIServer.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        let response = HTTPURLResponse(url: request.url ?? URL(fileURLWithPath: "/"), statusCode: Self.statusCode,
                                       httpVersion: "HTTP/1.1", headerFields: ["Content-Type": Self.contentType])
        if let response {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        }
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class AIClientTests: XCTestCase {
    private let configuration = AIClient.Configuration(baseURL: "https://example.com/v1", apiKey: "sk-test", model: "test-model")

    func testEndpoint() {
        XCTAssertEqual(AIClient.endpoint("https://api.example.com/v1")?.absoluteString, "https://api.example.com/v1/chat/completions")
        XCTAssertEqual(AIClient.endpoint(" https://api.example.com/v1/ ")?.absoluteString, "https://api.example.com/v1/chat/completions")
        XCTAssertEqual(AIClient.endpoint("http://localhost:11434/v1/chat/completions")?.absoluteString,
                       "http://localhost:11434/v1/chat/completions")
        XCTAssertNil(AIClient.endpoint("ftp://example.com/v1"))
        XCTAssertNil(AIClient.endpoint("not a url"))
        XCTAssertNil(AIClient.endpoint(""))
    }

    func testRequest() throws {
        let request = try AIClient.makeRequest(configuration, messages: [.system("s"), .user("你好")])
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://example.com/v1/chat/completions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, "test-model")
        XCTAssertEqual(body["stream"] as? Bool, true)
        let messages = try XCTUnwrap(body["messages"] as? [[String: String]])
        XCTAssertEqual(messages.map { $0["role"] }, ["system", "user"])
        XCTAssertEqual(messages.last?["content"], "你好")

        // 本机的服务可以不填 API Key
        var local = configuration
        local.apiKey = "  "
        XCTAssertNil(try AIClient.makeRequest(local, messages: [.user("hi")]).value(forHTTPHeaderField: "Authorization"))
        // 没填模型或地址
        var missing = configuration
        missing.model = ""
        XCTAssertThrowsError(try AIClient.makeRequest(missing, messages: [])) { error in
            XCTAssertEqual(error as? AIClient.Failure, .notConfigured)
        }
        var invalid = configuration
        invalid.baseURL = "example.com/v1"
        XCTAssertThrowsError(try AIClient.makeRequest(invalid, messages: [])) { error in
            XCTAssertEqual(error as? AIClient.Failure, .invalidURL)
        }
    }

    func testParsing() {
        XCTAssertEqual(AIClient.parseStreamLine(#"data: {"choices":[{"delta":{"content":"Hi"}}]}"#), .delta("Hi"))
        XCTAssertEqual(AIClient.parseStreamLine(#"data:{"choices":[{"delta":{"content":"你"}}]}"#), .delta("你"))
        XCTAssertEqual(AIClient.parseStreamLine("data: [DONE]"), .done)
        XCTAssertNil(AIClient.parseStreamLine(#"data: {"choices":[{"delta":{"role":"assistant"}}]}"#))
        XCTAssertNil(AIClient.parseStreamLine(": keep-alive"))
        XCTAssertNil(AIClient.parseStreamLine(""))
        XCTAssertEqual(AIClient.parseCompletion(Data(#"{"choices":[{"message":{"content":"Hello"}}]}"#.utf8)), "Hello")
        XCTAssertNil(AIClient.parseCompletion(Data("{}".utf8)))
        XCTAssertEqual(AIClient.errorMessage(from: Data(#"{"error":{"message":"Invalid API key"}}"#.utf8)), "Invalid API key")
        XCTAssertEqual(AIClient.errorMessage(from: Data(" Bad Gateway \n".utf8)), "Bad Gateway")
        XCTAssertTrue(AIClient.describe(AIClient.Failure.http(status: 401, message: "Invalid API key")).contains("API Key"))
    }

    func testStreamingResponse() async throws {
        MockAIServer.statusCode = 200
        MockAIServer.contentType = "text/event-stream; charset=utf-8"
        MockAIServer.body = Data("""
        data: {"choices":[{"delta":{"role":"assistant"}}]}

        data: {"choices":[{"delta":{"content":"你"}}]}

        data: {"choices":[{"delta":{"content":"好"}}]}

        data: [DONE]


        """.utf8)
        let reply = try await AIClient.complete(configuration, messages: [.user("hi")], session: MockAIServer.session())
        XCTAssertEqual(reply, "你好")
        XCTAssertEqual(MockAIServer.lastRequest?.url?.path, "/v1/chat/completions")
    }

    func testNonStreamingResponse() async throws {
        MockAIServer.statusCode = 200
        MockAIServer.contentType = "application/json"
        MockAIServer.body = Data(#"{"choices":[{"message":{"role":"assistant","content":"整段回答"}}]}"#.utf8)
        let reply = try await AIClient.complete(configuration, messages: [.user("hi")], session: MockAIServer.session())
        XCTAssertEqual(reply, "整段回答")
    }

    func testHTTPErrorCarriesTheServerMessage() async {
        MockAIServer.statusCode = 401
        MockAIServer.contentType = "application/json"
        MockAIServer.body = Data(#"{"error":{"message":"Invalid API key"}}"#.utf8)
        do {
            _ = try await AIClient.complete(configuration, messages: [.user("hi")], session: MockAIServer.session())
            XCTFail("应该失败")
        } catch {
            XCTAssertEqual(error as? AIClient.Failure, .http(status: 401, message: "Invalid API key"))
        }
    }
}

final class AIAssistantTests: XCTestCase {
    func testPrompts() {
        XCTAssertEqual(AIPrompt.expand("改写：{text}", text: "abc"), "改写：abc")
        XCTAssertEqual(AIPrompt.expand("  总结一下  ", text: "abc"), "总结一下\n\nabc")
        XCTAssertEqual(AIPrompt.expand("", text: "abc"), "abc")
        let messages = AIPrompt.messages(instruction: "解释", text: "abc")
        XCTAssertEqual(messages.first?.role, "system")
        XCTAssertEqual(messages.last?.content, "解释\n\nabc")
        XCTAssertTrue(AIAction.translate.instruction(answerLanguage: "简体中文", translationTarget: "English").contains("English"))
        XCTAssertTrue(AIAction.summarize.instruction(answerLanguage: "简体中文", translationTarget: "English").contains("简体中文"))
    }

    @MainActor
    func testUnconfiguredModelExplainsWhatToDo() {
        let model = AIChatModel(source: "hello", settings: AppSettings(), keyProvider: { nil })
        XCTAssertFalse(model.isConfigured)
        model.run(.polish)
        guard case .failed(let message) = model.phase else { return XCTFail("没设置接口时应该提示") }
        XCTAssertTrue(message.contains("设置 → AI"))
        XCTAssertEqual(model.label, "润色")
        XCTAssertEqual(model.activeAction, .polish)
    }

    @MainActor
    func testPluginsHandOffToTheCard() async {
        let context = PluginContext(settings: AppSettings(), openSettings: {})
        let content = ContentClassifier.classify(.text("Some text"))
        let polish = await AIPlugin.all[1].run(content, context: context)
        XCTAssertEqual(polish, .ai(AIRequestSpec(text: "Some text", action: .polish)))
        let assistant = await AIPlugin.all[0].run(content, context: context)
        XCTAssertEqual(assistant, .ai(AIRequestSpec(text: "Some text")))
    }

    func testAISettingsAndOptInPlugins() throws {
        let settings = AppSettings()
        XCTAssertFalse(settings.ai.isConfigured)
        XCTAssertTrue(settings.isInstalled(BuiltinPluginID.aiAssistant))
        XCTAssertFalse(settings.isInstalled(BuiltinPluginID.aiPolish))

        // 升级上来的设置：AI 助手自动装上，几个快捷功能默认不装
        let upgraded = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"installedPlugins": ["translate"], "knownBuiltinPlugins": ["translate"], "ai": {"baseURL": "https://example.com/v1", "model": "m", "unknown": 1}}"#.utf8))
        XCTAssertTrue(upgraded.isInstalled(BuiltinPluginID.aiAssistant))
        XCTAssertFalse(upgraded.isInstalled(BuiltinPluginID.aiSummarize))
        XCTAssertTrue(upgraded.knownBuiltinPlugins.contains(BuiltinPluginID.aiSummarize))
        XCTAssertTrue(upgraded.ai.isConfigured)
        XCTAssertEqual(upgraded.ai.model, "m")
    }

    @MainActor
    func testAIManifestPlugins() async throws {
        var manifest = PluginManifest(name: "正式一点", action: .init(type: .ai, prompt: "  改写：{text}  "), output: .card)
        XCTAssertNil(manifest.validationError())
        manifest = manifest.normalized()
        XCTAssertEqual(manifest.action.prompt, "改写：{text}")

        let data = try PluginManifest.makeEncoder().encode(manifest)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains("\"prompt\""))
        XCTAssertFalse(json.contains("\"script\""))
        XCTAssertEqual(try PluginManifest.makeDecoder().decode(PluginManifest.self, from: data), manifest)

        // 结果显示在卡片里：交给 AI 卡片一边生成一边显示
        let outcome = await ManifestRunner.run(manifest, content: ContentClassifier.classify(.text("hi there")))
        XCTAssertEqual(outcome, .ai(AIRequestSpec(text: "hi there", prompt: "改写：hi there", label: "正式一点")))

        // 没设置接口时，要复制或替换结果的插件给出提示
        manifest.output = .copy
        let failed = await ManifestRunner.run(manifest, content: ContentClassifier.classify(.text("hi there")))
        guard case .failure(let message) = failed else { return XCTFail("应该提示去设置 AI 接口") }
        XCTAssertTrue(message.contains("设置 → AI"))

        var empty = PluginManifest(name: "空的", action: .init(type: .ai, prompt: " "))
        XCTAssertEqual(empty.validationError(), "请填写给 AI 的指令")
        empty.action.prompt = "x"
        XCTAssertNil(empty.validationError())
    }
}
