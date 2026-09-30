import AppKit
import XCTest
@testable import Pop

/// 假的插件库：按网址返回设好的状态码和内容，没设的网址当作连不上，不联网。
final class MockPluginLibrary: URLProtocol {
    static var responses: [String: (status: Int, body: Data)] = [:]

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockPluginLibrary.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let response = Self.responses[url.absoluteString],
              let http = HTTPURLResponse(url: url, statusCode: response.status, httpVersion: "HTTP/1.1", headerFields: nil) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class PluginLibraryTests: XCTestCase {
    private let github = URL(string: "https://example.com/pop/main/plugins/index.json")!
    private let mirror = URL(string: "https://mirror.example.net/pop@main/plugins/index.json")!
    private var directory: URL!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        MockPluginLibrary.responses = [:]
        directory = FileManager.default.temporaryDirectory.appending(path: "pop-library-\(UUID().uuidString)", directoryHint: .isDirectory)
        defaults = try XCTUnwrap(UserDefaults(suiteName: "pop.tests.\(UUID().uuidString)"))
    }

    override func tearDownWithError() throws {
        MockPluginLibrary.responses = [:]
        try? FileManager.default.removeItem(at: directory)
    }

    private func pluginFile(id: String, name: String, type: String = "url") -> Data {
        let action = type == "shell"
            ? #"{"type": "shell", "script": "sort -u"}"#
            : #"{"type": "url", "template": "https://example.com/search?q={text}"}"#
        return Data(#"{"format": 1, "id": "\#(id)", "name": "\#(name)", "action": \#(action), "output": "none"}"#.utf8)
    }

    private func indexData(_ entries: [(id: String, name: String, type: String, sha256: String)]) -> Data {
        let items = entries.map { entry in
            #"{"id": "\#(entry.id)", "name": "\#(entry.name)", "summary": "说明", "author": "测试", "type": "\#(entry.type)", "url": "\#(entry.id).json", "sha256": "\#(entry.sha256)"}"#
        }
        return Data(#"{"format": 1, "plugins": [\#(items.joined(separator: ","))]}"#.utf8)
    }

    func testIndexDecodingSkipsBrokenEntries() throws {
        let json = #"""
        {
          "format": 1,
          "plugins": [
            {"id": "douban", "name": "豆瓣", "summary": "搜书和电影", "author": "Pop", "symbol": "film", "type": "url",
             "url": "douban.json", "sha256": "ABCDEF"},
            {"id": "no-hash", "name": "没有校验值", "url": "no-hash.json"},
            {"id": "douban", "name": "重复的", "url": "other.json", "sha256": "00"},
            {"id": "future", "type": "webview", "url": "https://example.com/future.json", "sha256": "11"},
            "不是对象"
          ],
          "extra": true
        }
        """#
        let index = try JSONDecoder().decode(PluginIndex.self, from: Data(json.utf8))
        XCTAssertEqual(index.plugins.map(\.id), ["douban", "future"])
        let douban = index.plugins[0]
        XCTAssertEqual(douban.name, "豆瓣")
        XCTAssertEqual(douban.author, "Pop")
        XCTAssertEqual(douban.symbol, "film")
        XCTAssertEqual(douban.sha256, "abcdef")
        XCTAssertEqual(douban.kind, .url)
        // 没写名称用 ID；不认识的类型要更新 Pop 才能装
        let future = index.plugins[1]
        XCTAssertEqual(future.name, "future")
        XCTAssertEqual(future.symbol, PluginManifest.defaultSymbol)
        XCTAssertNil(future.kind)

        // 搜索：名称的拼音首字母、说明、作者
        XCTAssertEqual(index.entries(matching: "db").map(\.id), ["douban"])
        XCTAssertEqual(index.entries(matching: "电影").map(\.id), ["douban"])
        XCTAssertEqual(index.entries(matching: "POP").map(\.id), ["douban"])
        XCTAssertEqual(index.entries(matching: " ").count, 2)
        XCTAssertTrue(index.entries(matching: "没有这个").isEmpty)

        XCTAssertEqual(try JSONDecoder().decode(PluginIndex.self, from: Data("{}".utf8)).plugins, [])
    }

    func testLocalizedNamesFollowTheInterfaceLanguage() throws {
        let data = Data(#"{"id": "demo", "name": "豆瓣", "summary": "搜书", "localized": {"en": {"name": "Douban", "summary": " "}, "ja": 3}}"#.utf8)
        let manifest = try JSONDecoder().decode(PluginManifest.self, from: data)
        // 写错的语言让整个 localized 读不出来，不影响插件本身
        XCTAssertEqual(manifest.name, "豆瓣")
        let good = Data(#"{"id": "demo", "name": "豆瓣", "summary": "搜书", "localized": {"en": {"name": "Douban", "summary": " "}}}"#.utf8)
        let localized = try JSONDecoder().decode(PluginManifest.self, from: good).localized
        XCTAssertEqual(PluginManifest.localizedValue(localized, \.name, languages: ["en"]), "Douban")
        XCTAssertEqual(PluginManifest.localizedValue(localized, \.name, languages: ["en-GB"]), "Douban")
        XCTAssertNil(PluginManifest.localizedValue(localized, \.name, languages: ["zh-Hans"]))
        XCTAssertNil(PluginManifest.localizedValue(localized, \.summary, languages: ["en"]), "空白的说明用原来的")
        // 测试用中文界面：显示原来的名字
        XCTAssertEqual(try JSONDecoder().decode(PluginManifest.self, from: good).displayName, "豆瓣")
        // 保存时去掉空白的翻译，没有翻译就不写 localized
        var manifest2 = try JSONDecoder().decode(PluginManifest.self, from: good)
        manifest2 = manifest2.normalized()
        XCTAssertEqual(manifest2.localized, ["en": PluginManifest.LocalizedText(name: "Douban", summary: nil)])
        manifest2.localized = ["en": PluginManifest.LocalizedText(name: " ", summary: nil)]
        XCTAssertNil(manifest2.normalized().localized)
        let encoded = try JSONEncoder().encode(PluginManifest(name: "没有翻译"))
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("localized"))
    }

    func testCandidateURLs() {
        let catalog = PluginLibrary.Catalog(index: PluginIndex(plugins: []), source: mirror)
        let relative = PluginIndex.Entry(id: "a", name: "A", url: "a.json", sha256: "00")
        // 先按读到索引的镜像算，再按其他地址算
        XCTAssertEqual(PluginLibrary.candidates(for: relative, catalog: catalog, sources: [github, mirror]).map(\.absoluteString),
                       ["https://mirror.example.net/pop@main/plugins/a.json", "https://example.com/pop/main/plugins/a.json"])
        let nested = PluginIndex.Entry(id: "b", name: "B", url: "more/b.json", sha256: "00")
        XCTAssertEqual(PluginLibrary.candidates(for: nested, catalog: catalog, sources: [mirror]).map(\.absoluteString),
                       ["https://mirror.example.net/pop@main/plugins/more/b.json"])
        let absolute = PluginIndex.Entry(id: "c", name: "C", url: "https://other.example.org/c.json", sha256: "00")
        XCTAssertEqual(PluginLibrary.candidates(for: absolute, catalog: catalog, sources: [github, mirror]).map(\.absoluteString),
                       ["https://other.example.org/c.json"])
    }

    func testDownloadedPluginIsVerified() throws {
        let data = pluginFile(id: "search-a", name: "搜索 A")
        let entry = PluginIndex.Entry(id: "search-a", name: "搜索 A", url: "search-a.json", sha256: Digests.sha256(data))
        let manifest = try PluginLibrary.manifest(from: data, entry: entry)
        XCTAssertEqual(manifest.id, "search-a")
        XCTAssertEqual(manifest.name, "搜索 A")
        XCTAssertEqual(manifest.action.template, "https://example.com/search?q={text}")

        // 内容被改过：校验值对不上
        var tampered = data
        tampered.append(contentsOf: Array(" ".utf8))
        XCTAssertThrowsError(try PluginLibrary.manifest(from: tampered, entry: entry)) { error in
            XCTAssertTrue((error as? PluginLibrary.Failure)?.message.contains("校验值") == true, "\(error)")
        }
        // ID 和索引里的不一样、和内置功能重名、不是插件、缺了网址
        let other = pluginFile(id: "other", name: "搜索 A")
        XCTAssertThrowsError(try PluginLibrary.manifest(from: other, entry: PluginIndex.Entry(id: "search-a", name: "搜索 A", url: "x", sha256: Digests.sha256(other))))
        let builtin = pluginFile(id: BuiltinPluginID.translate, name: "冒名")
        XCTAssertThrowsError(try PluginLibrary.manifest(from: builtin, entry: PluginIndex.Entry(id: BuiltinPluginID.translate, name: "冒名", url: "x", sha256: Digests.sha256(builtin))))
        let broken = Data("not json".utf8)
        XCTAssertThrowsError(try PluginLibrary.manifest(from: broken, entry: PluginIndex.Entry(id: "x", name: "X", url: "x", sha256: Digests.sha256(broken))))
        let empty = Data(#"{"id": "empty", "name": "空", "action": {"type": "url", "template": ""}}"#.utf8)
        XCTAssertThrowsError(try PluginLibrary.manifest(from: empty, entry: PluginIndex.Entry(id: "empty", name: "空", url: "x", sha256: Digests.sha256(empty))))
        // 文件里没写 ID 时用索引里的
        let unnamed = Data(#"{"action": {"type": "url", "template": "https://example.com/?q={text}"}}"#.utf8)
        let filled = try PluginLibrary.manifest(from: unnamed, entry: PluginIndex.Entry(id: "unnamed", name: "没写名字", url: "x", sha256: Digests.sha256(unnamed)))
        XCTAssertEqual(filled.id, "unnamed")
        XCTAssertEqual(filled.name, "没写名字")
    }

    func testFallsBackToMirror() async throws {
        let good = pluginFile(id: "search-a", name: "搜索 A")
        let sha = Digests.sha256(good)
        // GitHub 连不上，从镜像读到索引；镜像上的插件文件是旧的（校验值对不上），换回 GitHub 的地址下载
        MockPluginLibrary.responses[github.absoluteString] = (503, Data())
        MockPluginLibrary.responses[mirror.absoluteString] = (200, indexData([("search-a", "搜索 A", "url", sha)]))
        MockPluginLibrary.responses["https://mirror.example.net/pop@main/plugins/search-a.json"] = (200, pluginFile(id: "search-a", name: "旧的"))
        MockPluginLibrary.responses["https://example.com/pop/main/plugins/search-a.json"] = (200, good)

        let session = MockPluginLibrary.session()
        let catalog = try await PluginLibrary.fetchIndex(from: [github, mirror], session: session)
        XCTAssertEqual(catalog.source, mirror)
        let entry = try XCTUnwrap(catalog.index.plugins.first)
        let manifest = try await PluginLibrary.fetchPlugin(entry, catalog: catalog, sources: [github, mirror], session: session)
        XCTAssertEqual(manifest.name, "搜索 A")

        // 哪里都连不上
        MockPluginLibrary.responses = [:]
        do {
            _ = try await PluginLibrary.fetchIndex(from: [github, mirror], session: session)
            XCTFail("应该连不上")
        } catch {
            XCTAssertTrue((error as? PluginLibrary.Failure)?.message.contains("连不上") == true, "\(error)")
        }
        // 索引不是 JSON
        MockPluginLibrary.responses[github.absoluteString] = (200, Data("<html>".utf8))
        do {
            _ = try await PluginLibrary.fetchIndex(from: [github], session: session)
            XCTFail("索引应该读不出来")
        } catch {
            XCTAssertEqual((error as? PluginLibrary.Failure)?.message, "插件库的索引读不出来")
        }
    }

    @MainActor
    func testInstallAndUpdate() async throws {
        let first = pluginFile(id: "search-a", name: "搜索 A")
        let script = pluginFile(id: "sorter", name: "排序", type: "shell")
        MockPluginLibrary.responses[github.absoluteString] = (200, indexData([("search-a", "搜索 A", "url", Digests.sha256(first)),
                                                                              ("sorter", "排序", "shell", Digests.sha256(script)),
                                                                              ("future", "新类型", "webview", "00")]))
        MockPluginLibrary.responses["https://example.com/pop/main/plugins/search-a.json"] = (200, first)
        MockPluginLibrary.responses["https://example.com/pop/main/plugins/sorter.json"] = (200, script)

        let store = PluginStore(directory: directory, defaults: defaults)
        let model = PluginLibraryModel(sources: [github], session: MockPluginLibrary.session(), defaults: defaults)
        await model.load()
        let entries = try XCTUnwrap(model.catalog?.index.plugins)
        XCTAssertEqual(entries.map(\.id), ["search-a", "sorter", "future"])
        func states() -> [PluginLibraryModel.EntryState] {
            let installed = Set(store.manifests.map(\.id))
            return entries.map { model.state(of: $0, installedIDs: installed) }
        }
        XCTAssertEqual(states(), [.notInstalled, .notInstalled, .unsupported])

        let saved = try await model.install(entries[0], into: store)
        XCTAssertEqual(saved?.id, "search-a")
        XCTAssertEqual(store.manifest(id: "search-a")?.name, "搜索 A")
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appending(path: "search-a.json").path(percentEncoded: false)))
        XCTAssertEqual(model.versions["search-a"], Digests.sha256(first))
        XCTAssertTrue(model.installing.isEmpty)

        // 运行 Shell 脚本的插件要先确认；不同意就不装
        var shown: [String] = []
        let declined = try await model.install(entries[1], into: store, confirm: { manifest in
            shown.append(manifest.action.script)
            return false
        })
        XCTAssertNil(declined)
        XCTAssertEqual(shown, ["sort -u"])
        XCTAssertNil(store.manifest(id: "sorter"))
        let accepted = try await model.install(entries[1], into: store, confirm: { _ in true })
        XCTAssertEqual(accepted?.action.type, .shell)
        XCTAssertEqual(states(), [.installed, .installed, .unsupported])

        // 不认识的类型装不了
        do {
            _ = try await model.install(entries[2], into: store)
            XCTFail("不认识的类型不该装上")
        } catch {
            XCTAssertTrue((error as? PluginLibrary.Failure)?.message.contains("更新 Pop") == true, "\(error)")
        }

        // 插件库里换了新版：显示「更新」，更新后记下新的版本；重新打开也记得
        let second = pluginFile(id: "search-a", name: "搜索 A（新）")
        MockPluginLibrary.responses[github.absoluteString] = (200, indexData([("search-a", "搜索 A（新）", "url", Digests.sha256(second))]))
        MockPluginLibrary.responses["https://example.com/pop/main/plugins/search-a.json"] = (200, second)
        let reopened = PluginLibraryModel(sources: [github], session: MockPluginLibrary.session(), defaults: defaults)
        await reopened.load()
        let updated = try XCTUnwrap(reopened.catalog?.index.plugins.first)
        XCTAssertEqual(reopened.state(of: updated, installedIDs: Set(store.manifests.map(\.id))), .updateAvailable)
        _ = try await reopened.install(updated, into: store)
        XCTAssertEqual(store.manifest(id: "search-a")?.name, "搜索 A（新）")
        XCTAssertEqual(reopened.state(of: updated, installedIDs: Set(store.manifests.map(\.id))), .installed)

        // 连不上时显示原因
        MockPluginLibrary.responses = [:]
        await reopened.load()
        guard case .failed(let message) = reopened.phase else { return XCTFail("应该读不到索引：\(reopened.phase)") }
        XCTAssertTrue(message.contains("连不上"), message)
    }

    /// 仓库里的 plugins 文件夹：索引里的每一项都有文件、sha256 对得上、插件能装；文件夹里的插件都列在索引里
    func testRepositoryPlugins() throws {
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "plugins", directoryHint: .isDirectory)
        let indexFile = try Data(contentsOf: folder.appending(path: "index.json"))
        let index = try JSONDecoder().decode(PluginIndex.self, from: indexFile)
        // 每一项都要读得出来，ID 不重复（写错的会被跳过，数量就对不上）
        let raw = try XCTUnwrap(try JSONSerialization.jsonObject(with: indexFile) as? [String: Any])
        XCTAssertEqual((raw["plugins"] as? [Any])?.count, index.plugins.count, "index.json 里有写错或者重复的项")
        XCTAssertGreaterThanOrEqual(index.plugins.count, 10)

        for entry in index.plugins {
            XCTAssertNil(URL(string: entry.url)?.scheme, "\(entry.id)：仓库里的插件用相对地址")
            let data = try Data(contentsOf: folder.appending(path: entry.url))
            let actual = Digests.sha256(data)
            XCTAssertEqual(entry.sha256, actual, "\(entry.id)：index.json 里的 sha256 应该是 \(actual)")
            guard entry.sha256 == actual else { continue }
            let manifest = try PluginLibrary.manifest(from: data, entry: entry)
            XCTAssertEqual(manifest.name, entry.name, entry.id)
            XCTAssertEqual(manifest.summary, entry.summary, entry.id)
            XCTAssertEqual(manifest.symbol, entry.symbol, entry.id)
            XCTAssertEqual(manifest.localized, entry.localized, "\(entry.id)：localized 要和插件文件里的一样")
            XCTAssertFalse(entry.localized?["en"]?.name?.isEmpty ?? true, "\(entry.id)：要有英文名称")
            XCTAssertEqual(manifest.action.type.rawValue, entry.type, entry.id)
            XCTAssertFalse(entry.author.isEmpty, entry.id)
            XCTAssertNotNil(NSImage(systemSymbolName: entry.symbol, accessibilityDescription: nil), "\(entry.id)：没有 \(entry.symbol) 这个图标")
        }

        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))
            .filter { $0.hasSuffix(".json") && $0 != "index.json" }
        XCTAssertEqual(Set(files), Set(index.plugins.map(\.url)), "plugins 文件夹里的插件都要列在 index.json 里")
    }
}
