import Combine
import Foundation

struct PluginStoreError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}

/// 用户插件的存储：每个插件是插件文件夹（~/Library/Application Support/Pop/Plugins）里的一个 JSON 文件，
/// 可以直接用文本编辑器修改、拷贝给别人。文件夹有变化时自动重新载入；插件列表通过 iCloud 同步（见 CloudSync）。
@MainActor
final class PluginStore: ObservableObject {
    @Published private(set) var manifests: [PluginManifest] = []
    /// 读取失败的文件（文件名 → 原因），设置里提示用户
    @Published private(set) var loadErrors: [String: String] = [:]

    /// 用户在本机做的修改（包括直接改了文件夹里的文件），CloudSync 订阅它来上传
    let localChanges = PassthroughSubject<Void, Never>()

    /// 本机插件列表最后一次变化的时间。从没改过时是 distantPast，这样新设备会直接采用云端的插件。
    private(set) var modifiedAt: Date

    let directory: URL
    private let defaults: UserDefaults
    /// 插件 ID → 所在文件（手动放进来的文件名不一定是 ID）
    private var files: [String: URL] = [:]
    private var watcher: DispatchSourceFileSystemObject?
    private var pendingReload: DispatchWorkItem?

    static let modifiedAtKey = "pop.plugins.modifiedAt"

    nonisolated static var defaultDirectory: URL {
        let fileManager = FileManager.default
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appending(path: "Library/Application Support", directoryHint: .isDirectory)
        return base.appending(path: "Pop/Plugins", directoryHint: .isDirectory)
    }

    init(directory: URL = PluginStore.defaultDirectory, defaults: UserDefaults = .standard) {
        self.directory = directory
        self.defaults = defaults
        modifiedAt = defaults.object(forKey: Self.modifiedAtKey) as? Date ?? .distantPast
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let loaded = Self.readAll(in: directory)
        manifests = loaded.manifests
        loadErrors = loaded.errors
        files = loaded.files
    }

    // MARK: - 读取

    struct LoadResult {
        var manifests: [PluginManifest]
        var files: [String: URL]
        var errors: [String: String]
    }

