import AppKit
import SQLite3
import XCTest
@testable import Pop

final class ClipboardStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "pop-clipboard-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func text(_ value: String, source: String? = nil) -> ClipboardCapture {
        ClipboardCapture(kind: .text, text: value, sourceApp: source)
    }

    func testAddDeduplicateAndSearch() throws {
        let store = ClipboardStore(directory: directory)
        XCTAssertTrue(store.isAvailable)
        XCTAssertNil(store.openError)
        let start = Date(timeIntervalSince1970: 1_000_000)

        let first = try XCTUnwrap(store.add(text("hello world", source: "com.apple.TextEdit"), at: start))
        let second = try XCTUnwrap(store.add(text("second"), at: start + 10))
        XCTAssertNotEqual(first, second)

        // 同样的内容再复制一次：不新增，只把它挪到最前面，来源保持原来的
        XCTAssertEqual(store.add(text("hello world"), at: start + 20), first)
        let items = store.items()
        XCTAssertEqual(items.map(\.text), ["hello world", "second"])
        XCTAssertEqual(items.first?.sourceApp, "com.apple.TextEdit")
        XCTAssertEqual(items.first?.createdAt, start)
        XCTAssertEqual(items.first?.usedAt, start + 20)

        XCTAssertEqual(store.items(matching: "WORLD").map(\.text), ["hello world"])
        XCTAssertEqual(store.items(matching: "100%").count, 0)
        XCTAssertEqual(store.items(limit: 1).count, 1)
        XCTAssertEqual(store.statistics().count, 2)
        XCTAssertEqual(store.statistics().bytes, "hello world".utf8.count + "second".utf8.count)

        // 重新打开数据库，记录还在
        XCTAssertEqual(ClipboardStore(directory: directory).items().map(\.id), items.map(\.id))
    }

    func testCleanupKeepsPinnedItems() throws {
        let store = ClipboardStore(directory: directory)
        let start = Date(timeIntervalSince1970: 2_000_000)
        for index in 0..<5 {
            store.add(text("item \(index)"), at: start + Double(index))
        }
        let oldest = try XCTUnwrap(store.items().last)
        XCTAssertEqual(oldest.text, "item 0")
        store.setPinned(true, id: oldest.id)

        // 最多保留 2 条（固定的不算）
        XCTAssertEqual(store.cleanup(retentionDays: 0, maxItems: 2, now: start + 10), 2)
        XCTAssertEqual(store.items().map(\.text), ["item 0", "item 4", "item 3"])

        // 超过 1 天的删掉，固定的保留
        XCTAssertEqual(store.cleanup(retentionDays: 1, maxItems: 100, now: start + 2 * 86_400), 2)
        XCTAssertEqual(store.items().map(\.text), ["item 0"])

        store.clear(keepPinned: true)
        XCTAssertEqual(store.items().map(\.text), ["item 0"])
        store.clear(keepPinned: false)
        XCTAssertTrue(store.items().isEmpty)
    }

    func testImagesAndFiles() throws {
        let store = ClipboardStore(directory: directory)
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3])
        let imageID = try XCTUnwrap(store.add(ClipboardCapture(kind: .image, text: "", imagePNG: png, sourceApp: nil)))
        let image = try XCTUnwrap(store.item(id: imageID))
        let imageURL = try XCTUnwrap(store.imageURL(for: image))
        XCTAssertEqual(try Data(contentsOf: imageURL), png)
        XCTAssertEqual(image.byteSize, png.count)
        // 同一张图不会存两份
        XCTAssertEqual(store.add(ClipboardCapture(kind: .image, text: "", imagePNG: png, sourceApp: nil)), imageID)
        let imageFiles = try FileManager.default.contentsOfDirectory(atPath: store.imagesDirectory.path(percentEncoded: false))
        XCTAssertEqual(imageFiles.count, 1)

        store.delete(id: imageID)
        XCTAssertNil(store.item(id: imageID))
        XCTAssertFalse(FileManager.default.fileExists(atPath: imageURL.path(percentEncoded: false)))

        let files = ClipboardMonitor.capture(.files([URL(fileURLWithPath: "/tmp/a.txt"), URL(fileURLWithPath: "/tmp/b c.txt")]), sourceApp: nil)
        XCTAssertEqual(files?.text, "/tmp/a.txt\n/tmp/b c.txt")
        let fileID = try XCTUnwrap(store.add(try XCTUnwrap(files)))
        XCTAssertEqual(store.item(id: fileID)?.fileURLs.map(\.lastPathComponent), ["a.txt", "b c.txt"])
    }

    func testSkipsTwoFactorLinks() {
        // 两步验证的链接里写着密钥：剪贴板历史不记
        XCTAssertTrue(ClipboardMonitor.containsSecretLink("扫到的 OTPAUTH://totp/a?secret=JBSWY3DPEHPK3PXP"))
        XCTAssertTrue(ClipboardMonitor.containsSecretLink("otpauth-migration://offline?data=abc"))
        XCTAssertFalse(ClipboardMonitor.containsSecretLink("https://example.com/otpauth"))
    }

    func testCaptureHashDistinguishesKinds() {
        let asText = ClipboardCapture(kind: .text, text: "/tmp/a", sourceApp: nil)
        let asFiles = ClipboardCapture(kind: .files, text: "/tmp/a", sourceApp: nil)
        XCTAssertNotEqual(asText.hash, asFiles.hash)
        XCTAssertEqual(asText.hash, ClipboardCapture(kind: .text, text: "/tmp/a", sourceApp: "other").hash)
        XCTAssertEqual(ClipboardStore.escapeLike("50%_\\"), "50\\%\\_\\\\")
    }

    func testImagesAreFoundByTheirText() throws {
        let store = ClipboardStore(directory: directory)
        let png = try XCTUnwrap(Self.renderText("HELLO POP 2026"))
        let id = try XCTUnwrap(store.add(ClipboardCapture(kind: .image, text: "", imagePNG: png)))
        XCTAssertEqual(store.imagesWithoutRecognizedText(limit: 10).map(\.id), [id])
        XCTAssertTrue(store.items(matching: "hello").isEmpty)

        // 在本机识别图片里的文字，之后搜索能找到这张图
        ClipboardImageIndex.backfill(store: store)
        XCTAssertTrue(store.imagesWithoutRecognizedText(limit: 10).isEmpty)
        XCTAssertEqual(store.items(matching: "hello").map(\.id), [id])
        XCTAssertEqual(store.item(id: id)?.recognizedText?.uppercased().contains("POP"), true)

        // 识别过的不再识别
        store.setRecognizedText("", id: id)
        ClipboardImageIndex.index(png: png, id: id, store: store)
        XCTAssertEqual(store.item(id: id)?.recognizedText, "")
    }

    func testMigratesTheFirstSchema() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var handle: OpaquePointer?
        let path = directory.appending(path: "history.sqlite").path(percentEncoded: false)
        XCTAssertEqual(sqlite3_open(path, &handle), SQLITE_OK)
        let old = """
            CREATE TABLE items (id INTEGER PRIMARY KEY AUTOINCREMENT, kind TEXT NOT NULL, text TEXT NOT NULL DEFAULT '',
                image_name TEXT, hash TEXT NOT NULL UNIQUE, source_app TEXT, created_at REAL NOT NULL, used_at REAL NOT NULL,
                pinned INTEGER NOT NULL DEFAULT 0, byte_size INTEGER NOT NULL DEFAULT 0);
            INSERT INTO items (kind, text, hash, created_at, used_at) VALUES ('text', '旧的记录', 'text:old', 1, 1);
            PRAGMA user_version = 1;
            """
        XCTAssertEqual(sqlite3_exec(handle, old, nil, nil, nil), SQLITE_OK)
        sqlite3_close(handle)

        let store = ClipboardStore(directory: directory)
        XCTAssertEqual(store.items().map(\.text), ["旧的记录"])
        XCTAssertNil(store.items().first?.recognizedText)
        XCTAssertEqual(store.items(matching: "旧的").count, 1)
    }

    /// 白底黑字的一张图
    private static func renderText(_ text: String) -> Data? {
        let size = CGSize(width: 640, height: 140)
        guard let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 56, weight: .bold),
                                                      .foregroundColor: NSColor.black]).draw(at: CGPoint(x: 24, y: 36))
        NSGraphicsContext.restoreGraphicsState()
        guard let image = context.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }
}
