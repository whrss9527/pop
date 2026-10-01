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
    }

    var format: Int
    var version: String
    /// 插件包是哪一次构建的：要和 Pop 的 PopBuildID 一样才能用
    var build: String
    var plugins: [Entry]

    func entry(id: String) -> Entry? {
        plugins.first { $0.id == id }
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

    /// 「控制台」里按子系统 io.github.whrss9527.pop、类别 plugins 过滤
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Pop", category: "plugins")

    private let settingsStore: SettingsStore
    private let registry: PluginRegistry
    private var cancellables = Set<AnyCancellable>()
    private var indexTask: Task<PluginReleaseIndex, Error>?

    init(settingsStore: SettingsStore, registry: PluginRegistry) {
        self.settingsStore = settingsStore
        self.registry = registry
        refreshStatuses()
    }

    /// 启动时：老用户先迁移设置，再对照设置装上、卸载插件包；之后设置变了（包括 iCloud 同步过来的）再对照一次
    func start() {
        let onDisk = Set(PluginCatalog.packages.filter { isOnDisk($0) }.map(\.id))
        let recent = Set(PluginUsage.shared.lastUsed.keys)
        settingsStore.update { settings in
            _ = settings.adoptPluginBundles(recentlyUsed: recent, onDisk: onDisk)
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
        for package in PluginCatalog.packages {
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
    func loadIndex() async throws -> PluginReleaseIndex {
        if let index {
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
            return index
        }
        indexTask = task
        do {
            let loaded = try await task.value
            index = loaded
            indexError = nil
            indexTask = nil
            return loaded
        } catch {
            indexError = error.localizedDescription
            indexTask = nil
            throw error
        }
    }

    /// 设置页打开时读一下插件包列表，显示下载大小
    func refreshIndex() {
        guard index == nil else { return }
        Task { _ = try? await loadIndex() }
    }

    private func download(_ package: PluginPackage) async {
        statuses[package.id] = .installing
        do {
            let index = try await loadIndex()
            guard let entry = index.entry(id: package.id) else { throw PluginInstallError.notInIndex }
            guard index.build == PluginBundles.appBuildID else { throw PluginInstallError.wrongBuild }
            guard let source = Self.sourceURL else { throw PluginInstallError.noRelease }
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
            try FileManager.default.createDirectory(at: PluginBundles.directory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: target.path) {
                try FileManager.default.removeItem(at: target)
            }
            try FileManager.default.moveItem(at: bundle, to: target)
            switch PluginBundles.shared.load(target) {
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

    /// 卸载：拿掉功能，删掉插件包；deletingData 时连偏好一起删
    private func remove(_ package: PluginPackage, deletingData: Bool) {
        PluginBundles.shared.unload(package.id)
        try? FileManager.default.removeItem(at: PluginBundles.installedURL(bundleName: package.bundleName))
        if deletingData {
            for key in package.defaultsKeys {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
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
        for package in PluginCatalog.packages {
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
