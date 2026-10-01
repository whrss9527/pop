import XCTest
@testable import Pop

final class EncryptFilesTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "pop-encrypt-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    func testPasswordsNamesAndArguments() {
        XCTAssertEqual(EncryptedImage.passwordHint("abc", confirm: "abc")?.blocking, true)
        XCTAssertEqual(EncryptedImage.passwordHint("abcd", confirm: "abce")?.message, "两次输入的密码不一样")
        XCTAssertEqual(EncryptedImage.passwordHint("abcd", confirm: "abcd")?.blocking, false)
        XCTAssertEqual(EncryptedImage.passwordHint("abcdefgh", confirm: "abcdefgh")?.blocking, false)
        XCTAssertNil(EncryptedImage.passwordHint("Pop-2026!x", confirm: "Pop-2026!x"))

        XCTAssertEqual(EncryptedImage.defaultName(for: [URL(fileURLWithPath: "/tmp/合同", isDirectory: true)]), "合同")
        XCTAssertEqual(EncryptedImage.defaultName(for: [URL(fileURLWithPath: "/tmp/报告.pdf")]), "报告")
        XCTAssertEqual(EncryptedImage.defaultName(for: [URL(fileURLWithPath: "/tmp/a"), URL(fileURLWithPath: "/tmp/b"), URL(fileURLWithPath: "/tmp/c")]), "3 项")
        XCTAssertEqual(EncryptedImage.volumeName(" 季度/报告:终版 "), "季度-报告-终版")
        XCTAssertEqual(EncryptedImage.volumeName("  "), "加密")

        let arguments = EncryptedImage.arguments(source: URL(fileURLWithPath: "/tmp/合同", isDirectory: true), output: URL(fileURLWithPath: "/tmp/合同.dmg"),
                                                 volume: "合同", strength: .aes256)
        XCTAssertEqual(Array(arguments.prefix(1)), ["create"])
        XCTAssertTrue(arguments.contains("-stdinpass"))
        XCTAssertEqual(arguments[arguments.firstIndex(of: "-encryption")! + 1], "AES-256")
        XCTAssertEqual(arguments[arguments.firstIndex(of: "-srcfolder")! + 1], "/tmp/合同/")
        XCTAssertEqual(arguments.last, "/tmp/合同.dmg")
    }

    /// 真的用 hdiutil 做一个加密映像，再用密码挂上看看里面的东西
    func testCreatesAnEncryptedImage() async throws {
        let contract = folder.appending(path: "合同", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: contract, withIntermediateDirectories: true)
        try Data("第一页".utf8).write(to: contract.appending(path: "第一页.txt"))
        let note = folder.appending(path: "备注.txt")
        try Data("备注".utf8).write(to: note)
        XCTAssertGreaterThan(EncryptedImage.size(of: [contract, note]), 0)

        let image = try await EncryptedImage.create([contract], name: "合同", password: "pop-test-2026", in: folder)
        XCTAssertEqual(image.lastPathComponent, "合同.dmg")
        let encrypted = await EncryptedImage.isEncrypted(image)
        XCTAssertTrue(encrypted)
        // 几个文件：先放进临时文件夹；同名的映像已经有了就加 2
        let both = try await EncryptedImage.create([contract, note], name: "合同", password: "pop-test-2026", strength: .aes128, in: folder)
        XCTAssertEqual(both.lastPathComponent, "合同 2.dmg")

        // 用密码挂上（这台机器挂不上磁盘映像时跳过这一段）
        let mount = folder.appending(path: "挂载点", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
        let attached = await ProcessRunner.run(URL(fileURLWithPath: "/usr/bin/hdiutil"),
                                               arguments: ["attach", "-stdinpass", "-nobrowse", "-readonly", "-mountpoint",
                                                           mount.path(percentEncoded: false), both.path(percentEncoded: false)],
                                               stdin: "pop-test-2026\0", environment: [:], timeout: 120)
        guard case .success(let run) = attached, run.status == 0 else { throw XCTSkip("这台机器上挂不上磁盘映像") }
        defer {
            _ = ProcessRunner.runSync(URL(fileURLWithPath: "/usr/bin/hdiutil"), arguments: ["detach", mount.path(percentEncoded: false), "-force"],
                                      stdin: nil, environment: [:], timeout: 60)
        }
        let names = try FileManager.default.contentsOfDirectory(atPath: mount.path(percentEncoded: false)).filter { !$0.hasPrefix(".") }
        XCTAssertEqual(Set(names), ["合同", "备注.txt"])
        XCTAssertEqual(try String(contentsOf: mount.appending(path: "合同/第一页.txt"), encoding: .utf8), "第一页")
    }

    @MainActor
    func testCardChecksThePasswordAndCreates() async throws {
        let items = [folder.appending(path: "报告.pdf")]
        var created: [(name: String, password: String, strength: EncryptedImage.Strength)] = []
        var trashed: [URL] = []
        let image = folder.appending(path: "报告.dmg")
        try Data("映像".utf8).write(to: image)
        let model = EncryptFilesModel(items: items, size: 2_000_000, create: { _, name, password, strength, _ in
            created.append((name: name, password: password, strength: strength))
            return image
        }, recycle: { urls in
            trashed = urls
            return urls
        })
        XCTAssertEqual(model.name, "报告")
        XCTAssertEqual(model.folder.standardizedFileURL, folder.standardizedFileURL)
        XCTAssertEqual(model.contents, "报告.pdf，一共 \(ByteCountFormatter.string(fromByteCount: 2_000_000, countStyle: .file))")
        XCTAssertFalse(model.canCreate)
        model.password = "pop-2026"
        model.confirm = "pop-2025"
        XCTAssertFalse(model.canCreate)
        model.confirm = "pop-2026"
        XCTAssertTrue(model.canCreate)
        model.strength = .aes128
        model.trashOriginals = true
        model.start()
        for _ in 0..<200 where model.phase == .working {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(model.phase, .done(image, size: 6))
        XCTAssertEqual(created.map { $0.name }, ["报告"])
        XCTAssertEqual(created.map { $0.password }, ["pop-2026"])
        XCTAssertEqual(created.map { $0.strength }, [.aes128])
        XCTAssertEqual(trashed, items)
        // 做好以后密码不留着
        XCTAssertTrue(model.password.isEmpty)

        let failing = EncryptFilesModel(items: items, size: 1, create: { _, _, _, _, _ in
            throw EncryptedImage.Failure(message: "加密打包失败：磁盘满了")
        }, recycle: { $0 })
        failing.password = "pop-2026"
        failing.confirm = "pop-2026"
        failing.start()
        for _ in 0..<200 where failing.phase == .working {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(failing.phase, .failed("加密打包失败：磁盘满了"))
        failing.retry()
        XCTAssertEqual(failing.phase, .editing)
    }

    func testPluginTakesFiles() {
        let plugin = EncryptFilesPlugin().info
        XCTAssertTrue(plugin.canHandle(ContentClassifier.classify(.files([URL(fileURLWithPath: "/tmp/合同.pdf")]))))
        XCTAssertFalse(plugin.canHandle(.empty))
        XCTAssertFalse(plugin.canHandle(ContentClassifier.classify(.text("你好"))))
    }
}
