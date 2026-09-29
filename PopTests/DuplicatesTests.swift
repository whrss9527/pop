import XCTest
@testable import Pop

final class DuplicatesTests: XCTestCase {
    /// 一个临时文件夹：三份一样的内容（其中一份在子文件夹里）、一个同样大小但内容不同的、一个大小不同的，
    /// 再加一个隐藏文件和一个空文件（都不算）
    private func makeFolder() throws -> (root: URL, original: URL, copies: [URL]) {
        let root = FileManager.default.temporaryDirectory.appending(path: "pop-duplicates-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appending(path: "nested"), withIntermediateDirectories: true)
        let original = root.appending(path: "a.txt")
        let copies = [root.appending(path: "a copy.txt"), root.appending(path: "nested/a.txt")]
        let files: [(URL, String)] = [(original, "same"), (copies[0], "same"), (copies[1], "same"),
                                      (root.appending(path: "c.txt"), "diff"), (root.appending(path: "d.bin"), "longer content"),
                                      (root.appending(path: ".hidden"), "same"), (root.appending(path: "empty.txt"), "")]
        for (url, text) in files {
            try Data(text.utf8).write(to: url)
        }
        // 创建时间定下来：原件最早
        for (offset, url) in ([original] + copies).enumerated() {
            try FileManager.default.setAttributes([.creationDate: Date(timeIntervalSince1970: 1_700_000_000 + Double(offset) * 60)],
                                                  ofItemAtPath: url.path(percentEncoded: false))
        }
        return (root, original, copies)
    }

    func testFindsGroupsWithTheOldestFirst() throws {
        let folder = try makeFolder()
        let result = DuplicateFinder.find(in: [folder.root])
        XCTAssertEqual(result.scanned, 5)
        XCTAssertFalse(result.truncated)
        XCTAssertEqual(result.groups.count, 1)
        let group = try XCTUnwrap(result.groups.first)
        XCTAssertEqual(group.id, "0967115f2813a3541eaef77de9d9d5773f1c0c04314b0bbfe4ff3b3b1c55b5d5")
        XCTAssertEqual(group.size, 4)
        XCTAssertEqual(group.files.map(\.lastPathComponent), ["a.txt", "a copy.txt", "a.txt"])
        XCTAssertEqual(group.files.first?.resolvingSymlinksInPath(), folder.original.resolvingSymlinksInPath())
        XCTAssertEqual(result.wasted, 8)
        // 同时选了父文件夹和子文件夹，同一个文件只算一次
        XCTAssertEqual(DuplicateFinder.find(in: [folder.root, folder.root.appending(path: "nested")]).scanned, 5)
        // 开头一小段一样，整个文件不一样
        XCTAssertEqual(DuplicateFinder.hash(folder.original, limit: 2), DuplicateFinder.hash(folder.copies[0], limit: 2))
        XCTAssertNotEqual(DuplicateFinder.hash(folder.original), DuplicateFinder.hash(folder.root.appending(path: "c.txt")))
    }

    @MainActor
    func testCardKeepsOnePerGroup() async throws {
        let folder = try makeFolder()
        let model = DuplicatesModel(roots: [folder.root])
        model.start()
        for _ in 0..<200 {
            if case .done = model.phase { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        guard case .done(let result) = model.phase else { return XCTFail("没有扫完") }
        XCTAssertEqual(result.groups.count, 1)

        model.keepOne(in: result.groups)
        guard case .done(let after) = model.phase else { return XCTFail("状态不对") }
        XCTAssertTrue(after.groups.isEmpty)
        XCTAssertEqual(model.message, "已把 2 个文件移到废纸篓，可以从废纸篓放回")
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.original.path(percentEncoded: false)))
        for copy in folder.copies {
            XCTAssertFalse(FileManager.default.fileExists(atPath: copy.path(percentEncoded: false)), copy.path)
        }
    }

    @MainActor
    func testPluginNeedsAFolder() async throws {
        let folder = try makeFolder()
        let context = PluginContext(settings: AppSettings(), openSettings: {})
        let content = ContentClassifier.classify(.files([folder.root]))
        XCTAssertTrue(DuplicatesPlugin().info.canHandle(content))
        XCTAssertFalse(DuplicatesPlugin().info.canHandle(ContentClassifier.classify(.files([folder.original]))))
        let outcome = await DuplicatesPlugin().run(content, context: context)
        XCTAssertEqual(outcome, .findDuplicates([folder.root]))
    }
}
