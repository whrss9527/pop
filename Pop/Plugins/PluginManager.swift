import AppKit
import Combine
import os

/// 发布页上这个版本的插件包列表（plugins-<版本号>.json，由 scripts/package-plugins.sh 生成）。
struct PluginReleaseIndex: Decodable, Equatable {
    struct Entry: Decodable, Equatable {
        /// 插件包的 ID
        var id: String
        /// 压缩包里插件包的名字（PopXxx.bundle）
        var bundle: String
        /// 压缩包的文件名，和插件包列表在同一个地方
        var file: String
        var sha256: String
        /// 下载大小（字节）
        var size: Int64
        /// 装好后的大小（字节）
        var installedSize: Int64
        /// 插件包自己带的目录信息（插件包文件夹里的 plugin.json）；跟着 Pop 一起发布、Pop 里写好了的插件包可以没有
        var meta: PluginPackageMeta?
    }

    var format: Int
    var version: String
    /// 插件包是哪一次构建的：要和 Pop 的 PopBuildID 一样才能用
    var build: String
    var plugins: [Entry]

    func entry(id: String) -> Entry? {
        plugins.first { $0.id == id }
    }

    /// Pop 发布以后才单独发布的插件包：带着目录信息、Pop 里没写的
    var published: [PluginPackage] {
        plugins.compactMap { entry in
            PluginCatalog.packages.contains { $0.id == entry.id } ? nil : PluginPackage(published: entry)
        }
    }
}

/// 插件包自己带的目录信息：插件包文件夹里的 plugin.json，打包时也写进发布页的插件包列表。
/// Pop 发布以后才单独发布的插件包，Pop 里没写它叫什么、是哪一类，就照这个显示
struct PluginPackageMeta: Codable, Equatable {
    /// 插件包 ID（和 Info.plist 里的 PopPluginID 一样）
    var id: String?
    /// 插件包自己的版本：单独发布了新版本时，装着旧版本的 Pop 在后台换成新的
    var version: String?
    /// 语言（zh-Hans、en）→ 名字、介绍
    var name: [String: String]
    var summary: [String: String]
    /// SF Symbol 名称
    var symbol: String
    /// 分类：text、ai、convert、developer、screen、recording、files、other
    var category: String
    /// 提供的功能（功能 ID）
    var functions: [String]
    var defaultsKeys: [String]?
    var keychainAccounts: [String]?
    var dataFolders: [String]?

    /// 插件包里放着它的文件（Contents/Resources/plugin.json）
    static func read(bundle url: URL) -> PluginPackageMeta? {
        guard let data = try? Data(contentsOf: url.appendingPathComponent("Contents/Resources/plugin.json")) else { return nil }
        return try? JSONDecoder().decode(PluginPackageMeta.self, from: data)
    }
}

extension PluginPackage {
    /// 发布页上单独发布的插件包：照它自己带的目录信息。名字、介绍按界面语言挑；
    /// 插件包的名字只能是文件名（不带路径），卸载时只删 pop. 开头的偏好
    init?(published entry: PluginReleaseIndex.Entry, chinese: Bool = Localization.isChinese) {
        guard let meta = entry.meta, !meta.functions.isEmpty, entry.bundle.hasSuffix(".bundle") else { return nil }
        let bundleName = String(entry.bundle.dropLast(".bundle".count))
        guard !bundleName.isEmpty, !bundleName.contains("/"), !bundleName.hasPrefix(".") else { return nil }
        func text(_ values: [String: String]) -> String {
            values[chinese ? "zh-Hans" : "en"] ?? values["zh-Hans"] ?? values["en"] ?? entry.id
        }
        self.init(id: entry.id, bundleName: bundleName, name: text(meta.name), summary: text(meta.summary), symbol: meta.symbol,
                  category: BuiltinCategory(key: meta.category) ?? .other, functions: meta.functions,
                  defaultsKeys: (meta.defaultsKeys ?? []).filter { $0.hasPrefix("pop.") },
                  keychainAccounts: meta.keychainAccounts ?? [], dataFolders: meta.dataFolders ?? [])
    }
}

