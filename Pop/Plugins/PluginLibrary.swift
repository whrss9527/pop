import Foundation

/// 插件库的索引：pop 仓库 plugins 文件夹里的 index.json，列出可以一键安装的插件。
///
/// ```json
/// {
///   "format": 1,
///   "plugins": [
///     {
///       "id": "github-search",
///       "name": "GitHub 搜索",
///       "summary": "在 GitHub 上搜索选中的文字，找相关的仓库",
///       "author": "Pop",
///       "symbol": "chevron.left.forwardslash.chevron.right",
///       "type": "url",
///       "url": "github-search.json",
///       "sha256": "…"
///     }
///   ]
/// }
/// ```
///
/// `url` 是插件文件的下载地址，可以写相对 index.json 的路径；`sha256` 是插件文件的 SHA-256，下载后核对，对不上就不装。
/// 和插件文件一样宽松解析：写错的一项跳过，其余照常列出来。
struct PluginIndex: Decodable, Equatable {
    static let currentFormat = 1

    var format = PluginIndex.currentFormat
    var plugins: [Entry] = []

    struct Entry: Decodable, Equatable, Identifiable {
        var id: String
        var name: String
        var summary = ""
        var author = ""
        var symbol = PluginManifest.defaultSymbol
        /// 动作类型，和插件文件里的 action.type 一样，列表里显示用
        var type = PluginManifest.Action.Kind.url.rawValue
        var url: String
        /// 插件文件的 SHA-256，小写十六进制
        var sha256: String
        /// 其他语言的名称和说明，写法和插件文件里的 localized 一样
        var localized: [String: PluginManifest.LocalizedText]? = nil

        private enum CodingKeys: String, CodingKey {
            case id, name, summary, author, symbol, type, url, sha256, localized
        }

        /// 按界面语言显示的名称和说明
        var displayName: String {
            PluginManifest.localizedValue(localized, \.name) ?? name
        }

        var displaySummary: String {
            PluginManifest.localizedValue(localized, \.summary) ?? summary
        }

        init(id: String, name: String, summary: String = "", author: String = "", symbol: String = PluginManifest.defaultSymbol,
             type: PluginManifest.Action.Kind = .url, url: String, sha256: String) {
            self.id = id
            self.name = name
            self.summary = summary
            self.author = author
            self.symbol = symbol
            self.type = type.rawValue
            self.url = url
            self.sha256 = sha256.lowercased()
        }

        /// ID、下载地址和 sha256 必须有，缺了这一项就不列出来
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            url = try c.decode(String.self, forKey: .url)
            sha256 = try c.decode(String.self, forKey: .sha256).lowercased()
            name = c.lenient(.name, default: "")
            summary = c.lenient(.summary, default: "")
            author = c.lenient(.author, default: "")
            symbol = c.lenient(.symbol, default: PluginManifest.defaultSymbol)
            type = c.lenient(.type, default: PluginManifest.Action.Kind.url.rawValue)
            localized = c.lenient(.localized, default: [String: PluginManifest.LocalizedText]?.none)
            if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                name = id
            }
        }

        /// 这个版本的 Pop 认识的动作类型；nil 表示要更新 Pop 才能装
        var kind: PluginManifest.Action.Kind? {
            PluginManifest.Action.Kind(rawValue: type)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case format, plugins
    }

    init(format: Int = PluginIndex.currentFormat, plugins: [Entry]) {
        self.format = format
        self.plugins = plugins
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        format = c.lenient(.format, default: Self.currentFormat)
        let entries: [Entry] = c.lossyArray(.plugins) ?? []
        // 同一个 ID 只留第一个
        var seen = Set<String>()
        plugins = entries.filter { seen.insert($0.id).inserted }
    }

    /// 按名称（支持拼音和首字母）、说明、作者搜索
    func entries(matching query: String) -> [Entry] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return plugins }
        return plugins.filter { entry in
            SearchText.matches(trimmed, keys: SearchText.keys(for: entry.name) + SearchText.keys(for: entry.displayName)
                               + [entry.summary.lowercased(), entry.displaySummary.lowercased(), entry.author.lowercased()])
        }
    }
}

