import AppKit
import XCTest
@testable import Pop

/// 在后台暂停一次读取，随后继续使用生产读取；不接触通用粘贴板。
private final class HeldClipboardRead: @unchecked Sendable {
    let started = XCTestExpectation(description: "isolated clipboard read started")
    private let resume = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var calls = 0
    private let first: ClipboardMonitor.Clip

    init(_ first: ClipboardMonitor.Clip) { self.first = first }
    func release() { resume.signal() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return calls }
    func read(_ board: NSPasteboard, _ images: Bool) -> ClipboardMonitor.Clip? {
        lock.lock(); calls += 1; let firstCall = calls == 1; lock.unlock()
        guard firstCall else { return ClipboardMonitor.read(board, recordImages: images) }
        started.fulfill()
        resume.wait()
        return first
    }
}

@MainActor
private final class ClipboardMonitorFixture {
    let directory: URL
    let board: NSPasteboard
    let store: ClipboardStore
    let queue = DispatchQueue(label: "pop.clipboard-monitor-fixture")
    let guardState = PasteboardGuard()
    let monitor: ClipboardMonitor
    var settings = ClipboardSettings()
    var records = 0

    init(reader: ClipboardMonitor.Reader? = nil) {
        directory = FileManager.default.temporaryDirectory.appending(path: "pop-monitor-\(UUID())")
        board = NSPasteboard(name: .init("pop-monitor-\(UUID())"))
        store = ClipboardStore(directory: directory)
        monitor = ClipboardMonitor(store: store, pasteboard: board, pasteboardGuard: guardState,
                                   sourceApp: { "org.example.clipboard-fixture" }, workQueue: queue,
                                   pollsAutomatically: false, reader: reader)
        settings.searchImageText = false
        monitor.onRecord = { [weak self] in self?.records += 1 }
    }

    func start(cleanLinks: Bool = false) {
        settings.cleanLinks = cleanLinks
        monitor.apply(settings)
    }
    func copy(_ text: String) {
        board.clearContents()
        board.setString(text, forType: .string)
    }
    func close() {
        settings.enabled = false
        settings.cleanLinks = false
        monitor.apply(settings)
        board.releaseGlobally()
        try? FileManager.default.removeItem(at: directory)
    }
    func finish() async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while monitor.isReading {
            if ContinuousClock.now >= deadline { throw NSError(domain: "ClipboardMonitorFixture", code: 1) }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        await withCheckedContinuation { continuation in queue.async { continuation.resume() } }
    }
}

final class ClipboardMonitorTests: XCTestCase {
    @MainActor
    func testNewCopySurvivesAnOlderReadAndIsRecordedNormally() async throws {
        let first = "https://example.com/path?utm_source=fixture"
        let held = HeldClipboardRead(.text(first))
        let f = ClipboardMonitorFixture(reader: { held.read($0, $1) })
        defer { f.close(); held.release() }
        f.start(cleanLinks: true)
        f.copy(first)
        f.monitor.poll()
        let started = await XCTWaiter.fulfillment(of: [held.started], timeout: 3)
        XCTAssertEqual(started, .completed)
        f.copy("new fixture copy")
        held.release()
        try await f.finish()
        XCTAssertEqual(f.board.string(forType: .string), "new fixture copy")
        XCTAssertTrue(f.store.items().isEmpty)
        f.monitor.poll()
        try await f.finish()
        XCTAssertEqual(f.store.items().map(\.text), ["new fixture copy"])
        XCTAssertEqual(f.records, 1)
    }

    @MainActor
    func testDisablingHistoryKeepsCleanerOnlyModeAndIgnoresItsOwnWrite() async throws {
        let first = "https://example.com/path?utm_source=old"
        let held = HeldClipboardRead(.text(first))
        let f = ClipboardMonitorFixture(reader: { held.read($0, $1) })
        defer { f.close(); held.release() }
        f.start(cleanLinks: true)
        f.copy(first)
        f.monitor.poll()
        let started = await XCTWaiter.fulfillment(of: [held.started], timeout: 3)
        XCTAssertEqual(started, .completed)
        f.settings.enabled = false
        f.monitor.apply(f.settings)
        held.release()
        try await f.finish()
        XCTAssertEqual(f.board.string(forType: .string), first)
        XCTAssertTrue(f.store.items().isEmpty)
        f.copy("https://example.com/path?utm_source=new")
        f.monitor.poll()
        try await f.finish()
        XCTAssertEqual(f.board.string(forType: .string), "https://example.com/path")
        XCTAssertTrue(f.store.items().isEmpty)
        f.monitor.poll()
        XCTAssertEqual(held.count, 2)
        XCTAssertEqual(f.records, 0)
    }

