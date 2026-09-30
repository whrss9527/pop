import XCTest
@testable import Pop

/// 假的 DeepL：按设好的状态码和内容回复，不联网。
final class MockDeepL: URLProtocol {
    static var status = 200
    static var body = Data()
    static var lastURL: URL?

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockDeepL.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastURL = request.url
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: Self.status, httpVersion: "HTTP/1.1",
                                             headerFields: ["Content-Type": "application/json"]) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class DeepLClientTests: XCTestCase {
    func testTargetCodes() {
        XCTAssertEqual(DeepLClient.targetCode(for: "zh-Hans"), "ZH-HANS")
        XCTAssertEqual(DeepLClient.targetCode(for: "zh-Hant"), "ZH-HANT")
        XCTAssertEqual(DeepLClient.targetCode(for: "en"), "EN-US")
        XCTAssertEqual(DeepLClient.targetCode(for: "pt"), "PT-BR")
        XCTAssertEqual(DeepLClient.targetCode(for: "ja"), "JA")
        XCTAssertEqual(DeepLClient.targetCode(for: "ko"), "KO")
        XCTAssertEqual(DeepLClient.targetCode(for: "de-AT"), "DE")
        XCTAssertNil(DeepLClient.targetCode(for: "xx"))
        // 设置里能选的目标语言 DeepL 都能译
        for option in LanguageOption.translationTargets {
            XCTAssertNotNil(DeepLClient.targetCode(for: option.id), option.id)
        }
    }

    func testRequest() throws {
        let request = try DeepLClient.makeRequest(text: "Hello", target: "zh-Hans", key: " abc-123:fx ")
        XCTAssertEqual(request.url?.absoluteString, "https://api-free.deepl.com/v2/translate")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "DeepL-Auth-Key abc-123:fx")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(body["text"] as? [String], ["Hello"])
        XCTAssertEqual(body["target_lang"] as? String, "ZH-HANS")
        XCTAssertNil(body["source_lang"])

        // 付费版的 Key 走 api.deepl.com
        XCTAssertEqual(try DeepLClient.makeRequest(text: "Hi", target: "ja", key: "pro-key").url?.host, "api.deepl.com")
        // 没填 Key、译不成的语言
        XCTAssertThrowsError(try DeepLClient.makeRequest(text: "Hi", target: "ja", key: "  "))
        XCTAssertThrowsError(try DeepLClient.makeRequest(text: "Hi", target: "xx", key: "k"))
    }

    func testParseAndErrors() {
        XCTAssertEqual(DeepLClient.parse(Data(#"{"translations":[{"detected_source_language":"EN","text":"你好"}]}"#.utf8)), "你好")
        XCTAssertNil(DeepLClient.parse(Data(#"{"translations":[]}"#.utf8)))
        XCTAssertNil(DeepLClient.parse(Data("not json".utf8)))

        XCTAssertTrue(DeepLClient.describe(status: 403, data: Data()).contains("API Key 不对"))
        XCTAssertTrue(DeepLClient.describe(status: 456, data: Data()).contains("额度"))
        XCTAssertTrue(DeepLClient.describe(status: 429, data: Data()).contains("频繁"))
        XCTAssertTrue(DeepLClient.describe(status: 503, data: Data()).contains("503"))
        XCTAssertEqual(DeepLClient.describe(status: 400, data: Data(#"{"message":"Value for 'target_lang' not supported."}"#.utf8)),
                       "DeepL 返回了错误：Value for 'target_lang' not supported.")
        XCTAssertEqual(DeepLClient.describe(status: 400, data: Data()), "DeepL 返回了错误（400）")
    }

    func testTranslate() async throws {
        MockDeepL.status = 200
        MockDeepL.body = Data(#"{"translations":[{"detected_source_language":"EN","text":"你好，世界"}]}"#.utf8)
        let translated = try await DeepLClient.translate("Hello, world", to: "zh-Hans", key: "k:fx", session: MockDeepL.session())
        XCTAssertEqual(translated, "你好，世界")
        XCTAssertEqual(MockDeepL.lastURL?.host, "api-free.deepl.com")

        MockDeepL.status = 456
        MockDeepL.body = Data()
        do {
            _ = try await DeepLClient.translate("Hello", to: "zh-Hans", key: "k", session: MockDeepL.session())
            XCTFail("额度用完时应该报错")
        } catch {
            XCTAssertEqual((error as? DeepLClient.Failure)?.message, "DeepL 这个月的字数额度用完了")
        }
    }

    func testAIPrompt() {
        let messages = AITranslation.messages(for: "Hello\n\nWorld", target: "ja")
        XCTAssertEqual(messages.map(\.role), ["system", "user"])
        XCTAssertTrue(messages[0].content.contains("日本語"), messages[0].content)
        XCTAssertTrue(messages[0].content.contains("只输出译文"))
        XCTAssertEqual(messages[1].content, "Hello\n\nWorld")
    }

    func testEngineSetting() throws {
        XCTAssertEqual(TranslationSettings().engine, .system)
        let old = try JSONDecoder().decode(TranslationSettings.self, from: Data(#"{"foreignTarget":"ja","chineseTarget":"en"}"#.utf8))
        XCTAssertEqual(old.engine, .system)
        XCTAssertEqual(old.foreignTarget, "ja")
        let deepL = try JSONDecoder().decode(TranslationSettings.self, from: Data(#"{"engine":"deepL"}"#.utf8))
        XCTAssertEqual(deepL.engine, .deepL)
        // 新版本才有的引擎：回到系统翻译
        let future = try JSONDecoder().decode(TranslationSettings.self, from: Data(#"{"engine":"someday"}"#.utf8))
        XCTAssertEqual(future.engine, .system)
        var settings = AppSettings()
        settings.translation.engine = .ai
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(decoded.translation.engine, .ai)
    }
}

@MainActor
final class TranslationModelTests: XCTestCase {
    /// 记下联网引擎收到的请求
    private final class Calls {
        var requests: [(engine: TranslationEngine, target: String)] = []
    }

    private func services(_ calls: Calls, deepLReady: Bool = false, system: SystemTranslationStatus = .needsDownload,
                          reply: @escaping (TranslationEngine, String) throws -> [String] = { engine, target in ["\(engine.title)", "→\(target)"] })
        -> TranslationServices {
        TranslationServices(
            unavailableReason: { engine in
                engine == .deepL && !deepLReady ? "先填上 DeepL 的 API Key" : nil
            },
            translate: { engine, _, target in
                calls.requests.append((engine, target))
                let pieces = try reply(engine, target)
                return AsyncThrowingStream { continuation in
                    for piece in pieces {
                        continuation.yield(piece)
                    }
                    continuation.finish()
                }
            },
            checkSystem: { _, _, _ in system }
        )
    }

    func testSingleEngineStreamsAndFinishes() async {
        let calls = Calls()
        let model = TranslationModel(text: "Hello", sourceLanguage: "en", targetLanguage: "zh-Hans", engine: .ai, services: services(calls))
        XCTAssertEqual(model.mode, .single(.ai))
        model.start()
        XCTAssertEqual(model.phase, .translating)
        await model.waitUntilFinished()
        XCTAssertEqual(model.phase, .done("AI→zh-Hans"))
        XCTAssertEqual(model.translatedText, "AI→zh-Hans")
        XCTAssertEqual(calls.requests.map(\.engine), [.ai])
        // 再触发一次不会重复翻译
        model.start()
        await model.waitUntilFinished()
        XCTAssertEqual(calls.requests.count, 1)
    }

    func testCompareRunsEveryEngineOnce() async {
        let calls = Calls()
        let model = TranslationModel(text: "Hello", sourceLanguage: "en", targetLanguage: "zh-Hans", engine: .ai, services: services(calls))
        model.start()
        await model.waitUntilFinished()

        model.switchMode(to: .compare)
        XCTAssertNil(model.engine)
        XCTAssertNil(model.translatedText)
        await model.waitUntilFinished()
        // AI 已经翻译过，不再请求；DeepL 没填 Key；系统翻译要先下载语言包
        XCTAssertEqual(calls.requests.map(\.engine), [.ai])
        XCTAssertEqual(model.phase(of: .ai), .done("AI→zh-Hans"))
        XCTAssertEqual(model.phase(of: .deepL), .unavailable("先填上 DeepL 的 API Key"))
        XCTAssertEqual(model.phase(of: .system), .needsDownload)
        XCTAssertNil(model.configuration)

        // 换目标语言：清空重来，每个能用的引擎按新的语言再翻一次
        model.switchTarget(to: "ja")
        await model.waitUntilFinished()
        XCTAssertEqual(calls.requests.map(\.target), ["zh-Hans", "ja"])
        XCTAssertEqual(model.phase(of: .ai), .done("AI→ja"))

        // 换回单个引擎，直接显示已经有的结果
        model.switchMode(to: .single(.ai))
        XCTAssertEqual(model.translatedText, "AI→ja")
        XCTAssertEqual(calls.requests.count, 2)
    }

    func testSystemEngineWaitsForTheCard() async {
        let model = TranslationModel(text: "Hello", sourceLanguage: "en", targetLanguage: "zh-Hans",
                                     services: services(Calls(), system: .installed))
        model.start()
        await model.waitUntilFinished()
        // 语言包装好了：把会话配置交给卡片上的 .translationTask
        XCTAssertEqual(model.phase, .translating)
        XCTAssertNotNil(model.configuration)

        let unsupported = TranslationModel(text: "Hello", sourceLanguage: "en", targetLanguage: "zh-Hans",
                                           services: services(Calls(), system: .unsupported))
        unsupported.start()
        await unsupported.waitUntilFinished()
        XCTAssertEqual(unsupported.phase, .failed("系统翻译暂不支持「English → 简体中文」"))
    }

    func testUnavailableDefaultFallsBackToSystem() {
        let model = TranslationModel(text: "Hello", sourceLanguage: "en", targetLanguage: "zh-Hans", engine: .deepL,
                                     services: services(Calls()))
        XCTAssertEqual(model.mode, .single(.system))
        let ready = TranslationModel(text: "Hello", sourceLanguage: "en", targetLanguage: "zh-Hans", engine: .deepL,
                                     services: services(Calls(), deepLReady: true))
        XCTAssertEqual(ready.mode, .single(.deepL))
    }

    func testFailures() async {
        let failing = services(Calls(), deepLReady: true) { engine, _ in
            if engine == .deepL {
                throw DeepLClient.Failure("DeepL 这个月的字数额度用完了")
            }
            return ["  "]
        }
        let model = TranslationModel(text: "Hello", sourceLanguage: "en", targetLanguage: "zh-Hans", engine: .deepL, services: failing)
        model.start()
        await model.waitUntilFinished()
        XCTAssertEqual(model.phase, .failed("DeepL 这个月的字数额度用完了"))
        XCTAssertNil(model.translatedText)

        // 只回了空白
        model.switchMode(to: .single(.ai))
        await model.waitUntilFinished()
        XCTAssertEqual(model.phase, .failed("AI 没有返回译文"))
    }
}
