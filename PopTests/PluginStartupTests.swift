import AppKit
import XCTest
@testable import Pop

final class PluginStartupTests: XCTestCase {
    final class CheckState: @unchecked Sendable {
        private let lock = NSLock()
        private var checks = 0
        private var onMain = false
        func record() { lock.lock(); checks += 1; onMain = Thread.isMainThread; lock.unlock() }
        var snapshot: (Int, Bool) { lock.lock(); defer { lock.unlock() }; return (checks, onMain) }
    }

    @MainActor
    func testConcurrentStartupWaitsForBackgroundChecksAndYieldsBetweenLoads() async {
        let loader = PluginBundles()
        let urls = (0..<4).map { (url: URL(fileURLWithPath: "/fake/\($0).bundle"), external: true) }
        let checks = CheckState()
        let started = expectation(description: "签名检查开始")
        let gate = DispatchSemaphore(value: 0)
        var loaded: [URL] = []
        var heartbeats = 0
        let first = Task { @MainActor in
            await loader.loadInstalled(urls: urls, checkSignatures: { paths in
                checks.record()
                started.fulfill()
                _ = gate.wait(timeout: .now() + 2)
                return Dictionary(uniqueKeysWithValues: paths.map { ($0, true) })
            }, loadBundle: { url, external in
                XCTAssertTrue(Thread.isMainThread)
                XCTAssertTrue(external)
                XCTAssertEqual(heartbeats, loaded.count)
                loaded.append(url)
                DispatchQueue.main.async { heartbeats += 1 }
            })
        }
        // 签名检查被阻塞时主线程仍须能运行这个用例，不能同步等它。
        await fulfillment(of: [started], timeout: 1)
        XCTAssertEqual(checks.snapshot.0, 1)
        XCTAssertFalse(checks.snapshot.1)
        XCTAssertTrue(loaded.isEmpty)
        let second = Task { @MainActor in
            await loader.loadInstalled(urls: [], checkSignatures: { _ in
                XCTFail("重复检查")
                return [:]
            })
        }
        gate.signal()
        await first.value
        await second.value
        XCTAssertEqual(loaded, urls.map(\.url))
        XCTAssertEqual(heartbeats, urls.count)
        await loader.loadInstalled(urls: [], checkSignatures: { _ in XCTFail("完成后重复装载"); return [:] })
        XCTAssertEqual(checks.snapshot.0, 1)
    }

    @MainActor
    func testAsynchronousStartupStillRejectsUntrustedBundle() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let bundle = directory.appendingPathComponent("Unsigned.bundle")
        let contents = bundle.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let info = ["PopPluginID": "unsigned", "PopBuildID": PluginBundles.appBuildID]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        let loader = PluginBundles()
        await loader.loadInstalled(urls: [(bundle, false)], checkSignatures: { _ in [bundle: false] })
        XCTAssertTrue(loader.loaded.isEmpty)
        XCTAssertEqual(loader.failures[bundle], .untrusted)
    }
}