/// 插件库：下载索引，下载插件文件并核对 sha256。
enum PluginLibrary {
    /// 索引放在 GitHub 上；第一个地址连不上时换镜像
    static let sources = [
        URL(string: "https://raw.githubusercontent.com/whrss9527/pop/main/plugins/index.json")!,
        URL(string: "https://cdn.jsdelivr.net/gh/whrss9527/pop@main/plugins/index.json")!,
    ]
    /// 插件库在 GitHub 上的文件夹，想分享自己的插件可以提交到这里
    static let browseURL = URL(string: "https://github.com/whrss9527/pop/tree/main/plugins")!
    /// 测试用：指向另一份 index.json（本机文件也行）
    static let overrideVariable = "POP_PLUGIN_INDEX_URL"

    static var defaultSources: [URL] {
        if let override = ProcessInfo.processInfo.environment[overrideVariable].flatMap(URL.init(string:)) {
            return [override]
        }
        return sources
    }

    struct Failure: LocalizedError, Equatable {
        let message: String

        init(_ message: String) {
            self.message = message
        }

        var errorDescription: String? { message }
    }

    /// 读到的索引和它的地址（相对地址按它来算）
    struct Catalog: Equatable {
        var index: PluginIndex
        var source: URL
    }

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        return URLSession(configuration: configuration)
    }

    /// 依次试每个地址，返回第一个读得出来的索引
    static func fetchIndex(from sources: [URL], session: URLSession) async throws -> Catalog {
        var lastError = Failure(String(localized: "连不上插件库"))
        for source in sources {
            do {
                let data = try await download(source, session: session)
                guard let index = try? JSONDecoder().decode(PluginIndex.self, from: data) else {
                    lastError = Failure(String(localized: "插件库的索引读不出来"))
                    continue
                }
                return Catalog(index: index, source: source)
            } catch {
                lastError = error as? Failure ?? Failure(error.localizedDescription)
            }
        }
        throw lastError
    }

    /// 插件文件可以从哪些地址下载：写了完整网址的只用它；相对路径先按读到索引的地址算，再按其他镜像算
    static func candidates(for entry: PluginIndex.Entry, catalog: Catalog, sources: [URL]) -> [URL] {
        if let absolute = URL(string: entry.url), absolute.scheme != nil {
            return [absolute]
        }
        var bases = [catalog.source]
        for source in sources where source != catalog.source {
            bases.append(source)
        }
        return bases.compactMap { URL(string: entry.url, relativeTo: $0)?.absoluteURL }
    }

    /// 下载插件文件，核对后读成插件；一个地址下载不了或者核对不上时换下一个
    static func fetchPlugin(_ entry: PluginIndex.Entry, catalog: Catalog, sources: [URL], session: URLSession) async throws -> PluginManifest {
        guard entry.kind != nil else {
            throw Failure(String(localized: "「\(entry.name)」要更新 Pop 才能安装"))
        }
        var lastError = Failure(String(localized: "下载不了「\(entry.name)」"))
        for url in candidates(for: entry, catalog: catalog, sources: sources) {
            do {
                let data = try await download(url, session: session)
                return try manifest(from: data, entry: entry)
            } catch {
                lastError = error as? Failure ?? Failure(error.localizedDescription)
            }
        }
        throw lastError
    }

    /// 核对下载的内容：sha256 要和索引里的一样，插件 ID 也要一样
    static func manifest(from data: Data, entry: PluginIndex.Entry) throws -> PluginManifest {
        guard Digests.sha256(data) == entry.sha256 else {
            throw Failure(String(localized: "下载的「\(entry.name)」和插件库记录的校验值对不上，没有安装"))
        }
        guard var manifest = try? PluginManifest.makeDecoder().decode(PluginManifest.self, from: data) else {
            throw Failure(String(localized: "「\(entry.name)」不是有效的插件文件"))
        }
        if manifest.id.isEmpty {
            manifest.id = entry.id
        }
        guard manifest.id == entry.id, PluginManifest.isValidID(manifest.id), !BuiltinPluginID.all.contains(manifest.id) else {
            throw Failure(String(localized: "「\(entry.name)」的插件 ID 和插件库记录的不一样，没有安装"))
        }
        if manifest.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            manifest.name = entry.name
        }
        if let problem = manifest.validationError() {
            throw Failure(String(localized: "「\(entry.name)」有问题：\(problem)"))
        }
        return manifest
    }

    private static func download(_ url: URL, session: URLSession) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue(UpdateChecker.userAgent, forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let result: (Data, URLResponse)
        do {
            result = try await session.data(for: request)
        } catch {
            throw Failure(String(localized: "连不上插件库：\(error.localizedDescription)"))
        }
        if let http = result.1 as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw Failure(String(localized: "插件库返回了错误（\(http.statusCode)）"))
        }
        return result.0
    }
}

