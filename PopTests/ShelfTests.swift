import AppKit
import XCTest
@testable import Pop

final class ShakeTrackerTests: XCTestCase {
    /// 按固定的时间间隔送进一串位置，返回第几个位置时判定为晃动（没有则为 nil）
    private func shakeIndex(_ xs: [CGFloat], interval: TimeInterval = 0.04) -> Int? {
        var tracker = ShakeTracker()
        for (index, x) in xs.enumerated() {
            if tracker.add(x: x, time: Double(index) * interval) {
                return index
            }
        }
        return nil
    }

    func testDetectsQuickSwings() {
        // 右、左、右、左：第三次换方向时判定
        let xs: [CGFloat] = [0, 50, 100, 50, 0, 50, 100, 50, 0]
        XCTAssertEqual(shakeIndex(xs), 7)
    }

    func testIgnoresSmallJitterAndSlowMoves() {
        // 来回只动 10 点：手抖，不算
        XCTAssertNil(shakeIndex([0, 10, 0, 10, 0, 10, 0, 10, 0, 10]))
        // 幅度够，但太慢（每次隔 0.5 秒）
        XCTAssertNil(shakeIndex([0, 50, 100, 50, 0, 50, 100, 50, 0], interval: 0.5))
        // 一直往一个方向拖
        XCTAssertNil(shakeIndex(Array(stride(from: 0, to: 400, by: 20)).map { CGFloat($0) }))
    }
}

@MainActor
final class FileShelfTests: XCTestCase {
    func testAddRemoveAndPrune() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "pop-shelf-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = folder.appending(path: "a.txt")
        let second = folder.appending(path: "b.txt")
        try Data("a".utf8).write(to: first)
        try Data("b".utf8).write(to: second)

        let shelf = FileShelf()
        shelf.add([first, second, first, URL(string: "https://example.com")!])
        XCTAssertEqual(shelf.files.map(\.lastPathComponent), ["a.txt", "b.txt"])
        shelf.remove(shelf.files[0])
        XCTAssertEqual(shelf.files.map(\.lastPathComponent), ["b.txt"])
        // 文件被移走了就从架子上拿掉
        try FileManager.default.removeItem(at: second)
        shelf.pruneMissing()
        XCTAssertTrue(shelf.files.isEmpty)
        shelf.add([first])
        shelf.clear()
        XCTAssertTrue(shelf.files.isEmpty)
    }
}

final class OpenWithTests: XCTestCase {
    func testBrowsersForLinks() throws {
        let link = try XCTUnwrap(URL(string: "https://example.com"))
        let apps = OpenWith.applications(for: link)
        XCTAssertFalse(apps.isEmpty)
        XCTAssertTrue(apps.contains { Bundle(url: $0)?.bundleIdentifier == "com.apple.Safari" })
        // 同一个 App 不重复
        let ids = apps.compactMap { Bundle(url: $0)?.bundleIdentifier }
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertEqual(OpenWith.subject(of: [link]), "example.com")
        XCTAssertEqual(OpenWith.subject(of: [URL(fileURLWithPath: "/tmp/a.txt"), URL(fileURLWithPath: "/tmp/b.txt")]), "2 个文件")
    }

    @MainActor
    func testPluginOffersApps() async throws {
        let context = PluginContext(settings: AppSettings(), openSettings: {})
        let content = ContentClassifier.classify(.text("https://example.com/page"))
        XCTAssertTrue(OpenWithPlugin().info.canHandle(content))
        let outcome = await OpenWithPlugin().run(content, context: context)
        guard case .chooseApp(let request) = outcome else { return XCTFail("应该让用户选 App") }
        XCTAssertEqual(request.targets, [try XCTUnwrap(URL(string: "https://example.com/page"))])
        XCTAssertFalse(request.apps.isEmpty)
        XCTAssertFalse(OpenWithPlugin().info.canHandle(ContentClassifier.classify(.text("hello"))))
    }
}

final class EdgeFinderTests: XCTestCase {
    /// 20×10 的白图，中间 x 5–14、y 2–6 是一块黑色
    private func image() throws -> CGImage {
        var pixels: [UInt8] = []
        for y in 0..<10 {
            for x in 0..<20 {
                let inside = (5...14).contains(x) && (2...6).contains(y)
                let value: UInt8 = inside ? 0 : 255
                pixels += [value, value, value, 255]
            }
        }
        let provider = try XCTUnwrap(CGDataProvider(data: Data(pixels) as CFData))
        return try XCTUnwrap(CGImage(width: 20, height: 10, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 80,
                                     space: try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)),
                                     bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                     provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    }

    func testSpansStopAtEdges() throws {
        let finder = try XCTUnwrap(EdgeFinder(image: try image()))
        // 在黑块里：量出黑块的范围
        let inside = try XCTUnwrap(finder.span(atX: 8, y: 4))
        XCTAssertEqual(inside, EdgeFinder.Span(left: 5, right: 14, top: 2, bottom: 6))
        XCTAssertEqual(inside.width, 10)
        XCTAssertEqual(inside.height, 5)
        // 在左边的白色里：横着到黑块为止，竖着一直到图的上下边
        XCTAssertEqual(finder.span(atX: 1, y: 4), EdgeFinder.Span(left: 0, right: 4, top: 0, bottom: 9))
        XCTAssertNil(finder.span(atX: 20, y: 0))
    }
}