    @MainActor
    func testStopAndRestartCannotReviveOldWork() async throws {
        let held = HeldClipboardRead(.text("old fixture"))
        let f = ClipboardMonitorFixture(reader: { held.read($0, $1) })
        defer { f.close(); held.release() }
        f.start()
        f.copy("old fixture")
        f.monitor.poll()
        let started = await XCTWaiter.fulfillment(of: [held.started], timeout: 3)
        XCTAssertEqual(started, .completed)
        f.settings.enabled = false
        f.monitor.apply(f.settings)
        f.settings.enabled = true
        f.monitor.apply(f.settings)
        held.release()
        try await f.finish()
        XCTAssertTrue(f.store.items().isEmpty)
        f.copy("restarted fixture")
        f.monitor.poll()
        try await f.finish()
        XCTAssertEqual(f.store.items().map(\.text), ["restarted fixture"])
    }

    @MainActor
    func testChangedCapturePoliciesInvalidatePendingReads() async throws {
        for policy in 0..<3 {
            let held = HeldClipboardRead(.text("policy fixture"))
            let f = ClipboardMonitorFixture(reader: { held.read($0, $1) })
            defer { f.close(); held.release() }
            f.start(cleanLinks: true)
            f.copy("policy fixture")
            f.monitor.poll()
            let started = await XCTWaiter.fulfillment(of: [held.started], timeout: 3)
        XCTAssertEqual(started, .completed)
            if policy == 0 { f.settings.cleanLinks = false }
            else if policy == 1 { f.settings.recordImages = false }
            else { f.settings.ignoredBundleIDs.append("org.example.clipboard-fixture") }
            f.monitor.apply(f.settings)
            held.release()
            try await f.finish()
            XCTAssertTrue(f.store.items().isEmpty)
            XCTAssertEqual(f.records, 0)
        }
    }

    @MainActor
    func testCurrentSensitiveTypesAndPasteboardGuardAreRechecked() async throws {
        for guarded in [false, true] {
            let held = HeldClipboardRead(.text("filtered fixture"))
            let f = ClipboardMonitorFixture(reader: { held.read($0, $1) })
            defer { f.close(); held.release() }
            f.start()
            f.copy("filtered fixture")
            if !guarded {
                // 后台依赖返回旧内容，最终元数据仍必须拒绝当前敏感类型。
                let item = NSPasteboardItem()
                XCTAssertTrue(item.setString("filtered fixture", forType: .string))
                XCTAssertTrue(item.setData(Data(), forType: ClipboardMonitor.ignoredTypes[0]))
                f.board.clearContents()
                XCTAssertTrue(f.board.writeObjects([item]))
                XCTAssertTrue(f.board.types?.contains(ClipboardMonitor.ignoredTypes[0]) == true)
            }
            f.monitor.poll()
            let started = await XCTWaiter.fulfillment(of: [held.started], timeout: 3)
        XCTAssertEqual(started, .completed)
            if guarded { f.guardState.begin() }
            held.release()
            try await f.finish()
            if guarded { f.guardState.end(changeCount: f.board.changeCount) }
            XCTAssertTrue(f.store.items().isEmpty)
            XCTAssertEqual(f.records, 0)
        }
    }

    @MainActor
    func testNormalCleanedCopyUsesTheProductionReaderAndRecordsOnce() async throws {
        let f = ClipboardMonitorFixture()
        defer { f.close() }
        f.start(cleanLinks: true)
        f.copy("https://example.com/path?utm_source=fixture")
        f.monitor.poll()
        try await f.finish()
        XCTAssertEqual(f.board.string(forType: .string), "https://example.com/path")
        XCTAssertEqual(f.store.items().map(\.text), ["https://example.com/path"])
        f.monitor.poll()
        XCTAssertFalse(f.monitor.isReading)
        XCTAssertEqual(f.records, 1)
    }

    func testStorageAdmissionCanRejectInsertImageAndDuplicateUpdates() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "pop-store-admission-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ClipboardStore(directory: directory)
        let capture = ClipboardCapture(kind: .text, text: "accepted fixture", sourceApp: nil)
        let first = Date(timeIntervalSince1970: 1_000)
        let id = try XCTUnwrap(store.add(capture, at: first))
        XCTAssertNil(store.add(capture, at: first + 10, shouldRecord: { false }))
        XCTAssertEqual(store.item(id: id)?.usedAt, first)
        XCTAssertNil(store.add(ClipboardCapture(kind: .text, text: "rejected fixture"), shouldRecord: { false }))
        XCTAssertNil(store.add(ClipboardCapture(kind: .image, text: "", imagePNG: Data([1, 2, 3])), shouldRecord: { false }))
        XCTAssertEqual(store.items().count, 1)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: store.imagesDirectory.path).count, 0)
    }
}
