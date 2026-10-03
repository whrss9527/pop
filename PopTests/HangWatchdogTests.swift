import XCTest
@testable import Pop

@MainActor
final class HangWatchdogTests: XCTestCase {
    /// 主线程卡了 0.5 秒：记下一行「hang 开始的时间戳 卡了几秒」，秒数差不多是 0.5
    func testRecordsAStalledMainThread() async throws {
        let path = FileManager.default.temporaryDirectory.appending(path: "pop-hangs-\(UUID().uuidString).log").path(percentEncoded: false)
        addTeardownBlock { try? FileManager.default.removeItem(atPath: path) }
        let watchdog = HangWatchdog(path: path)
        watchdog.start()
        defer { watchdog.stop() }
        try await Task.sleep(for: .milliseconds(200))

        let stalledAt = Date().timeIntervalSince1970
        blockMainThread(for: 0.5)
        // 主线程空下来以后，检测的线程才知道刚才等了多久
        try await Task.sleep(for: .milliseconds(300))

        let lines = try String(contentsOfFile: path, encoding: .utf8).split(separator: "\n").map { $0.split(separator: " ") }
        let hangs = lines.filter { $0.count == 3 && $0[0] == "hang" }
        XCTAssertEqual(hangs.count, lines.count)
        let longest = try XCTUnwrap(hangs.max { (Double($0[2]) ?? 0) < (Double($1[2]) ?? 0) })
        XCTAssertGreaterThanOrEqual(Double(longest[2]) ?? 0, 0.4)
        XCTAssertLessThan(Double(longest[2]) ?? 0, 1.5)
        // 开始的时间是卡住之前不久发出去的那个空任务的时间
        XCTAssertEqual(Double(longest[1]) ?? 0, stalledAt, accuracy: 0.2)
    }

    /// 同步地卡住主线程（在 async 的测试里不能直接调用 Thread.sleep）
    private func blockMainThread(for seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    func testLinesAreAppended() throws {
        let path = FileManager.default.temporaryDirectory.appending(path: "pop-lines-\(UUID().uuidString).log").path(percentEncoded: false)
        addTeardownBlock { try? FileManager.default.removeItem(atPath: path) }
        LineLog.append("ring 1.0 6", to: path)
        LineLog.append("hang 1.2 0.300", to: path)
        XCTAssertEqual(try String(contentsOfFile: path, encoding: .utf8), "ring 1.0 6\nhang 1.2 0.300\n")
    }

    func testOnlyRunsWhenAsked() {
        // 平时（没有演示日志、没有 POP_HANG_LOG）不开
        XCTAssertNil(HangWatchdog.requestedPath(environment: [:]))
        XCTAssertNil(HangWatchdog.requestedPath(environment: ["POP_DEMO_LOG": "/tmp/demo.log"]))
        XCTAssertEqual(HangWatchdog.requestedPath(environment: ["POP_DEMO": "1", "POP_DEMO_LOG": "/tmp/demo.log"]), "/tmp/demo.log")
        XCTAssertEqual(HangWatchdog.requestedPath(environment: ["POP_HANG_LOG": "/tmp/hangs.log"]), "/tmp/hangs.log")
        XCTAssertNil(HangWatchdog.requestedPath(environment: ["POP_HANG_LOG": ""]))
    }
}