/// 哪些插件包是新的。还没记过看过哪些时（第一次读到插件包列表），现在有的都算看过：
/// 刚装好 Pop、刚更新到会标「新」的版本时不会一下子全标上，之后发布的、Pop 新版本里加的才标
enum PluginNewness {
    static func update(seen: Set<String>?, current: Set<String>) -> (seen: Set<String>, new: Set<String>) {
        guard let seen else { return (current, []) }
        return (seen, current.subtracting(seen))
    }
}

enum PluginInstallError: LocalizedError, Equatable {
    /// 自己构建的 Pop 没有发布页，也就没有可以下载的插件包
    case noRelease
    case server(Int)
    case badIndex
    case notInIndex
    /// 发布页上的插件包和这个 Pop 不是同一次构建的
    case wrongBuild
    case checksumMismatch
    case extract(String)
    case load(String)

    var errorDescription: String? {
        switch self {
        case .noRelease: return String(localized: "这个 Pop 是自己构建的，发布页上没有对应的插件包")
        case .server(let code): return String(localized: "GitHub 返回了 \(code)")
        case .badIndex: return String(localized: "读不懂发布页上的插件包列表")
        case .notInIndex: return String(localized: "这个版本没有发布这个插件包")
        case .wrongBuild: return String(localized: "发布页上的插件包和这个 Pop 对不上，请先更新 Pop")
        case .checksumMismatch: return String(localized: "下载的插件包校验和不对，可能没下载完整或者被篡改了")
        case .extract(let text): return String(localized: "解压失败：\(text)")
        case .load(let text): return String(localized: "装载失败：\(text)")
        }
    }
}

/// 插件包的安装、卸载和更新。
///
/// 设置里的 installedPlugins 记着要用哪些功能（会随 iCloud 同步）。插件包提供的功能在里面，就要把插件包装上；
/// 都不在里面了就卸载。这里对照设置和这台 Mac 上的插件包：缺的从发布页下载，不要的删掉，
/// 和这个 Pop 不是同一次构建的（Pop 更新了）换成对应的版本。
@MainActor
final class PluginManager: ObservableObject {
    enum Status: Equatable {
        case notInstalled
        case installing
        case installed
        case failed(String)
    }

    /// 每个插件包现在的状态
    @Published private(set) var statuses: [String: Status] = [:]
    /// 装好的插件包占了多大（字节）：插件包本身
    @Published private(set) var sizes: [String: Int64] = [:]
    /// 发布页上的插件包列表：没装的插件包显示下载大小
    @Published private(set) var index: PluginReleaseIndex?
    /// 读不到插件包列表时的原因
    @Published private(set) var indexError: String?
    /// 单独发布了新版本、已经在后台换好的插件包：装载着的还是旧的，下次打开 Pop 时用新的
    @Published private(set) var updatedOnDisk: Set<String> = []
    /// 新出的插件包：还没在「设置 → 功能」里看过的，名字旁边标「新」
    @Published private(set) var newPackageIDs: Set<String> = []

    /// 「控制台」里按子系统 io.github.whrss9527.pop、类别 plugins 过滤
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Pop", category: "plugins")

    private let settingsStore: SettingsStore
    private let registry: PluginRegistry
    private var cancellables = Set<AnyCancellable>()
    private var indexTask: Task<PluginReleaseIndex, Error>?
    /// 插件包列表是什么时候读的（从发布页，或者本机存的那份）
    private var indexLoadedAt: Date?
    /// 正在后台换新版本的插件包
    private var updating: Set<String> = []

    /// 打开设置时插件包列表超过这么久就再读一次；平时（Pop 启动时）超过 6 小时才读
    static let settingsRefreshAge: TimeInterval = 10 * 60
    static let backgroundRefreshAge: TimeInterval = 6 * 3600

    init(settingsStore: SettingsStore, registry: PluginRegistry) {
        self.settingsStore = settingsStore
        self.registry = registry
        loadCachedIndex()
        refreshStatuses()
    }

