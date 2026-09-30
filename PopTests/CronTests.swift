import XCTest
@testable import Pop

final class CronTests: XCTestCase {
    private func summary(_ text: String) -> String? {
        CronExpression(text)?.summary
    }

    func testSummaries() {
        XCTAssertEqual(summary("*/5 * * * *"), "每 5 分钟")
        XCTAssertEqual(summary("* * * * *"), "每分钟")
        XCTAssertEqual(summary("30 9 * * 1-5"), "每个工作日（周一到周五） 09:30")
        XCTAssertEqual(summary("0 0 1 * *"), "每月 1 日 00:00")
        XCTAssertEqual(summary("@yearly"), "1 月 1 日 00:00")
        XCTAssertEqual(summary("@hourly"), "每小时的整点")
        XCTAssertEqual(summary("0 9-18 * * *"), "每天 9 点到 18 点的整点")
        XCTAssertEqual(summary("0 12 * * SAT,SUN"), "每个周末 12:00")
        XCTAssertEqual(summary("15 10 * * MON-WED"), "每周一到周三 10:15")
        XCTAssertEqual(summary("0 8,12,18 * * *"), "每天 08:00、12:00、18:00")
        XCTAssertEqual(summary("*/15 9-17 * * 1-5"), "每个工作日（周一到周五） 9 点到 17 点每 15 分钟")
        XCTAssertEqual(summary("0 0 * * 7"), "每周日 00:00")
    }

    func testEnglishSummaries() {
        func english(_ text: String) -> String? { CronExpression(text)?.englishSummary }
        XCTAssertEqual(english("*/5 * * * *"), "every 5 minutes")
        XCTAssertEqual(english("30 9 * * 1-5"), "every weekday (Monday to Friday) at 09:30")
        XCTAssertEqual(english("0 0 1 * *"), "on day 1 of every month at 00:00")
        XCTAssertEqual(english("@yearly"), "on day 1 of January at 00:00")
        XCTAssertEqual(english("@hourly"), "every hour on the hour")
        XCTAssertEqual(english("0 9-18 * * *"), "every day on the hour during hours 9–18")
        XCTAssertEqual(english("0 12 * * SAT,SUN"), "every weekend day at 12:00")
        XCTAssertEqual(english("15 10 * * MON-WED"), "every Monday to Wednesday at 10:15")
        XCTAssertEqual(english("0 8,12,18 * * *"), "every day at 08:00, 12:00, 18:00")
    }

    func testInvalidExpressions() {
        XCTAssertNil(CronExpression("61 * * * *"))
        XCTAssertNil(CronExpression("* * *"))
        XCTAssertNil(CronExpression("a b c d e"))
        XCTAssertNil(CronExpression("*/0 * * * *"))
        XCTAssertNil(CronExpression("5-1 * * * *"))
        XCTAssertNil(CronExpression("hello world"))
    }

    func testNextRuns() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        // 2026-09-26 是周六
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 26, hour: 12)))
        let cron = try XCTUnwrap(CronExpression("30 9 * * 1-5"))
        let runs = cron.nextRuns(after: start, count: 3, calendar: calendar)
        let days = runs.map { calendar.dateComponents([.day, .hour, .minute], from: $0) }
        XCTAssertEqual(days.map(\.day), [28, 29, 30])
        XCTAssertEqual(days.map(\.hour), [9, 9, 9])
        XCTAssertEqual(days.map(\.minute), [30, 30, 30])
        XCTAssertTrue(runs.allSatisfy { cron.matches($0, calendar: calendar) })
        // 二月二十九日：往后找到闰年
        let leap = try XCTUnwrap(CronExpression("0 0 29 2 *")).nextRuns(after: start, count: 1, calendar: calendar)
        XCTAssertEqual(leap.first.map { calendar.component(.year, from: $0) }, 2028)
    }

    func testRingShowsItOnlyForCron() {
        let info = CronPlugin().info
        XCTAssertTrue(info.canHandle(ContentClassifier.classify(.text("*/15 9-17 * * 1-5"))))
        XCTAssertTrue(info.canHandle(ContentClassifier.classify(.text("0 0 * * 0"))))
        XCTAssertFalse(info.canHandle(ContentClassifier.classify(.text("hello world"))))
    }
}

final class ColorContrastTests: XCTestCase {
    func testRatiosAndVerdicts() throws {
        let black = try XCTUnwrap(ColorValue.parse("#000000"))
        let white = try XCTUnwrap(ColorValue.parse("#FFFFFF"))
        let gray = try XCTUnwrap(ColorValue.parse("#777777"))
        XCTAssertEqual(ColorContrast.ratio(black, white), 21, accuracy: 0.001)
        XCTAssertEqual(ColorContrast.format(ColorContrast.ratio(gray, white)), "4.47 : 1")
        // 普通文字不够 4.5，大号文字够 3
        XCTAssertEqual(ColorContrast.rows(gray, white).map(\.value),
                       ["4.47 : 1", "AA 不通过 · AAA 不通过", "AA 通过 · AAA 不通过"])
        XCTAssertEqual(ColorContrast.summary(for: black), "对白色 21.00 : 1，对黑色 1.00 : 1")
    }

