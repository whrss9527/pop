import XCTest
@testable import Pop

final class QuitAppsTests: XCTestCase {
    private func entry(_ pid: pid_t, _ name: String, _ memory: UInt64?) -> RunningApps.Entry {
        RunningApps.Entry(pid: pid, name: name, bundleID: nil, memory: memory)
    }

    func testSortsByMemory() {
        let sorted = RunningApps.sorted([entry(1, "备忘录", 100), entry(2, "Xcode", 2_000), entry(3, "Mail", nil), entry(4, "Safari", 2_000),
                                         entry(5, "App Store", nil)])
        // 占得多的在前；一样多、读不到的按名字排
        XCTAssertEqual(sorted.map(\.pid), [4, 2, 1, 5, 3])
        XCTAssertEqual(RunningApps.total(sorted), 4_100)
        XCTAssertEqual(RunningApps.others(sorted, keeping: 2).map(\.pid), [4, 1, 5, 3])
        XCTAssertEqual(RunningApps.others(sorted, keeping: nil).count, 5)
    }

    func testSortsByCPUAndFormatsIt() {
        var xcode = entry(1, "Xcode", 2_000)
        xcode.cpu = 150
        var safari = entry(2, "Safari", 1_000)
        safari.cpu = 3
        let notes = entry(3, "备忘录", 500)
        var mail = entry(4, "Mail", 300)
        mail.cpu = 3
        // CPU 一样多时比内存；还没算出 CPU 的排在后面
        XCTAssertEqual(RunningApps.sorted([safari, notes, xcode, mail], by: .cpu).map(\.pid), [1, 2, 4, 3])
        XCTAssertEqual(RunningApps.sorted([safari, notes, xcode, mail], by: .memory).map(\.pid), [1, 2, 3, 4])

        XCTAssertEqual(RunningApps.formatCPU(0.01), "0%")
        XCTAssertEqual(RunningApps.formatCPU(0.3), "0.3%")
        XCTAssertEqual(RunningApps.formatCPU(9.5), "9.5%")
        XCTAssertEqual(RunningApps.formatCPU(186), "186%")
        XCTAssertEqual(RunningApps.cpuPercent(from: 1_000_000_000, to: 1_500_000_000, seconds: 2), 25, accuracy: 0.0001)
        // 子进程退出了、少了的算 0
        XCTAssertEqual(RunningApps.cpuPercent(from: 2_000, to: 1_000, seconds: 1), 0)
        XCTAssertEqual(RunningApps.cpuPercent(from: 1_000, to: 2_000, seconds: 0), 0)
        XCTAssertEqual(RunningApps.nanoseconds(3_000_000), 3_000_000 * RunningApps.timebase.numer / RunningApps.timebase.denom)
    }

    func testReadsCPUTimeOfProcesses() throws {
        let pid = ProcessInfo.processInfo.processIdentifier
        // 只比进程自己的：连子进程一起算的话，中间有子进程退出，总数会变少
        let before = try XCTUnwrap(RunningApps.ownCPUTime(of: pid))
        // 忙一会儿，用掉一点 CPU
        var value = 0.0
        let start = Date()
        while Date().timeIntervalSince(start) < 0.05 {
            value += sin(value) + 1
        }
        XCTAssertGreaterThan(value, 0)
        let after = try XCTUnwrap(RunningApps.ownCPUTime(of: pid))
        XCTAssertGreaterThan(after, before)
        // 连子进程一起算的不会比自己的少
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(RunningApps.cpuTime(of: pid)), after)
        XCTAssertNil(RunningApps.cpuTime(of: -1))
        XCTAssertEqual(RunningApps.tree(of: pid).first, pid)
    }

    @MainActor
    func testCardShowsCPUAndSortsByIt() {
        defer { UserDefaults.standard.removeObject(forKey: QuitAppsModel.sortKey) }
        let rows = [entry(1, "Xcode", 300), entry(2, "Safari", 200), entry(3, "备忘录", 100)].map { QuitAppsModel.Row(entry: $0, icon: nil) }
        let model = QuitAppsModel(rows: rows, front: nil, terminate: { _, _ in true }, isRunning: { _ in true }, sort: .cpu)
        // 还没算出 CPU：先按内存排
        XCTAssertEqual(model.rows.map(\.entry.pid), [1, 2, 3])
        let start = Date()
        model.apply([1: 1_000_000_000, 2: 1_000_000_000, 3: 1_000_000_000], at: start)
        XCTAssertNil(model.rows[0].entry.cpu)
        // 两秒里：备忘录用了 1 秒 CPU（50%），Safari 0.2 秒（10%），Xcode 没用；第一次算出来时按 CPU 排
        model.apply([1: 1_000_000_000, 2: 1_200_000_000, 3: 2_000_000_000], at: start.addingTimeInterval(2))
        XCTAssertEqual(model.rows.map(\.entry.pid), [3, 2, 1])
        XCTAssertEqual(model.rows[0].entry.cpu ?? -1, 50, accuracy: 0.0001)
        XCTAssertEqual(model.rows[1].entry.cpu ?? -1, 10, accuracy: 0.0001)
        XCTAssertEqual(model.rows[2].entry.cpu ?? -1, 0, accuracy: 0.0001)
        // 之后只换数字，不重新排
        model.apply([1: 3_000_000_000, 2: 1_200_000_000, 3: 2_000_000_000], at: start.addingTimeInterval(4))
        XCTAssertEqual(model.rows.map(\.entry.pid), [3, 2, 1])
        XCTAssertEqual(model.rows[2].entry.cpu ?? -1, 100, accuracy: 0.0001)
        // 换成按内存排，下次打开还记着
        model.sort = .memory
        XCTAssertEqual(model.rows.map(\.entry.pid), [1, 2, 3])
        XCTAssertEqual(UserDefaults.standard.string(forKey: QuitAppsModel.sortKey), "memory")
        XCTAssertEqual(QuitAppsModel(rows: rows, front: nil, terminate: { _, _ in true }, isRunning: { _ in true }).sort, .memory)
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
    func testRefusedQuitOffersForceQuit() {
        // 请它退出没能发出去，但还在运行：直接给出强制退出
        let model = QuitAppsModel(rows: [QuitAppsModel.Row(entry: entry(7, "预览", 50), icon: nil)], front: nil,
                                  terminate: { _, force in force }, isRunning: { _ in true })
        model.quit(7)
        XCTAssertEqual(model.rows.first?.state, .stuck)
        model.quit(7, force: true)
        XCTAssertEqual(model.rows.first?.state, .quitting)
    }

    @MainActor
    func testDemoRowsAndPlugin() {
        XCTAssertEqual(QuitAppsPlugin.demoRows().count, 6)
        XCTAssertEqual(QuitAppsPlugin.demoRows().first?.entry.cpu, 186)
        XCTAssertTrue(QuitAppsPlugin().info.canHandle(.empty))
    }
}