    /// 启动时：老用户先迁移设置，再对照设置装上、卸载插件包；之后设置变了（包括 iCloud 同步过来的）再对照一次
    func start() {
        let onDisk = Set(PluginCatalog.packages.filter { isOnDisk($0) }.map(\.id))
        let recent = Set(PluginUsage.shared.lastUsed.keys)
        settingsStore.update { settings in
            _ = settings.adoptPluginBundles(recentlyUsed: recent, onDisk: onDisk)
        }
        // CI 用：POP_INSTALL_PLUGINS=all 时装上所有插件包，检查每一个都装载得上（App Store 版是从 App 里装载）
        if ProcessInfo.processInfo.environment["POP_INSTALL_PLUGINS"] == "all" {
            settingsStore.update { settings in
                for id in PluginCatalog.packages.flatMap(\.functions) {
                    settings.setInstalled(id, true)
                }
            }
        }
        reconcile()
        settingsStore.$settings
            .map(\.installedPlugins)
            .removeDuplicates()
            .dropFirst()
            // 等这次设置改完再对照
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.reconcile()
                }
            }
            .store(in: &cancellables)
        // App Store 版的插件包都在 App 里，不从网上读列表、不下载新版本
        guard PluginBundles.bundledDirectory == nil else { return }
        // 本机存的那份插件包列表里，装着的插件包有新版本的先换上；再去发布页看有没有新的插件包、新版本
        if let index {
            updateOutdated(index)
        }
        Task { _ = try? await loadIndex(maxAge: Self.backgroundRefreshAge) }
    }

    func status(of package: PluginPackage) -> Status {
        statuses[package.id] ?? .notInstalled
    }

    /// 在设置里装上：把插件包的功能加进设置，对照设置时就会下载装上
    func install(_ package: PluginPackage) {
        statuses[package.id] = .notInstalled
        settingsStore.update { settings in
            for id in package.functions {
                settings.setInstalled(id, true)
            }
        }
        reconcile()
    }

    /// 在设置里卸载：从圆盘、快捷键里拿掉它的功能，删掉插件包和它的偏好
    func uninstall(_ package: PluginPackage) {
        settingsStore.update { settings in
            for id in package.functions {
                settings.setInstalled(id, false)
            }
        }
        remove(package, deletingData: true)
    }

    /// 对照设置和这台 Mac 上的插件包
    func reconcile() {
        let settings = settingsStore.settings
        for package in PluginCatalog.all {
            let wanted = package.functions.contains { settings.isInstalled($0) }
            if let item = PluginBundles.shared.loadedBundle(package.id), item.external {
                // POP_PLUGIN_DIR 里的（测试、截图用）不归这里管
                continue
            }
            let loaded = PluginBundles.shared.isLoaded(package.id)
            switch status(of: package) {
            case .installing:
                continue
            case .failed:
                // 装失败的等用户点「重试」，不要一直重试
                if wanted { continue }
            default:
                break
            }
            if wanted && !loaded {
                // 先标上「正在装」：下载开始前又对照一次时不会再下载一遍
                statuses[package.id] = .installing
                Task { await self.download(package) }
            } else if !wanted && (loaded || isOnDisk(package)) {
                // 别的 Mac 上卸载了（iCloud 同步过来）：删掉插件包，偏好留着
                remove(package, deletingData: false)
            }
        }
    }

    // MARK: - 下载、校验、装载

    /// 插件包从哪里下载：发布页上这个版本的附件。POP_PLUGIN_SOURCE 可以换成别的地址或者本地文件夹（测试用）
    nonisolated static var sourceURL: URL? {
        if let value = ProcessInfo.processInfo.environment["POP_PLUGIN_SOURCE"], !value.isEmpty {
            if value.hasPrefix("/") {
                return URL(fileURLWithPath: value, isDirectory: true)
            }
            return URL(string: value.hasSuffix("/") ? value : value + "/")
        }
        let version = UpdateChecker.currentVersion
        // 自己构建的 Pop（0.0.0-dev、0.0.0-ci）没有发布页
        guard !version.hasPrefix("0.0.0") else { return nil }
        return URL(string: "https://github.com/\(UpdateChecker.repository)/releases/download/v\(version)/")
    }

    /// 发布页上这个版本的插件包列表；读过一次就记着
    /// 发布页上这个版本的插件包列表。读过、没超过 maxAge 就用读过的；单独发布了插件包以后列表会变，所以隔一阵子再读
    func loadIndex(maxAge: TimeInterval = PluginManager.settingsRefreshAge) async throws -> PluginReleaseIndex {
        if let index, let indexLoadedAt, Date().timeIntervalSince(indexLoadedAt) < maxAge {
            return index
        }
        if let indexTask {
            return try await indexTask.value
        }
        let task = Task { () throws -> PluginReleaseIndex in
            guard let source = Self.sourceURL else { throw PluginInstallError.noRelease }
            let url = source.appendingPathComponent("plugins-\(UpdateChecker.currentVersion).json")
            let data = try await Self.fetch(url)
            guard let index = try? JSONDecoder().decode(PluginReleaseIndex.self, from: data) else {
                throw PluginInstallError.badIndex
            }
            // 存一份：没网时也知道单独发布的插件包叫什么
            if let cache = Self.indexCacheURL {
                try? FileManager.default.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? data.write(to: cache, options: .atomic)
            }
            return index
        }
        indexTask = task
        do {
            let loaded = try await task.value
            indexTask = nil
            indexError = nil
            indexLoaded(loaded, at: Date())
            return loaded
        } catch {
            indexError = error.localizedDescription
            indexTask = nil
            throw error
        }
    }

    /// 本机存的那份插件包列表（上次从发布页读到的）。POP_PLUGIN_SOURCE 换了地方时（测试用）不存
    nonisolated static var indexCacheURL: URL? {
        if let value = ProcessInfo.processInfo.environment["POP_PLUGIN_SOURCE"], !value.isEmpty {
            return nil
        }
        return PluginPackage.dataDirectory.appending(path: "plugin-index.json")
    }

    /// 启动时先用本机存的那份：单独发布的插件包马上就认得。版本对不上（Pop 更新了）的不用
    private func loadCachedIndex() {
        guard PluginBundles.bundledDirectory == nil,
              let cache = Self.indexCacheURL, let data = try? Data(contentsOf: cache),
              let cached = try? JSONDecoder().decode(PluginReleaseIndex.self, from: data),
              cached.version == UpdateChecker.currentVersion else { return }
        let date = (try? cache.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        indexLoaded(cached, at: date)
    }

    /// 读到了插件包列表：认得单独发布的插件包，对照设置装上要用的，换掉装着的旧版本
    private func indexLoaded(_ loaded: PluginReleaseIndex, at date: Date) {
        index = loaded
        indexLoadedAt = date
        PluginCatalog.setPublished(loaded.published)
        refreshStatuses()
        refreshNewPackages()
        // 启动时 start() 之前读到的：start() 里会对照
        guard !cancellables.isEmpty else { return }
        reconcile()
        updateOutdated(loaded)
    }

    /// 看过的插件包记在这里（插件包 ID）
    static let seenKey = "pop.plugins.seen"

    /// 读到插件包列表以后：算出哪些插件包是新的
    private func refreshNewPackages() {
        let saved = UserDefaults.standard.stringArray(forKey: Self.seenKey).map { Set($0) }
        let result = PluginNewness.update(seen: saved, current: Set(PluginCatalog.all.map(\.id)))
        if result.seen != saved {
            UserDefaults.standard.set(result.seen.sorted(), forKey: Self.seenKey)
        }
        newPackageIDs = result.new
    }

    /// 在「设置 → 功能」里看过插件列表了：现在标着「新」的，以后不再标
    func markPackagesSeen() {
        guard !newPackageIDs.isEmpty else { return }
        let saved = Set(UserDefaults.standard.stringArray(forKey: Self.seenKey) ?? [])
        UserDefaults.standard.set(saved.union(newPackageIDs).sorted(), forKey: Self.seenKey)
        newPackageIDs = []
    }

    /// 装着的插件包单独发布了新版本（插件包里的 plugin.json 版本和列表里的不一样）：在后台下载换上，下次打开 Pop 时用新的
    private func updateOutdated(_ index: PluginReleaseIndex) {
        guard index.build == PluginBundles.appBuildID else { return }
        for item in PluginBundles.shared.loaded where !item.external && !updating.contains(item.id) && !updatedOnDisk.contains(item.id) {
            guard let entry = index.entry(id: item.id), let latest = entry.meta?.version,
                  let package = PluginCatalog.package(id: item.id),
                  let installed = PluginPackageMeta.read(bundle: item.url)?.version, installed != latest else { continue }
            updating.insert(item.id)
            Task {
                defer { updating.remove(item.id) }
                do {
                    _ = try await fetchBundle(package, entry: entry, index: index)
                    updatedOnDisk.insert(item.id)
                    Self.log.notice("updated plugin \(item.id, privacy: .public) on disk to \(latest, privacy: .public)")
                } catch {
                    Self.log.error("could not update plugin \(item.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    /// 设置页打开时读一下插件包列表：显示下载大小，有新的单独发布的插件包也列出来。App Store 版的插件包都在 App 里，不用读
    func refreshIndex() {
        guard PluginBundles.bundledDirectory == nil else { return }
        Task { _ = try? await loadIndex() }
    }

    private func download(_ package: PluginPackage) async {
        statuses[package.id] = .installing
        if let bundled = PluginBundles.bundledDirectory {
            await installBundled(package, from: bundled)
            return
        }
        do {
            let index = try await loadIndex()
            guard let entry = index.entry(id: package.id) else { throw PluginInstallError.notInIndex }
            guard index.build == PluginBundles.appBuildID else { throw PluginInstallError.wrongBuild }
            let target = try await fetchBundle(package, entry: entry, index: index)
            switch await PluginBundles.shared.loadCheckingInBackground(target) {
            case .success:
                break
            case .failure(let error):
                try? FileManager.default.removeItem(at: target)
                throw PluginInstallError.load(String(describing: error))
            }
            Self.log.notice("installed plugin \(package.id, privacy: .public)")
            refreshStatuses()
            registry.reloadBuiltins()
            // 下载期间在设置里卸载了的话，这时候删掉
            reconcile()
        } catch {
            Self.log.error("could not install plugin \(package.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            statuses[package.id] = .failed(error.localizedDescription)
        }
    }

    /// App Store 版：从 Pop.app 里的插件包装载，不下载
    private func installBundled(_ package: PluginPackage, from directory: URL) async {
        let url = directory.appendingPathComponent("\(package.bundleName).bundle", isDirectory: true)
        switch await PluginBundles.shared.loadCheckingInBackground(url) {
        case .success:
            Self.log.notice("loaded bundled plugin \(package.id, privacy: .public)")
            refreshStatuses()
            registry.reloadBuiltins()
            // 装载期间在设置里卸载了的话，这时候拿掉
            reconcile()
        case .failure(let error):
            statuses[package.id] = .failed(PluginInstallError.load(String(describing: error)).localizedDescription)
        }
    }

    /// 下载、校验、解压插件包，放进装插件包的文件夹（换掉原来的），返回放好的位置；不装载。
    /// 换掉正装载着的旧版本时（后台更新），先确认新的签名没问题，免得把能用的换成不能用的
    private func fetchBundle(_ package: PluginPackage, entry: PluginReleaseIndex.Entry, index: PluginReleaseIndex) async throws -> URL {
        guard let source = Self.sourceURL else { throw PluginInstallError.noRelease }
        // 列表里的文件名只能是文件名，不能带路径
        guard !entry.file.contains("/"), !entry.bundle.contains("/") else { throw PluginInstallError.badIndex }
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("pop-plugin-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        let archive = work.appendingPathComponent(entry.file)
        try await Self.download(source.appendingPathComponent(entry.file), size: entry.size, to: archive)
        let actual = try await runInBackground { () -> Result<String, Error> in
            Result { try Checksums.sha256(of: archive) }
        }.get()
        guard actual == entry.sha256.lowercased() else { throw PluginInstallError.checksumMismatch }
        let extracted = work.appendingPathComponent("extracted", isDirectory: true)
        try await Self.extract(archive, to: extracted)
        let bundle = extracted.appendingPathComponent(entry.bundle, isDirectory: true)
        guard PluginBundles.pluginID(of: bundle) == package.id else {
            throw PluginInstallError.extract(String(localized: "压缩包里没有这个插件包"))
        }
        let target = PluginBundles.installedURL(bundleName: package.bundleName)
        if PluginBundles.shared.isLoaded(package.id) {
            guard PluginBundles.buildID(of: bundle) == PluginBundles.appBuildID else { throw PluginInstallError.wrongBuild }
            guard await runInBackground({ CodeSignature.isTrustedPlugin(bundle) }) else {
                throw PluginInstallError.load(String(describing: PluginBundles.LoadError.untrusted))
            }
        }
        try FileManager.default.createDirectory(at: PluginBundles.directory, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: target.path) {
            try FileManager.default.removeItem(at: target)
        }
        try FileManager.default.moveItem(at: bundle, to: target)
        return target
    }

    /// 卸载：拿掉功能，删掉插件包；deletingData 时连偏好、密钥、数据文件夹一起删
    private func remove(_ package: PluginPackage, deletingData: Bool) {
        PluginBundles.shared.unload(package.id)
        try? FileManager.default.removeItem(at: PluginBundles.installedURL(bundleName: package.bundleName))
        if deletingData {
            for key in package.defaultsKeys {
                UserDefaults.standard.removeObject(forKey: key)
            }
            for account in package.keychainAccounts {
                KeychainSecret(service: PluginPackage.keychainService(package.id), account: account, label: "").save("")
            }
            for folder in package.dataFolders where !folder.isEmpty && !folder.contains("..") {
                try? FileManager.default.removeItem(at: PluginPackage.dataDirectory.appending(path: folder, directoryHint: .isDirectory))
            }
        }
        updatedOnDisk.remove(package.id)
        Self.log.notice("removed plugin \(package.id, privacy: .public)")
        statuses[package.id] = .notInstalled
        refreshStatuses()
        registry.reloadBuiltins()
    }

    private func isOnDisk(_ package: PluginPackage) -> Bool {
        FileManager.default.fileExists(atPath: PluginBundles.installedURL(bundleName: package.bundleName).path)
    }

    /// 按装载情况重新算每个插件包的状态和大小；正在装的、装失败的保持原样
    private func refreshStatuses() {
        for package in PluginCatalog.all {
            if let loaded = PluginBundles.shared.loadedBundle(package.id) {
                statuses[package.id] = .installed
                sizes[package.id] = Self.size(of: loaded.url)
            } else {
                sizes[package.id] = nil
                switch statuses[package.id] {
                case .installing?, .failed?:
                    break
                default:
                    statuses[package.id] = .notInstalled
                }
            }
        }
    }

    /// 文件夹占了多大（字节）
    nonisolated static func size(of url: URL) -> Int64 {
        let keys: [URLResourceKey] = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            guard let values = try? file.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        return total
    }

    // MARK: - 网络和文件

    /// 读一个不大的文件（插件包列表）；本地文件夹（测试用）直接读
    private nonisolated static func fetch(_ url: URL) async throws -> Data {
        if url.isFileURL {
            return try Data(contentsOf: url)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 60
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        var request = URLRequest(url: url)
        request.setValue(UpdateChecker.userAgent, forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw PluginInstallError.server(http.statusCode)
        }
        return data
    }

    private nonisolated static func download(_ url: URL, size: Int64, to destination: URL) async throws {
        if url.isFileURL {
            try FileManager.default.copyItem(at: url, to: destination)
            return
        }
        try await UpdateInstaller.download(url, expectedSize: Int(size), to: destination, progress: { _ in })
    }

    private nonisolated static func extract(_ archive: URL, to directory: URL) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let result = await ProcessRunner.run(URL(fileURLWithPath: "/usr/bin/ditto"),
                                             arguments: ["-x", "-k", archive.path(percentEncoded: false), directory.path(percentEncoded: false)],
                                             stdin: nil, environment: [:], timeout: 120)
        switch result {
        case .success(let output) where output.status == 0 && !output.timedOut:
            return
        case .success(let output):
            throw PluginInstallError.extract(output.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        case .failure(let error):
            throw PluginInstallError.extract(error.localizedDescription)
        }
    }
}