    nonisolated static func readAll(in directory: URL) -> LoadResult {
        let fileManager = FileManager.default
        let urls = (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        let decoder = PluginManifest.makeDecoder()
        var result = LoadResult(manifests: [], files: [:], errors: [:])
        for url in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) where url.pathExtension.lowercased() == "json" {
            let fileName = url.lastPathComponent
            guard let data = try? Data(contentsOf: url),
                  var manifest = try? decoder.decode(PluginManifest.self, from: data) else {
                result.errors[fileName] = "不是有效的插件文件"
                continue
            }
            // 手写的文件可以不写 ID 和名称，用文件名代替
            let baseName = url.deletingPathExtension().lastPathComponent
            if manifest.id.isEmpty {
                manifest.id = baseName
            }
            if manifest.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                manifest.name = baseName
            }
            guard PluginManifest.isValidID(manifest.id), !BuiltinPluginID.all.contains(manifest.id) else {
                result.errors[fileName] = "插件 ID「\(manifest.id)」无效，只能包含字母、数字、点、横线和下划线，也不能和内置功能重名"
                continue
            }
            guard result.files[manifest.id] == nil else {
                result.errors[fileName] = "和 \(result.files[manifest.id]?.lastPathComponent ?? "其他文件") 的插件 ID 重复"
                continue
            }
            result.files[manifest.id] = url
            result.manifests.append(manifest)
        }
        result.manifests = sorted(result.manifests)
        return result
    }

    nonisolated static func sorted(_ manifests: [PluginManifest]) -> [PluginManifest] {
        manifests.sorted { a, b in
            let order = a.name.localizedStandardCompare(b.name)
            return order == .orderedSame ? a.id < b.id : order == .orderedAscending
        }
    }

    func manifest(id: String) -> PluginManifest? {
        manifests.first { $0.id == id }
    }

    func fileURL(for id: String) -> URL? {
        files[id]
    }

    // MARK: - 修改

    /// 新建或更新插件，返回实际保存的内容（整理过格式、更新了修改时间）。
    @discardableResult
    func save(_ manifest: PluginManifest) throws -> PluginManifest {
        if let problem = manifest.validationError() {
            throw PluginStoreError(problem)
        }
        guard PluginManifest.isValidID(manifest.id), !BuiltinPluginID.all.contains(manifest.id) else {
            throw PluginStoreError("插件 ID 无效")
        }
        var updated = manifest.normalized()
        updated.modifiedAt = PluginManifest.timestamp()
        try write(updated)
        if let index = manifests.firstIndex(where: { $0.id == updated.id }) {
            manifests[index] = updated
        } else {
            manifests.append(updated)
        }
        manifests = Self.sorted(manifests)
        markLocalChange()
        return updated
    }

    func delete(id: String) {
        if let url = files[id] {
            try? FileManager.default.removeItem(at: url)
        }
        files[id] = nil
        guard manifests.contains(where: { $0.id == id }) else { return }
        manifests.removeAll { $0.id == id }
        markLocalChange()
    }

    /// 导入插件文件。和已有插件 ID 相同时覆盖（相当于更新）；ID 无效或和内置功能冲突时换一个新 ID。
    @discardableResult
    func importFile(at url: URL) throws -> PluginManifest {
        let data = try Data(contentsOf: url)
        guard var manifest = try? PluginManifest.makeDecoder().decode(PluginManifest.self, from: data) else {
            throw PluginStoreError("「\(url.lastPathComponent)」不是有效的插件文件")
        }
        if manifest.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            manifest.name = url.deletingPathExtension().lastPathComponent
        }
        if !PluginManifest.isValidID(manifest.id) || BuiltinPluginID.all.contains(manifest.id) {
            manifest.id = PluginManifest.makeID()
        }
        return try save(manifest)
    }

    func export(_ manifest: PluginManifest, to url: URL) throws {
        let data = try PluginManifest.makeEncoder().encode(manifest.normalized())
        try data.write(to: url, options: .atomic)
    }

    /// 文件夹里的文件被外部修改（手动编辑、拷贝进来、删除）后重新载入。
    func reloadFromDisk() {
        let loaded = Self.readAll(in: directory)
        if loaded.errors != loadErrors {
            loadErrors = loaded.errors
        }
        files = loaded.files
        guard loaded.manifests != manifests else { return }
        manifests = loaded.manifests
        markLocalChange()
    }

    /// 采用 iCloud 上的插件列表：写入云端的每个插件，删掉云端没有的。不会触发回传。
    func applyRemote(_ remote: [PluginManifest], modifiedAt remoteModifiedAt: Date) {
        var seen = Set<String>()
        let valid = remote.filter { manifest in
            guard PluginManifest.isValidID(manifest.id), !BuiltinPluginID.all.contains(manifest.id),
                  !seen.contains(manifest.id) else { return false }
            seen.insert(manifest.id)
            return true
        }
        for manifest in manifests where !seen.contains(manifest.id) {
            if let url = files[manifest.id] {
                try? FileManager.default.removeItem(at: url)
            }
            files[manifest.id] = nil
        }
        for manifest in valid where self.manifest(id: manifest.id) != manifest {
            try? write(manifest)
        }
        manifests = Self.sorted(valid)
        modifiedAt = remoteModifiedAt
        defaults.set(remoteModifiedAt, forKey: Self.modifiedAtKey)
    }

    // MARK: - 监视文件夹

    func startWatching() {
        guard watcher == nil else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let descriptor = open(directory.path(percentEncoded: false), O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor,
                                                               eventMask: [.write, .delete, .rename, .extend],
                                                               queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                self?.scheduleReload()
            }
        }
        source.setCancelHandler {
            close(descriptor)
        }
        source.resume()
        watcher = source
    }

    private func scheduleReload() {
        pendingReload?.cancel()
        // 编辑器保存文件往往是好几步操作，合并成一次重新载入
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.reloadFromDisk()
            }
        }
        pendingReload = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
    }

    // MARK: - 内部

    private func write(_ manifest: PluginManifest) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = files[manifest.id] ?? directory.appending(path: "\(manifest.id).json")
        let data = try PluginManifest.makeEncoder().encode(manifest)
        try data.write(to: url, options: .atomic)
        files[manifest.id] = url
    }

    private func markLocalChange() {
        modifiedAt = Date()
        defaults.set(modifiedAt, forKey: Self.modifiedAtKey)
        localChanges.send()
    }
}
