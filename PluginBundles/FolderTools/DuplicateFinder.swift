import CryptoKit
import Foundation
@testable import Pop

/// 找出内容完全一样的文件：先按大小分组，大小一样的比开头一小段，还一样的再算整个文件的 SHA-256。
/// 隐藏文件、App 这类包里面的文件和空文件不算。
enum DuplicateFinder {
    struct Group: Identifiable, Equatable {
        /// 文件内容的 SHA-256
        var id: String
        var size: Int64
        /// 最早创建的在最前面（默认留它）
        var files: [URL]

        /// 只留一个时能腾出的空间
        var wasted: Int64 { size * Int64(max(files.count - 1, 0)) }
    }

    struct Progress: Equatable {
        var scanned = 0
        var hashed = 0
        var toHash = 0
    }

    struct Result: Equatable {
        var groups: [Group]
        var scanned: Int
        /// 文件太多，只看了前面一部分
        var truncated: Bool

        var wasted: Int64 { groups.reduce(0) { $0 + $1.wasted } }
    }

    static let fileLimit = 100_000

    /// 文件夹里（包括子文件夹）的普通文件和大小
    static func files(in roots: [URL], limit: Int = fileLimit, isCancelled: () -> Bool = { false })
        -> (files: [(url: URL, size: Int64)], truncated: Bool) {
        var result: [(url: URL, size: Int64)] = []
        var seen = Set<String>()
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .isSymbolicLinkKey]
        for root in roots {
            guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys,
                                                                  options: [.skipsHiddenFiles, .skipsPackageDescendants],
                                                                  errorHandler: { _, _ in true }) else { continue }
            for case let url as URL in enumerator {
                if isCancelled() { return (result, false) }
                guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true,
                      values.isSymbolicLink != true, let size = values.fileSize, size > 0 else { continue }
                // 选了父文件夹又选了子文件夹时，同一个文件只算一次
                guard seen.insert(url.standardizedFileURL.path(percentEncoded: false)).inserted else { continue }
                result.append((url, Int64(size)))
                if result.count >= limit {
                    return (result, true)
                }
            }
        }
        return (result, false)
    }

    static func find(in roots: [URL], limit: Int = fileLimit, isCancelled: () -> Bool = { false },
                     progress: (Progress) -> Void = { _ in }) -> Result {
        let listing = files(in: roots, limit: limit, isCancelled: isCancelled)
        var state = Progress(scanned: listing.files.count)
        // 大小一样的才可能重复
        let bySize = Dictionary(grouping: listing.files, by: { $0.size }).filter { $0.value.count > 1 }
        state.toHash = bySize.values.reduce(0) { $0 + $1.count }
        progress(state)
        var groups: [Group] = []
        var reported = 0
        for (size, candidates) in bySize {
            if isCancelled() { break }
            // 先比开头 16 KB，大部分不一样的文件在这一步就分开了
            let byHead = Dictionary(grouping: candidates.map { $0.url }) { hash($0, limit: 16 * 1024) ?? UUID().uuidString }
                .filter { $0.value.count > 1 }
            for urls in byHead.values {
                let byContent = Dictionary(grouping: urls) { hash($0) ?? UUID().uuidString }
                for (digest, same) in byContent where same.count > 1 {
                    groups.append(Group(id: digest, size: size, files: ordered(same)))
                }
            }
            state.hashed += candidates.count
            // 每比完一百来个文件报一次进度，不要太频繁
            if state.hashed - reported >= 100 {
                reported = state.hashed
                progress(state)
            }
        }
        groups.sort { lhs, rhs in
            if lhs.wasted != rhs.wasted {
                return lhs.wasted > rhs.wasted
            }
            return lhs.files[0].lastPathComponent < rhs.files[0].lastPathComponent
        }
        return Result(groups: groups, scanned: listing.files.count, truncated: listing.truncated)
    }

    /// 最早创建的在前面，一样早的按路径排
    static func ordered(_ urls: [URL]) -> [URL] {
        struct Entry {
            var url: URL
            var created: Date
            var path: String
        }
        let entries = urls.map { url -> Entry in
            let date = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantFuture
            return Entry(url: url, created: date, path: url.path(percentEncoded: false))
        }
        let sorted = entries.sorted { lhs, rhs in
            if lhs.created != rhs.created {
                return lhs.created < rhs.created
            }
            return lhs.path.localizedStandardCompare(rhs.path) == .orderedAscending
        }
        return sorted.map { $0.url }
    }

    /// 文件内容的 SHA-256（limit 不为空时只算开头这么多字节）
    static func hash(_ url: URL, limit: Int? = nil) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        var remaining = limit ?? Int.max
        while remaining > 0 {
            guard let chunk = try? handle.read(upToCount: min(1 << 20, remaining)), !chunk.isEmpty else { break }
            hasher.update(data: chunk)
            remaining -= chunk.count
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// 移到废纸篓，返回移走了哪些、哪些没能移走（原因）
    static func trash(_ urls: [URL]) -> (moved: [URL], failures: [String]) {
        var moved: [URL] = []
        var failures: [String] = []
        for url in urls {
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                moved.append(url)
            } catch {
                failures.append(String(localized: "\(url.lastPathComponent)：\(error.localizedDescription)"))
            }
        }
        return (moved, failures)
    }
}