/// 插件库页面的状态：读索引、安装，记下从插件库装的是哪个版本（插件库里换了新版时显示「更新」）。
@MainActor
final class PluginLibraryModel: ObservableObject {
    enum Phase: Equatable {
        case loading
        case loaded(PluginLibrary.Catalog)
        case failed(String)
    }

    enum EntryState: Equatable {
        case notInstalled
        case installed
        /// 插件库里的版本和装的时候不一样
        case updateAvailable
        /// 要更新 Pop 才能装
        case unsupported
    }

    @Published private(set) var phase: Phase = .loading
    /// 正在安装的插件 ID
    @Published private(set) var installing: Set<String> = []
    /// 从插件库装的插件：ID → 装的时候的 sha256
    @Published private(set) var versions: [String: String]

    private let sources: [URL]
    private let session: URLSession
    private let defaults: UserDefaults

    static let versionsKey = "pop.pluginLibrary.versions"

    init(sources: [URL] = PluginLibrary.defaultSources, session: URLSession = PluginLibrary.makeSession(),
         defaults: UserDefaults = .standard) {
        self.sources = sources
        self.session = session
        self.defaults = defaults
        versions = defaults.dictionary(forKey: Self.versionsKey) as? [String: String] ?? [:]
    }

    var catalog: PluginLibrary.Catalog? {
        if case .loaded(let catalog) = phase {
            return catalog
        }
        return nil
    }

    func load() async {
        phase = .loading
        do {
            let loaded = try await PluginLibrary.fetchIndex(from: sources, session: session)
            phase = .loaded(loaded)
        } catch {
            phase = .failed((error as? PluginLibrary.Failure)?.message ?? error.localizedDescription)
        }
    }

    func state(of entry: PluginIndex.Entry, installedIDs: Set<String>) -> EntryState {
        guard entry.kind != nil else { return .unsupported }
        guard installedIDs.contains(entry.id) else { return .notInstalled }
        if let version = versions[entry.id], version != entry.sha256 {
            return .updateAvailable
        }
        return .installed
    }

    /// 下载、核对并保存到插件文件夹，返回装好的插件。confirm 返回 false 时不装（运行 Shell 脚本的插件先让用户看一眼脚本）。
    func install(_ entry: PluginIndex.Entry, into pluginStore: PluginStore,
                 confirm: @MainActor (PluginManifest) -> Bool = { _ in true }) async throws -> PluginManifest? {
        guard let catalog, !installing.contains(entry.id) else { return nil }
        installing.insert(entry.id)
        defer { installing.remove(entry.id) }
        let manifest = try await PluginLibrary.fetchPlugin(entry, catalog: catalog, sources: sources, session: session)
        if manifest.action.type == .shell, !confirm(manifest) {
            return nil
        }
        let saved = try pluginStore.save(manifest)
        versions[entry.id] = entry.sha256
        defaults.set(versions, forKey: Self.versionsKey)
        return saved
    }
}
