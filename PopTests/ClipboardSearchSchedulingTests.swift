import AppKit
import XCTest
@testable import Pop

/// 故意不响应取消的等待器：确认旧等待结束后仍不会发起查询。
@MainActor
private final class HeldClipboardSearchDelay {
    private var pending: [CheckedContinuation<Void, Never>] = []
    var count: Int { pending.count }

    func wait() async {
        await withCheckedContinuation { pending.append($0) }
    }

    func releaseAll() {
        let continuations = pending
        pending.removeAll()
        for continuation in continuations { continuation.resume() }
    }
}

@MainActor
final class ClipboardSearchSchedulingTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "pop-search-\(UUID())")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !condition() {
            guard ContinuousClock.now < deadline else {
                XCTFail("搜索调度未在期限内完成")
                throw NSError(domain: "ClipboardSearchSchedulingTests", code: 1)
            }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    func testContinuousInputOnlySearchesTheLastQuery() async throws {
        let store = ClipboardStore(directory: directory)
        store.add(ClipboardCapture(kind: .text, text: "第二条"))
        store.add(ClipboardCapture(kind: .text, text: "第一条"))
        let service = ClipboardService(store: store)
        let delay = HeldClipboardSearchDelay()
        defer { delay.releaseAll() }
        var queries: [String] = []
        var finishedWaits = 0
        let model = ClipboardHistoryModel(service: service, searchItems: {
            queries.append($0)
            return await service.searchItems(matching: $0)
        }, waitForSearch: {
            await delay.wait()
            finishedWaits += 1
        })
        model.query = "第"
        try await waitUntil { delay.count == 1 }
        model.query = "第二"
        try await waitUntil { delay.count == 2 }
        XCTAssertTrue(queries.isEmpty, "等待期间不能把每个字都提交到数据库")
        delay.releaseAll()
        try await waitUntil { finishedWaits == 2 && model.items.map(\.text) == ["第二条"] }
        XCTAssertEqual(queries, ["第二"])
    }

    func testClearingAndHistoryChangesRefreshWithoutWaitingForTyping() async throws {
        let store = ClipboardStore(directory: directory)
        store.add(ClipboardCapture(kind: .text, text: "现有记录"))
        let service = ClipboardService(store: store)
        let delay = HeldClipboardSearchDelay()
        defer { delay.releaseAll() }
        var queries: [String] = []
        let model = ClipboardHistoryModel(service: service, searchItems: {
            queries.append($0)
            return await service.searchItems(matching: $0)
        }, waitForSearch: { await delay.wait() })
        model.query = "不存在"
        try await waitUntil { delay.count == 1 }
        model.query = ""
        try await waitUntil { queries == [""] }
        XCTAssertEqual(delay.count, 1, "清空不再增加防抖等待")
        store.add(ClipboardCapture(kind: .text, text: "新记录"))
        service.changes.send()
        try await waitUntil { model.items.count == 2 }
        XCTAssertEqual(queries, ["", ""])
        XCTAssertEqual(delay.count, 1, "历史变动不再增加防抖等待")
        delay.releaseAll()
    }

    func testReleasedModelDoesNotStartItsPendingSearch() async throws {
        let service = ClipboardService(store: ClipboardStore(directory: directory))
        let delay = HeldClipboardSearchDelay()
        defer { delay.releaseAll() }
        var finishedWait = false
        var model: ClipboardHistoryModel? = ClipboardHistoryModel(service: service, searchItems: { _ in
            XCTFail("关闭面板后不能发起等待中的搜索")
            return []
        }, waitForSearch: {
            await delay.wait()
            finishedWait = true
        })
        weak var released = model
        model?.query = "待取消"
        try await waitUntil { delay.count == 1 }
        model = nil
        XCTAssertNil(released, "防抖任务不能持有已经关闭的面板")
        delay.releaseAll()
        try await waitUntil { finishedWait }
    }

    func testOlderResultCannotReplaceTheLatestResultEvenWhenQueryMatchesAgain() async throws {
        let store = ClipboardStore(directory: directory)
        store.add(ClipboardCapture(kind: .text, text: "目标一"))
        let service = ClipboardService(store: store)
        let held = HeldClipboardSearchDelay()
        defer { held.releaseAll() }
        var calls = 0
        var oldFinished = false
        let model = ClipboardHistoryModel(service: service, searchItems: { query in
            calls += 1
            let isFirst = calls == 1
            let results = await service.searchItems(matching: query)
            if isFirst {
                await held.wait()
                oldFinished = true
            }
            return results
        }, waitForSearch: {})
        model.query = "目标"
        try await waitUntil { held.count == 1 }
        store.add(ClipboardCapture(kind: .text, text: "目标二"))
        model.query = "其他"
        model.query = "目标"
        try await waitUntil { model.items.count == 2 }
        held.releaseAll()
        try await waitUntil { oldFinished }
        XCTAssertEqual(Set(model.items.map(\.text)), ["目标一", "目标二"])
    }

    func testCancelledQueuedSearchLeavesTheLatestReadAndWritesUsable() async throws {
        let queue = DispatchQueue(label: "pop-search-queued-fixture")
        let store = ClipboardStore(directory: directory, workQueue: queue)
        store.add(ClipboardCapture(kind: .text, text: "目标记录"))
        let blocked = expectation(description: "数据库队列已暂停")
        let release = DispatchSemaphore(value: 0)
        queue.async { blocked.fulfill(); release.wait() }
        defer { release.signal() }
        await fulfillment(of: [blocked], timeout: 5)
        let started = expectation(description: "旧搜索任务已开始")
        let old = Task {
            started.fulfill()
            return await store.searchItems(matching: "目标")
        }
        await fulfillment(of: [started], timeout: 5)
        old.cancel()
        let current = Task { await store.searchItems(matching: "目标") }
        release.signal()
        let cancelled = await old.value
        let latest = await current.value
        XCTAssertTrue(cancelled.isEmpty)
        XCTAssertEqual(latest.map(\.text), ["目标记录"])
        XCTAssertNotNil(store.add(ClipboardCapture(kind: .text, text: "之后的写入")))
        XCTAssertEqual(store.items().count, 2)
    }
}
