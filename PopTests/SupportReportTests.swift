import Foundation
import XCTest
@testable import Pop

final class SupportReportTests: XCTestCase {
    private func report(channel: String = "GitHub") -> SupportReport {
        SupportReport(version: "0.71.0-beta.1", build: "123", channel: channel,
                      system: "26.0.1", chip: "Apple Silicon", accessibility: true, screenRecording: false)
    }

    func testFeedbackPrefillsOnlyVersionFieldAndPreservesEncoding() throws {
        let url = try XCTUnwrap(URLComponents(url: report(channel: "App Store").feedbackURL, resolvingAgainstBaseURL: false))
        XCTAssertEqual(url.host, "github.com")
        XCTAssertEqual(url.path, "/whrss9527/pop/issues/new")
        let fields = Dictionary(uniqueKeysWithValues: try XCTUnwrap(url.queryItems).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(fields.count, 2)
        XCTAssertEqual(fields["template"], "bug.yml")
        XCTAssertEqual(fields["version"], "Pop 0.71.0-beta.1 (123), App Store, macOS 26.0.1")
    }

    func testReportIncludesPermissionsAndOnlyLast200Lines() {
        let text = report().text(logs: (0..<205).map { "event-\($0);" }, logsAvailable: true)
        for field in ["0.71.0-beta.1", "123", "GitHub", "26.0.1", "Apple Silicon", "Accessibility: granted", "Screen Recording: missing", "event-5;", "event-204;"] {
            XCTAssertTrue(text.contains(field), field)
        }
        XCTAssertFalse(text.contains("event-4;"))
        XCTAssertFalse(text.contains("event-0;"))
    }

    func testUnavailableAndEmptyLogsAreExplicit() {
        XCTAssertTrue(report().text(logs: [], logsAvailable: false).contains("Logs unavailable."))
        XCTAssertTrue(report().text(logs: [], logsAvailable: true).contains("No available entries."))
    }

    func testOnlyKnownNumericOrFixedLogMessagesAreIncluded() {
        for message in ["唤起：按下点 -12, 50", "loaded 5 plugins in 12.5 ms", "Pop 已启动，版本 0.71.0-beta.1", "鼠标手势取消：收起圆盘，不执行当前指向的功能"] {
            XCTAssertEqual(SupportReport.safeLogMessage(message), message)
        }
    }

    func testUnknownMessagesAndSensitiveValuesCannotEscapeAllowlist() {
        for message in [
            "apiKey=sk-secret", "Authorization: Bearer secret", "password=hunter2",
            "could not install plugin test: https://user:pass@example.com/?token=secret",
            "/Users/alice/private.txt", "clipboard: private selected text",
            "Pop 已启动，版本 secret", "唤起：按下点 1, 2\napiKey=secret",
            "loaded 2 plugins in 1 ms\n", String(repeating: "x", count: 10000)
        ] {
            XCTAssertEqual(SupportReport.safeLogMessage(message), "[content hidden]", message)
        }
    }
}
