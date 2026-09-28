import Combine
import XCTest
@testable import Pop

final class PluginManifestTests: XCTestCase {
    func testLenientDecoding() throws {
        let json = #"""
        {"id": "user-x", "name": "测试", "match": {"kinds": ["text", "fromTheFuture", "url"], "pattern": 5},
         "action": {"type": "teleport", "timeout": 99999}, "output": "hologram"}
        """#
        let manifest = try PluginManifest.makeDecoder().decode(PluginManifest.self, from: Data(json.utf8))
        XCTAssertEqual(manifest.id, "user-x")
        XCTAssertEqual(manifest.match.kinds, [.text, .url])
        XCTAssertNil(manifest.match.pattern)
        XCTAssertEqual(manifest.action.type, .url)
        XCTAssertEqual(manifest.action.timeout, PluginManifest.Action.timeoutRange.upperBound)
        XCTAssertEqual(manifest.output, PluginManifest.Output.card)
        XCTAssertEqual(manifest.symbol, PluginManifest.defaultSymbol)
    }

    func testFileRoundTripAndCompactActionEncoding() throws {
        var manifest = PluginManifest(name: "排序", match: .init(kinds: [.text], pattern: "\\n"),
                                      action: .init(type: .shell, template: "leftover", script: "sort -u", timeout: 20), output: .replace)
        manifest = manifest.normalized()
        manifest.modifiedAt = PluginManifest.timestamp()
        let data = try PluginManifest.makeEncoder().encode(manifest)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains("\"script\""))
        XCTAssertTrue(json.contains("sort -u"))
        XCTAssertFalse(json.contains("template"))
        XCTAssertEqual(try PluginManifest.makeDecoder().decode(PluginManifest.self, from: data), manifest)
    }

    func testNormalizedCleansUp() {
        let manifest = PluginManifest(name: "  网页  ", symbol: " ", match: .init(kinds: [.text], pattern: "  ", minLength: 0),
                                      action: .init(type: .url, template: " https://example.com/?q={text} ", script: "unused"),
                                      output: .card).normalized()
        XCTAssertEqual(manifest.name, "网页")
        XCTAssertEqual(manifest.symbol, PluginManifest.defaultSymbol)
        XCTAssertNil(manifest.match.pattern)
        XCTAssertNil(manifest.match.minLength)
        XCTAssertEqual(manifest.action.template, "https://example.com/?q={text}")
        XCTAssertEqual(manifest.action.script, "")
        XCTAssertEqual(manifest.output, PluginManifest.Output.none)
    }

    func testValidation() {
        XCTAssertEqual(PluginManifest(name: " ").validationError(), "请填写名称")
        XCTAssertNotNil(PluginManifest(name: "x", action: .init(type: .url, template: "example.com/{text}")).validationError())
        XCTAssertNotNil(PluginManifest(name: "x", match: .init(pattern: "("), action: .init(type: .url, template: "https://a.com")).validationError())
        XCTAssertNotNil(PluginManifest(name: "x", action: .init(type: .shell, script: "  ")).validationError())
        XCTAssertNil(PluginManifest(name: "x", action: .init(type: .javascript, script: "input")).validationError())
        for template in PluginManifest.templates {
            XCTAssertNil(template.manifest.validationError(), template.title)
        }
    }

    func testIDs() {
        XCTAssertTrue(PluginManifest.isValidID("user-abc_1.2"))
        XCTAssertTrue(PluginManifest.isValidID(PluginManifest.makeID()))
        XCTAssertFalse(PluginManifest.isValidID(""))
        XCTAssertFalse(PluginManifest.isValidID("../escape"))
        XCTAssertFalse(PluginManifest.isValidID(".hidden"))
        XCTAssertFalse(PluginManifest.isValidID("中文"))
        XCTAssertNotEqual(PluginManifest.makeID(), PluginManifest.makeID())
    }

    func testManifestPluginInfo() {
        let manifest = PluginManifest(id: "user-digits", name: "数字", match: .init(kinds: [.text], pattern: "^[0-9]+$"),
                                      action: .init(type: .javascript, script: "input"))
        let info = ManifestPlugin(manifest: manifest).info
        XCTAssertEqual(info.source, .user)
        XCTAssertEqual(info.summary, PluginManifest.Action.Kind.javascript.title)
        XCTAssertTrue(info.canHandle(ContentClassifier.classify(.text("2024"))))
        XCTAssertFalse(info.canHandle(ContentClassifier.classify(.text("abc"))))

        // 没有勾选任何类型：随时可用
        let anytime = ManifestPlugin(manifest: PluginManifest(name: "随时", match: .init(kinds: []))).info
        XCTAssertTrue(anytime.canHandle(.empty))
    }
}

final class ManifestRunnerTests: XCTestCase {
    private typealias Action = PluginManifest.Action

    private func run(_ action: Action, _ text: String, files: [String] = []) async -> Result<String, PluginRunError> {
        await ManifestRunner.execute(action, input: ManifestRunner.Input(text: text, files: files))
    }

    func testURLTemplate() {
        let input = ManifestRunner.Input(text: "C++ 你好")
        XCTAssertEqual(ManifestRunner.expandURL("https://example.com/s?q={text}", input: input)?.absoluteString,
                       "https://example.com/s?q=C%2B%2B%20%E4%BD%A0%E5%A5%BD")
        XCTAssertNil(ManifestRunner.expandURL("not a url {text}", input: input))
    }

    func testJavaScript() async {
        let upper = await run(Action(type: .javascript, script: "function run(input) { return input.toUpperCase() }"), "pop")
        XCTAssertEqual(upper, .success("POP"))

        let expression = await run(Action(type: .javascript, script: "input.split('').reverse().join('')"), "abc")
        XCTAssertEqual(expression, .success("cba"))

        let object = await run(Action(type: .javascript, script: "function run(input, files) { return { count: files.length } }"), "", files: ["a", "b"])
        XCTAssertEqual(object, .success("{\n  \"count\": 2\n}"))

        let logged = await run(Action(type: .javascript, script: "console.log('hello', 1)"), "")
        XCTAssertEqual(logged, .success("hello 1"))
    }

    func testJavaScriptErrors() async {
        let thrown = await run(Action(type: .javascript, script: "function run() { throw new Error('boom') }"), "x")
        guard case .failure(let error) = thrown else { return XCTFail("应该失败") }
        XCTAssertTrue(error.message.contains("boom"), error.message)

        let syntax = await run(Action(type: .javascript, script: "function ("), "x")
        guard case .failure = syntax else { return XCTFail("语法错误应该失败") }
    }

    func testJavaScriptTimeout() async {
        let start = Date()
        let result = await run(Action(type: .javascript, script: "while (true) {}", timeout: 1), "x")
        guard case .failure = result else { return XCTFail("死循环应该超时") }
        XCTAssertLessThan(Date().timeIntervalSince(start), 10)
    }

    func testShell() async {
        let upper = await run(Action(type: .shell, script: "tr a-z A-Z"), "pop\n")
        XCTAssertEqual(upper, .success("POP"))

        let environment = await run(Action(type: .shell, script: #"printf '%s|%s' "$POP_TEXT" "$POP_FILES""#), "text", files: ["/a", "/b"])
        XCTAssertEqual(environment, .success("text|/a\n/b"))

        let failed = await run(Action(type: .shell, script: "echo oops >&2; exit 3"), "")
        XCTAssertEqual(failed, .failure(PluginRunError("oops")))

        let silent = await run(Action(type: .shell, script: "exit 4"), "")
        XCTAssertEqual(silent, .failure(PluginRunError("脚本退出码 4")))
    }

    func testShellTimeout() async {
        let start = Date()
        let result = await run(Action(type: .shell, script: "sleep 20", timeout: 1), "")
        XCTAssertEqual(result, .failure(PluginRunError("运行超时")))
        XCTAssertLessThan(Date().timeIntervalSince(start), 10)
    }

    func testTrimTrailingNewlines() {
        XCTAssertEqual(ManifestRunner.trimTrailingNewlines("a\nb\n\r\n"), "a\nb")
        XCTAssertEqual(ManifestRunner.trimTrailingNewlines("\n"), "")
    }

    @MainActor
    func testOutputModes() {
        let copy = ManifestRunner.present("result", manifest: PluginManifest(name: "x", output: .copy), canReplace: true)
        XCTAssertEqual(copy, .done(toast: "已复制结果"))
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "result")

        let replace = ManifestRunner.present("new", manifest: PluginManifest(name: "x", output: .replace), canReplace: true)
        XCTAssertEqual(replace, .replace("new"))
        let cannotReplace = ManifestRunner.present("new", manifest: PluginManifest(name: "x", output: .replace), canReplace: false)
        XCTAssertEqual(cannotReplace, .failure("选中的不是文字，无法替换"))

        let toast = ManifestRunner.present("first\nsecond", manifest: PluginManifest(name: "x", output: .toast), canReplace: false)
        XCTAssertEqual(toast, .done(toast: "first"))

        let card = ManifestRunner.present("body", manifest: PluginManifest(name: "标题", output: .card), canReplace: true)
        XCTAssertEqual(card, .card(ResultCard(title: "标题", body: "body", monospaced: true, copyText: "body", replaceText: "body")))
    }
}

final class PluginStoreTests: XCTestCase {
    private var directory: URL!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "pop-plugins-\(UUID().uuidString)", directoryHint: .isDirectory)
        defaults = try XCTUnwrap(UserDefaults(suiteName: "pop.tests.\(UUID().uuidString)"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func webPlugin(_ name: String) -> PluginManifest {
        PluginManifest(name: name, action: .init(type: .url, template: "https://example.com/?q={text}"))
    }

    @MainActor
    func testSaveReloadAndDelete() throws {
        let store = PluginStore(directory: directory, defaults: defaults)
        XCTAssertTrue(store.manifests.isEmpty)
        XCTAssertEqual(store.modifiedAt, .distantPast)
        var changes = 0
        let cancellable = store.localChanges.sink { _ in changes += 1 }
        defer { cancellable.cancel() }

        let saved = try store.save(webPlugin("  网页搜索 "))
        XCTAssertEqual(saved.name, "网页搜索")
        XCTAssertEqual(saved.output, PluginManifest.Output.none)
        XCTAssertEqual(changes, 1)
        XCTAssertGreaterThan(store.modifiedAt, .distantPast)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appending(path: "\(saved.id).json").path(percentEncoded: false)))

        // 重新打开能读到同样的内容；内容没变时重新载入不算修改
        XCTAssertEqual(PluginStore(directory: directory, defaults: defaults).manifests, [saved])
        store.reloadFromDisk()
        XCTAssertEqual(changes, 1)

        store.delete(id: saved.id)
        XCTAssertTrue(store.manifests.isEmpty)
        XCTAssertEqual(changes, 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appending(path: "\(saved.id).json").path(percentEncoded: false)))
    }

    @MainActor
    func testHandWrittenFilesAreLoaded() throws {
        let store = PluginStore(directory: directory, defaults: defaults)
        var changes = 0
        let cancellable = store.localChanges.sink { _ in changes += 1 }
        defer { cancellable.cancel() }

        try Data(#"{"action": {"type": "javascript", "script": "input.length"}}"#.utf8)
            .write(to: directory.appending(path: "hand-made.json"))
        try Data("not json".utf8).write(to: directory.appending(path: "broken.json"))
        try Data(#"{"id": "translate", "name": "冒名"}"#.utf8).write(to: directory.appending(path: "clash.json"))
        store.reloadFromDisk()

        XCTAssertEqual(store.manifests.map(\.id), ["hand-made"])
        XCTAssertEqual(store.manifests.first?.name, "hand-made")
        XCTAssertNotNil(store.loadErrors["broken.json"])
        XCTAssertNotNil(store.loadErrors["clash.json"])
        XCTAssertEqual(changes, 1)

        // 编辑后写回原来的文件，不会多出一个文件
        var edited = try XCTUnwrap(store.manifests.first)
        edited.summary = "字数"
        try store.save(edited)
        let jsonFiles = try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false)).filter { $0.hasSuffix(".json") }
        XCTAssertEqual(Set(jsonFiles), ["hand-made.json", "broken.json", "clash.json"])
    }

    @MainActor
    func testImportReplacesInvalidIDs() throws {
        let store = PluginStore(directory: directory, defaults: defaults)
        let source = FileManager.default.temporaryDirectory.appending(path: "import-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: source) }
        try Data(#"{"id": "translate", "name": "导入的", "action": {"type": "url", "template": "https://a.com/{text}"}}"#.utf8).write(to: source)
        let imported = try store.importFile(at: source)
        XCTAssertNotEqual(imported.id, "translate")
        XCTAssertTrue(imported.id.hasPrefix("user-"))
        XCTAssertEqual(store.manifests.map(\.name), ["导入的"])
    }

    @MainActor
    func testApplyRemoteReplacesLocalPluginsSilently() throws {
        let store = PluginStore(directory: directory, defaults: defaults)
        let local = try store.save(webPlugin("本地"))
        var changes = 0
        let cancellable = store.localChanges.sink { _ in changes += 1 }
        defer { cancellable.cancel() }

        var remote = webPlugin("云端").normalized()
        remote.modifiedAt = PluginManifest.timestamp(Date(timeIntervalSince1970: 1_800_000_000))
        let remoteDate = Date(timeIntervalSince1970: 1_800_000_100)
        store.applyRemote([remote], modifiedAt: remoteDate)

        XCTAssertEqual(store.manifests, [remote])
        XCTAssertEqual(store.modifiedAt, remoteDate)
        XCTAssertEqual(changes, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appending(path: "\(local.id).json").path(percentEncoded: false)))
        // 云端的插件写进了文件夹，重新载入不会被当成本地修改
        store.reloadFromDisk()
        XCTAssertEqual(changes, 0)
        XCTAssertEqual(PluginStore(directory: directory, defaults: defaults).manifests, [remote])
    }

    @MainActor
    func testRegistryMergesUserPlugins() {
        let registry = PluginRegistry()
        let builtinCount = registry.catalog.count
        registry.setUserManifests([
            PluginManifest(id: "user-one", name: "一"),
            PluginManifest(id: BuiltinPluginID.translate, name: "冒名"),
        ])
        XCTAssertEqual(registry.userPlugins.map(\.manifest.id), ["user-one"])
        XCTAssertEqual(registry.catalog.count, builtinCount + 1)
        XCTAssertEqual(registry.info(id: "user-one")?.source, .user)
        XCTAssertEqual(registry.info(id: BuiltinPluginID.translate)?.source, .builtin)
    }

    func testPluginSyncResolution() {
        let older = Date(timeIntervalSince1970: 1_700_000_000)
        let newer = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(SyncResolver.resolve(localModifiedAt: .distantPast, remoteModifiedAt: nil, sameContent: false), .none)
        XCTAssertEqual(SyncResolver.resolve(localModifiedAt: .distantPast, remoteModifiedAt: older, sameContent: false), .applyRemote)
        XCTAssertEqual(SyncResolver.resolve(localModifiedAt: newer, remoteModifiedAt: older, sameContent: false), .pushLocal)
        XCTAssertEqual(SyncResolver.resolve(localModifiedAt: older, remoteModifiedAt: newer, sameContent: true), .none)
    }

    func testPluginEnvelopeRoundTrip() throws {
        let envelope = PluginSyncEnvelope(device: "MacBook", modifiedAt: Date(timeIntervalSince1970: 1_800_000_000),
                                          plugins: [PluginManifest(id: "user-a", name: "A", action: .init(type: .shell, script: "cat")).normalized()])
        let data = try JSONEncoder().encode(envelope)
        XCTAssertEqual(try JSONDecoder().decode(PluginSyncEnvelope.self, from: data), envelope)
    }
}

final class PasteboardGuardTests: XCTestCase {
    func testVerdicts() {
        let pasteboardGuard = PasteboardGuard()
        XCTAssertEqual(pasteboardGuard.verdict(for: 5), .record)
        pasteboardGuard.begin()
        XCTAssertEqual(pasteboardGuard.verdict(for: 6), .busy)
        pasteboardGuard.end(changeCount: 7)
        XCTAssertEqual(pasteboardGuard.verdict(for: 7), .ignore)
        XCTAssertEqual(pasteboardGuard.verdict(for: 8), .record)
    }
}