    func testFindingPairs() {
        XCTAssertEqual(ColorContrast.pair(in: "#333333 on #FFFFFF")?.background.hexString, "#FFFFFF")
        XCTAssertTrue(ColorContrast.isColorPair("rgb(0, 0, 0), #fff"))
        XCTAssertFalse(ColorContrast.isColorPair("#333333"))
        XCTAssertFalse(ColorContrast.isColorPair("#111111 #222222 #333333"))
        XCTAssertFalse(ColorContrast.isColorPair("the button uses #333333 text on a #ffffff background everywhere"))
        // 两个颜色不算外文，不会被直接拿去翻译
        let content = ContentClassifier.classify(.text("#333333 #FFFFFF"))
        XCTAssertFalse(content.kinds.contains(.foreignText))
        XCTAssertTrue(ContrastPlugin().info.canHandle(content))
    }
}

/// 假的网络：按「方法 网址」或者「网址」返回状态码和响应头，不真的访问网络
final class RedirectMock: URLProtocol {
    static var routes: [String: (status: Int, headers: [String: String])] = [:]

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let key = "\(request.httpMethod ?? "GET") \(url.absoluteString)"
        let route = Self.routes[key] ?? Self.routes[url.absoluteString] ?? (status: 404, headers: [:])
        if let response = HTTPURLResponse(url: url, statusCode: route.status, httpVersion: "HTTP/1.1", headerFields: route.headers) {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class LinkExpanderTests: XCTestCase {
    private var session: URLSession!

    override func setUp() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RedirectMock.self]
        session = URLSession(configuration: configuration)
    }

    override func tearDown() {
        RedirectMock.routes = [:]
    }

    func testShortLinkHosts() throws {
        XCTAssertTrue(LinkExpander.isShortLink(try XCTUnwrap(URL(string: "https://t.cn/A6abc"))))
        XCTAssertTrue(LinkExpander.isShortLink(try XCTUnwrap(URL(string: "http://www.bit.ly/x"))))
        XCTAssertFalse(LinkExpander.isShortLink(try XCTUnwrap(URL(string: "https://example.com/t.cn"))))
    }

    func testFollowsRedirectsAndCleansTheResult() async throws {
        RedirectMock.routes = [
            "https://t.cn/abc": (301, ["Location": "https://example.com/go"]),
            // 这一跳不接受 HEAD，换 GET
            "HEAD https://example.com/go": (405, [:]),
            "GET https://example.com/go": (302, ["Location": "/page?id=7&utm_source=share"]),
            "https://example.com/page?id=7&utm_source=share": (200, [:]),
        ]
        let start = try XCTUnwrap(URL(string: "https://t.cn/abc"))
        let expansion = try await LinkExpander.expand(start, session: session)
        XCTAssertEqual(expansion.hops.map(\.absoluteString),
                       ["https://example.com/go", "https://example.com/page?id=7&utm_source=share"])
        let card = LinkExpander.card(for: expansion)
        XCTAssertEqual(card.body, "https://example.com/page?id=7")
        XCTAssertEqual(card.detail, "跳转了 2 次，已去掉跟踪参数")
    }

    func testStopsLoopingRedirects() async throws {
        RedirectMock.routes = [
            "https://t.cn/a": (301, ["Location": "https://t.cn/b"]),
            "https://t.cn/b": (301, ["Location": "https://t.cn/a"]),
        ]
        do {
            _ = try await LinkExpander.expand(try XCTUnwrap(URL(string: "https://t.cn/a")), session: session, limit: 5)
            XCTFail("应该因为跳转太多而停下")
        } catch {
            XCTAssertEqual(LinkExpander.describe(error), "跳转次数太多")
        }
    }

    @MainActor
    func testInspectCardOffersExpansionOnlyForShortLinks() async {
        let context = PluginContext(settings: AppSettings(), openSettings: {})
        let short = await LinkInspectPlugin().run(ContentClassifier.classify(.text("https://t.cn/abc")), context: context)
        guard case .card(let card) = short else { return XCTFail("应该返回结果卡片") }
        XCTAssertEqual(card.buttons.first?.title, "展开短链接")
        let normal = await LinkInspectPlugin().run(ContentClassifier.classify(.text("https://example.com/a")), context: context)
        guard case .card(let plain) = normal else { return XCTFail("应该返回结果卡片") }
        XCTAssertFalse(plain.buttons.contains { $0.title == "展开短链接" })
    }
}
