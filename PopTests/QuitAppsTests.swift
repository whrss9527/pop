import XCTest
@testable import Pop

final class QuitAppsTests: XCTestCase {
    private func entry(_ pid: pid_t, _ name: String, _ memory: UInt64?) -> RunningApps.Entry {
        RunningApps.Entry(pid: pid, name: name, bundleID: nil, memory: memory)
    }

    func testSortsByMemory() {
        let sorted = RunningApps.sorted([entry(1, "备忘录", 100), entry(2, "Xcode", 2_000), entry(3, "邮件", nil), entry(4, "Safari", 2_000),
                                         entry(5, "App Store", nil)])
        // 占得多的在前；一样多、读不到的按名字排
        XCTAssertEqual(sorted.map(\.pid), [4, 2, 1, 5, 3])
        XCTAssertEqual(RunningApps.total(sorted), 4_100)
        XCTAssertEqual(RunningApps.others(sorted, keeping: 2).map(\.pid), [4, 1, 5, 3])
        XCTAssertEqual(RunningApps.others(sorted, keeping: nil).count, 5)
    }

    func testReadsMemoryOfProcesses() throws {
        // 自己这个进程一定读得到
        let own = try XCTUnwrap(RunningApps.memory(of: ProcessInfo.processInfo.processIdentifier))
        XCTAssertGreaterThan(own, 1_000_000)
        XCTAssertNil(RunningApps.memory(of: -1))
        XCTAssertFalse(RunningApps.format(1_240_000_000).isEmpty)
    }

    @MainActor
    func testQuitRemovesTheRowOnceTheAppIsGone() async throws {
        var running: Set<pid_t> = [1, 2, 3]
        var requests: [(pid_t, Bool)] = []
        let rows = [entry(1, "Xcode", 300), entry(2, "Safari", 200), entry(3, "备忘录", 100)].map { QuitAppsModel.Row(entry: $0, icon: nil) }
        let model = QuitAppsModel(rows: rows, front: 2, terminate: { pid, force in
            requests.append((pid, force))
            return running.contains(pid)
        }, isRunning: { running.contains($0) })
        model.patience = .milliseconds(600)
        XCTAssertEqual(model.summary, "正在运行 3 个 App，一共占用 \(RunningApps.format(600)) 内存")
        XCTAssertEqual(model.frontName, "Safari")

        model.quit(1)
        XCTAssertEqual(model.rows.first?.state, .quitting)
        running.remove(1)
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(model.rows.map(\.entry.pid), [2, 3])

        // 一直没退出：标成卡住了，再强制退出
        model.quit(3)
        try await Task.sleep(for: .milliseconds(900))
        XCTAssertEqual(model.rows.last?.state, .stuck)
        model.quit(3, force: true)
        XCTAssertEqual(requests.map(\.0), [1, 3, 3])
        XCTAssertEqual(requests.map(\.1), [false, false, true])

        // 已经退出了的直接拿掉
        running.remove(3)
        model.quit(3)
        XCTAssertEqual(model.rows.map(\.entry.pid), [2])
    }

    @MainActor
    func testQuitOthersKeepsTheCurrentApp() {
        var asked: [pid_t] = []
        let rows = [entry(1, "Xcode", 300), entry(2, "Safari", 200), entry(3, "备忘录", 100)].map { QuitAppsModel.Row(entry: $0, icon: nil) }
        let model = QuitAppsModel(rows: rows, front: 2, terminate: { pid, _ in asked.append(pid); return true }, isRunning: { _ in true })
        XCTAssertEqual(model.others.map(\.entry.pid), [1, 3])
        model.confirmingOthers = true
        model.quitOthers()
        XCTAssertFalse(model.confirmingOthers)
        XCTAssertEqual(asked, [1, 3])
        XCTAssertEqual(model.rows.map(\.state), [.quitting, .running, .quitting])
    }

    @MainActor
    func testDemoRowsAndPlugin() {
        XCTAssertEqual(QuitAppsPlugin.demoRows().count, 6)
        XCTAssertTrue(QuitAppsPlugin().info.canHandle(.empty))
    }
}
