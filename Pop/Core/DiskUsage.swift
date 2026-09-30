import Foundation

/// 文件夹里各部分占了多少空间：扫一遍，记下每个文件夹（连同子文件夹）的总大小和文件数，以及最大的几个文件，
/// 之后可以一层层点进去看。按文件在磁盘上实际占的空间算，隐藏文件和 App 这类包里面的文件也算。
enum DiskUsage {
    struct Item: Identifiable, Equatable {
        var url: URL
        var size: Int64
        /// 文件夹里一共几个文件（文件本身算 1）
        var files: Int
        /// 能点进去看的文件夹（App 这类包不算）
        var isFolder: Bool

        var id: URL { url }
    }

    struct Totals: Equatable {
        var size: Int64 = 0
        var files = 0
    }

    struct Progress: Equatable {
        var files = 0
        var size: Int64 = 0
    }

    struct Result: Equatable {
        var root: URL
        /// 每个文件夹（按 DiskUsage.key 记）连同子文件夹里全部文件加起来
        var folders: [String: Totals]
        /// 最大的几个文件，从大到小
        var largest: [Item]
        /// 文件太多，只看了前面一部分
        var truncated: Bool

        var total: Totals { folders[DiskUsage.key(root)] ?? Totals() }

        func totals(of folder: URL) -> Totals {
            folders[DiskUsage.key(folder)] ?? Totals()
        }
    }

    static let fileLimit = 2_000_000
    private static let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .isPackageKey,
                                                 .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey]

    /// 路径（结尾不带 /），当字典的键。扫描时从标准化过的 root 往下走，下面的路径都是在它后面接上名字，不用再标准化
    static func key(_ url: URL) -> String {
        var path = url.path(percentEncoded: false)
        while path.hasSuffix("/") && path != "/" {
            path.removeLast()
        }
        return path
    }

    /// 文件在磁盘上占的空间
    static func allocatedSize(_ values: URLResourceValues) -> Int64 {
        Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0)
    }

    static func scan(_ folder: URL, limit: Int = fileLimit, keep: Int = 30, isCancelled: () -> Bool = { false },
                     progress: (Progress) -> Void = { _ in }) -> Result {
        let root = folder.standardizedFileURL
        let rootKey = key(root)
        let keySet = Set(keys)
        // 先记每个文件夹里直接放着的文件，扫完再从最深的一层往上加
        var folders: [String: Totals] = [rootKey: Totals()]
        var largest: [Item] = []
        var state = Progress()
        var truncated = false
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: [],
                                                        errorHandler: { _, _ in true })
        while let url = enumerator?.nextObject() as? URL {
            if isCancelled() { break }
            guard let values = try? url.resourceValues(forKeys: keySet), values.isSymbolicLink != true else { continue }
            if values.isDirectory == true {
                let path = key(url)
                if folders[path] == nil {
                    folders[path] = Totals()
                }
                continue
            }
            guard values.isRegularFile == true else { continue }
            let bytes = allocatedSize(values)
            let parent = key(url.deletingLastPathComponent())
            folders[parent, default: Totals()].size += bytes
            folders[parent, default: Totals()].files += 1
            state.files += 1
            state.size += bytes
            largest.append(Item(url: url, size: bytes, files: 1, isFolder: false))
            if largest.count >= keep * 4 {
                largest = Array(largest.sorted { $0.size > $1.size }.prefix(keep))
            }
            if state.files % 2000 == 0 {
                progress(state)
            }
            if state.files >= limit {
                truncated = true
                break
            }
        }
        // 从最深的文件夹开始，把每个文件夹的合计加到上一层
        var byDepth: [Int: [String]] = [:]
        for path in folders.keys where path != rootKey {
            byDepth[depth(of: path), default: []].append(path)
        }
        for path in byDepth.keys.sorted(by: >).flatMap({ byDepth[$0] ?? [] }) {
            guard let totals = folders[path] else { continue }
            let parent = (path as NSString).deletingLastPathComponent
            guard parent.hasPrefix(rootKey) else { continue }
            folders[parent, default: Totals()].size += totals.size
            folders[parent, default: Totals()].files += totals.files
        }
        return Result(root: root, folders: folders, largest: Array(largest.sorted { $0.size > $1.size }.prefix(keep)),
                      truncated: truncated)
    }

    /// 路径有几层（数 /）
    static func depth(of path: String) -> Int {
        var count = 0
        for byte in path.utf8 where byte == UInt8(ascii: "/") {
            count += 1
        }
        return count
    }

    /// 文件夹下一层的东西，从大到小
    static func children(of folder: URL, in result: Result) -> [Item] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys, options: [])) ?? []
        return urls.compactMap { url -> Item? in
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isSymbolicLink != true else { return nil }
            if values.isDirectory == true {
                let totals = result.totals(of: url)
                return Item(url: url, size: totals.size, files: totals.files, isFolder: values.isPackage != true)
            }
            return Item(url: url, size: allocatedSize(values), files: 1, isFolder: false)
        }.sorted { lhs, rhs in
            if lhs.size != rhs.size {
                return lhs.size > rhs.size
            }
            return lhs.url.lastPathComponent.localizedStandardCompare(rhs.url.lastPathComponent) == .orderedAscending
        }
    }

    /// 移到废纸篓之后：从上面各层的合计里减掉，最大的文件里去掉它（和它里面的）
    static func removing(_ item: Item, from result: Result) -> Result {
        var updated = result
        let removed = key(item.url)
        let rootKey = key(result.root)
        var parent = (removed as NSString).deletingLastPathComponent
        while parent.hasPrefix(rootKey) {
            updated.folders[parent]?.size -= item.size
            updated.folders[parent]?.files -= item.files
            if parent == rootKey { break }
            parent = (parent as NSString).deletingLastPathComponent
        }
        updated.folders = updated.folders.filter { $0.key != removed && !$0.key.hasPrefix(removed + "/") }
        updated.largest.removeAll { key($0.url) == removed || key($0.url).hasPrefix(removed + "/") }
        return updated
    }

    /// 相对 root 的路径：「下载/安装包.dmg」
    static func relativePath(_ url: URL, in root: URL) -> String {
        let path = key(url)
        let base = key(root)
        guard path.hasPrefix(base + "/") else { return url.lastPathComponent }
        return String(path.dropFirst(base.count + 1))
    }
}
