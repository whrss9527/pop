import Foundation

/// 比较两个文件夹（包括子文件夹）：只在一边有的文件、两边都有但内容不一样的文件。
/// 按相对路径对上号，大小一样的再比 SHA-256；隐藏文件和 App 这类包里面的文件不比较。
enum FolderCompare {
    struct Result: Equatable {
        var left: URL
        var right: URL
        var onlyLeft: [String]
        var onlyRight: [String]
        var different: [String]
        var same: Int
        /// 文件太多，只比了一部分
        var truncated: Bool

        var isIdentical: Bool { onlyLeft.isEmpty && onlyRight.isEmpty && different.isEmpty }
    }

    static let fileLimit = 50_000

    /// 文件夹里的普通文件：相对路径（用 / 隔开）→ 大小
    static func files(in folder: URL, limit: Int = fileLimit) -> (files: [String: Int64], truncated: Bool) {
        let root = DiskUsage.resolved(folder)
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .isSymbolicLinkKey]
        let keySet = Set(keys)
        var result: [String: Int64] = [:]
        // 遍历给出的路径里根文件夹的写法：第一项一定在根文件夹下面
        var base: String?
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys,
                                                        options: [.skipsHiddenFiles, .skipsPackageDescendants],
                                                        errorHandler: { _, _ in true })
        while let url = enumerator?.nextObject() as? URL {
            if base == nil {
                base = DiskUsage.key(url.deletingLastPathComponent())
            }
            guard let values = try? url.resourceValues(forKeys: keySet), values.isRegularFile == true,
                  values.isSymbolicLink != true, let base else { continue }
            let path = DiskUsage.key(url)
            guard path.hasPrefix(base + "/") else { continue }
            let relative = String(path.dropFirst(base.count + 1))
            result[relative] = Int64(values.fileSize ?? 0)
            if result.count >= limit {
                return (result, true)
            }
        }
        return (result, false)
    }

    static func compare(_ left: URL, _ right: URL, isCancelled: () -> Bool = { false }) -> Result {
        let first = files(in: left)
        let second = files(in: right)
        let leftRoot = DiskUsage.resolved(left)
        let rightRoot = DiskUsage.resolved(right)
        var onlyLeft: [String] = []
        var different: [String] = []
        var same = 0
        for (path, size) in first.files {
            if isCancelled() { break }
            guard let otherSize = second.files[path] else {
                onlyLeft.append(path)
                continue
            }
            guard size == otherSize else {
                different.append(path)
                continue
            }
            let leftHash = DuplicateFinder.hash(leftRoot.appending(path: path))
            let rightHash = DuplicateFinder.hash(rightRoot.appending(path: path))
            if leftHash != nil && leftHash == rightHash {
                same += 1
            } else {
                different.append(path)
            }
        }
        let onlyRight = second.files.keys.filter { first.files[$0] == nil }
        return Result(left: left, right: right, onlyLeft: sorted(onlyLeft), onlyRight: sorted(Array(onlyRight)),
                      different: sorted(different), same: same, truncated: first.truncated || second.truncated)
    }

    /// 按路径排（数字按大小：第 2 页在第 10 页前面）
    static func sorted(_ paths: [String]) -> [String] {
        paths.sorted { lhs, rhs in lhs.localizedStandardCompare(rhs) == .orderedAscending }
    }

    /// 卡片上怎么称呼两个文件夹：名字一样时往上找到第一层不一样的文件夹，带上它的名字
    static func names(_ left: URL, _ right: URL) -> (left: String, right: String) {
        let a = left.standardizedFileURL.pathComponents
        let b = right.standardizedFileURL.pathComponents
        let nameA = a.last ?? left.lastPathComponent
        let nameB = b.last ?? right.lastPathComponent
        guard nameA == nameB else { return (nameA, nameB) }
        var common = 0
        while common < min(a.count, b.count), a[a.count - 1 - common] == b[b.count - 1 - common] {
            common += 1
        }
        // 同一个文件夹选了两次
        guard common < a.count, common < b.count else {
            return ("第一个 " + nameA, "第二个 " + nameB)
        }
        let joiner = common > 1 ? "/…/" : "/"
        return (a[a.count - 1 - common] + joiner + nameA, b[b.count - 1 - common] + joiner + nameB)
    }

    /// 结果卡片：一句话总结，下面按「内容不同」「只在 A 里」「只在 B 里」分页列出路径
    static func card(_ result: Result) -> ResultCard {
        let labels = names(result.left, result.right)
        let shown = 500
        func list(_ paths: [String]) -> String {
            var lines = Array(paths.prefix(shown))
            if paths.count > shown {
                lines.append("……还有 \(paths.count - shown) 个")
            }
            return lines.joined(separator: "\n")
        }
        var tabs: [ResultCard.Tab] = []
        if !result.different.isEmpty {
            tabs.append(ResultCard.Tab(title: "内容不同 \(result.different.count)", text: list(result.different)))
        }
        if !result.onlyLeft.isEmpty {
            tabs.append(ResultCard.Tab(title: "只在「\(labels.left)」里 \(result.onlyLeft.count)", text: list(result.onlyLeft)))
        }
        if !result.onlyRight.isEmpty {
            tabs.append(ResultCard.Tab(title: "只在「\(labels.right)」里 \(result.onlyRight.count)", text: list(result.onlyRight)))
        }
        var detail = "一样的 \(result.same) 个，内容不同 \(result.different.count) 个，只在一边有的 \(result.onlyLeft.count + result.onlyRight.count) 个；"
            + "隐藏文件和 App 这类包里面的文件不比较"
        if result.truncated {
            detail += "，文件太多只比了前 \(fileLimit) 个"
        }
        let body = result.isIdentical ? "两个文件夹里的 \(result.same) 个文件完全一样" : ""
        return ResultCard(title: "比较文件夹", body: body, detail: detail, tabs: tabs)
    }
}
