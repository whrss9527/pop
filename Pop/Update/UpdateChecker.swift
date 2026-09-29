import Foundation

/// GitHub 上的一个发布版本，以及一键更新需要的附件。
struct ReleaseInfo: Equatable {
    var version: String
    var tag: String
    var title: String
    var pageURL: URL
    var notes: String
    var publishedAt: Date?
    var isPrerelease: Bool
    /// 一键更新下载的压缩包（Pop-版本号.zip）
    var archiveURL: URL?
    var archiveName: String?
    var archiveSize: Int?
    /// SHA256SUMS.txt：每行「哈希  文件名」
    var checksumsURL: URL?

    /// 有压缩包和校验文件才能在 Pop 里直接安装，否则只能去发布页手动下载。
    var canInstall: Bool { archiveURL != nil && checksumsURL != nil }
}

enum UpdateError: LocalizedError, Equatable {
    case server(Int)
    case badResponse
    case noArchive
    case checksumsMissing
    case checksumMismatch
    case extract(String)
    case appNotFound
    case wrongApp(String)
    case notInstallable(String)
    case install(String)
    case cancelledByUser
    /// macOS 不让替换（「App 管理」权限或者别的系统保护）
    case appManagement
    /// 新版本的签名和当前版本不是同一个证书
    case wrongSigner

    var errorDescription: String? {
        switch self {
        case .server(let code): return "GitHub 返回了 \(code)"
        case .badResponse: return "读不懂 GitHub 返回的内容"
        case .noArchive: return "这个版本没有可以直接安装的附件，请到发布页手动下载"
        case .checksumsMissing: return "校验文件里没有这个附件的校验和"
        case .checksumMismatch: return "下载的文件校验和不对，可能没下载完整或者被篡改了"
        case .extract(let text): return "解压失败：\(text)"
        case .appNotFound: return "压缩包里没有 Pop.app"
        case .wrongApp(let text): return "下载的程序不对：\(text)"
        case .notInstallable(let text): return text
        case .install(let text): return "替换程序失败：\(text)"
        case .cancelledByUser: return "已取消授权，Pop 没有改动"
        case .appManagement: return "macOS 不允许 Pop 替换自己：到「系统设置 → 隐私与安全性 → App 管理」里打开 Pop，再点重试"
        case .wrongSigner: return "新版本和当前版本不是用同一个证书签名的，为了安全没有安装。可以到发布页确认后手动下载"
        }
    }
}

/// 从 GitHub Releases 检查新版本。
enum UpdateChecker {
    static let repository = "whrss9527/pop"
    static let checksumsName = "SHA256SUMS.txt"
    /// 测试用：指向一个返回 GitHub releases 格式 JSON 的地址（数组或单个发布都行），就能在本机假装发布新版本。
    static let overrideVariable = "POP_UPDATE_URL"

    static var releasesPageURL: URL {
        URL(string: "https://github.com/\(repository)/releases")!
    }

    static var overrideURL: URL? {
        ProcessInfo.processInfo.environment[overrideVariable].flatMap(URL.init(string:))
    }

    /// 测试版（预发布）也要能收到，所以查发布列表，而不是只返回正式版的 releases/latest。
    static var apiURL: URL {
        overrideURL ?? URL(string: "https://api.github.com/repos/\(repository)/releases?per_page=20")!
    }

    static var currentVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.0.0"
    }

    static var userAgent: String { "Pop/\(currentVersion) (macOS)" }

    /// 最新的可用版本；includePrereleases 为 false 时跳过测试版。一个发布都没有时返回 nil。
    static func latest(includePrereleases: Bool) async throws -> ReleaseInfo? {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        var request = URLRequest(url: apiURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw UpdateError.server(http.statusCode)
        }
        guard let releases = parseReleases(data) else { throw UpdateError.badResponse }
        return newest(releases, includePrereleases: includePrereleases)
    }

    /// 解析 GitHub releases 接口的 JSON：发布列表（数组）或单个发布（对象）都可以。草稿会被跳过。
    static func parseReleases(_ data: Data) -> [ReleaseInfo]? {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return nil }
        if let list = json as? [[String: Any]] {
            return list.compactMap(parseRelease)
        }
        if let single = json as? [String: Any] {
            return [parseRelease(single)].compactMap { $0 }
        }
        return nil
    }

    static func parseRelease(_ json: [String: Any]) -> ReleaseInfo? {
        guard let tag = json["tag_name"] as? String, !tag.isEmpty, (json["draft"] as? Bool) != true else { return nil }
        let version = tag.hasPrefix("v") || tag.hasPrefix("V") ? String(tag.dropFirst()) : tag
        let assets = (json["assets"] as? [[String: Any]]) ?? []
        func name(_ asset: [String: Any]) -> String { (asset["name"] as? String) ?? "" }
        // 压缩包：Pop 开头的 .zip，优先文件名里带版本号的那个
        let archives = assets.filter {
            let lower = name($0).lowercased()
            return lower.hasPrefix("pop") && lower.hasSuffix(".zip")
        }
        let archive = archives.first { name($0).contains(version) } ?? archives.first
        let checksums = assets.first { name($0) == checksumsName }
        let publishedAt = (json["published_at"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) }
        return ReleaseInfo(
            version: version,
            tag: tag,
            title: (json["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Pop \(version)",
            pageURL: (json["html_url"] as? String).flatMap(URL.init(string:)) ?? releasesPageURL,
            notes: (json["body"] as? String) ?? "",
            publishedAt: publishedAt,
            isPrerelease: (json["prerelease"] as? Bool) ?? false,
            archiveURL: archive.flatMap { ($0["browser_download_url"] as? String).flatMap(URL.init(string:)) },
            archiveName: archive.map(name),
            archiveSize: archive?["size"] as? Int,
            checksumsURL: checksums.flatMap { ($0["browser_download_url"] as? String).flatMap(URL.init(string:)) }
        )
    }

    static func newest(_ releases: [ReleaseInfo], includePrereleases: Bool) -> ReleaseInfo? {
        var best: ReleaseInfo?
        for release in releases where includePrereleases || !release.isPrerelease {
            if let current = best, !isNewer(release.version, than: current.version) { continue }
            best = release
        }
        return best
    }

    /// first 比 second 新时返回 true。数字逐段比较；带 -beta 之类后缀的比同号的正式版旧。
    static func isNewer(_ first: String, than second: String) -> Bool {
        let a = components(first)
        let b = components(second)
        for index in 0..<max(a.numbers.count, b.numbers.count) {
            let x = index < a.numbers.count ? a.numbers[index] : 0
            let y = index < b.numbers.count ? b.numbers[index] : 0
            if x != y { return x > y }
        }
        return !a.prerelease && b.prerelease
    }

    private static func components(_ version: String) -> (numbers: [Int], prerelease: Bool) {
        var text = version.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("v") || text.hasPrefix("V") {
            text.removeFirst()
        }
        let parts = text.split(separator: "-", maxSplits: 1)
        let numbers = (parts.first ?? "").split(separator: ".").map { Int($0) ?? 0 }
        return (numbers, parts.count > 1)
    }
}
