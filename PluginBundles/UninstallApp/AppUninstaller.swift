import Foundation
import Security
@testable import Pop

/// 卸载 App：除了 App 本身，再找出它在「资源库」里留下的文件（设置、缓存、容器……），一起移到废纸篓。
///
/// 怎么找：先读出 App 和它里面带的扩展、辅助程序的 bundle ID，签名里的开发者团队和 App 组，
/// 再到「资源库」下面几个固定的地方按这些 ID 和 App 的名字对。
/// 按 ID 正好对上的默认勾选；只是开头对上的（可能是同一个开发者别的 App）、App 组的共享容器（可能和别的 App 共用）默认不勾。
enum AppUninstaller {
    struct Failure: Error, Equatable {
        let message: String
    }

    struct App: Equatable {
        let url: URL
        let name: String
        let bundleID: String?
        let version: String?
        let executable: String?
        /// App 和它里面带的扩展、辅助程序的 bundle ID
        let relatedIDs: Set<String>
        /// 签名里的 App 组（共享容器的名字）
        let groups: [String]
        let teamID: String?

        /// 系统自带的（苹果的）App
        var isApple: Bool {
            bundleID?.hasPrefix("com.apple.") == true || url.path(percentEncoded: false).hasPrefix("/System/")
        }
    }

    /// 在「资源库」里的哪一类地方
    enum Place: String, CaseIterable {
        case app
        case support
        case caches
        case preferences
        case containers
        case groupContainers
        case savedState
        case webData
        case logs
        case launchAgents
        case scripts

        var title: String {
            switch self {
            case .app: return String(localized: "App 本身")
            case .support: return String(localized: "应用程序支持")
            case .caches: return String(localized: "缓存")
            case .preferences: return String(localized: "偏好设置")
            case .containers: return String(localized: "容器")
            case .groupContainers: return String(localized: "共享容器")
            case .savedState: return String(localized: "窗口状态")
            case .webData: return String(localized: "网页数据")
            case .logs: return String(localized: "日志")
            case .launchAgents: return String(localized: "开机启动的服务")
            case .scripts: return String(localized: "脚本")
            }
        }

        var symbol: String {
            switch self {
            case .app: return "app"
            case .support: return "folder"
            case .caches: return "archivebox"
            case .preferences: return "gearshape"
            case .containers: return "shippingbox"
            case .groupContainers: return "person.2"
            case .savedState: return "macwindow"
            case .webData: return "globe"
            case .logs: return "doc.text"
            case .launchAgents: return "power"
            case .scripts: return "applescript"
            }
        }
    }

    /// 为什么没有默认勾上
    enum Doubt: Equatable {
        /// 只是名字的开头对上了，可能是同一个开发者的别的 App
        case prefix
        /// App 组的共享容器，可能和同一个开发者的别的 App 共用
        case shared

        var note: String {
            switch self {
            case .prefix: return String(localized: "名字只是开头对上了，可能是同一个开发者的别的 App")
            case .shared: return String(localized: "可能和同一个开发者的别的 App 共用")
            }
        }
    }

    struct Item: Identifiable, Equatable {
        let url: URL
        let place: Place
        /// 有疑问的默认不勾
        var doubt: Doubt?

        var id: URL { url }
    }

    // MARK: - 读 App

    static func app(at url: URL) throws -> App {
        guard url.pathExtension.lowercased() == "app", let bundle = Bundle(url: url) else {
            throw Failure(message: String(localized: "「\(url.lastPathComponent)」不是 App"))
        }
        let info = bundle.infoDictionary ?? [:]
        let bundleID = info["CFBundleIdentifier"] as? String
        let name = (info["CFBundleDisplayName"] as? String) ?? (info["CFBundleName"] as? String) ?? url.deletingPathExtension().lastPathComponent
        let signed = signing(of: url)
        return App(url: url, name: name, bundleID: bundleID, version: info["CFBundleShortVersionString"] as? String,
                   executable: info["CFBundleExecutable"] as? String,
                   relatedIDs: Set([bundleID].compactMap { $0 } + embeddedIDs(in: url)),
                   groups: signed.groups, teamID: signed.team)
    }

    /// App 里面带的扩展、登录项、辅助程序的 bundle ID（它们的设置、容器也算这个 App 的）
    static func embeddedIDs(in app: URL) -> [String] {
        let contents = app.appending(path: "Contents", directoryHint: .isDirectory)
        let places = ["PlugIns", "Library/LoginItems", "Library/LaunchServices", "Helpers", "XPCServices", "Frameworks"]
        var ids: [String] = []
        for place in places {
            let folder = contents.appending(path: place, directoryHint: .isDirectory)
            guard let items = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { continue }
            for item in items where ["app", "appex", "xpc"].contains(item.pathExtension.lowercased()) {
                if let id = Bundle(url: item)?.bundleIdentifier {
                    ids.append(id)
                }
            }
        }
        return ids
    }

    /// 签名里的开发者团队和 App 组；没签名或者读不出来时为空
    static func signing(of app: URL) -> (team: String?, groups: [String]) {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code else { return (nil, []) }
        var information: CFDictionary?
        let flags = SecCSFlags(rawValue: UInt32(kSecCSSigningInformation) | UInt32(kSecCSRequirementInformation))
        guard SecCodeCopySigningInformation(code, flags, &information) == errSecSuccess,
              let dictionary = information as? [String: Any] else { return (nil, []) }
        let entitlements = dictionary[kSecCodeInfoEntitlementsDict as String] as? [String: Any]
        return (dictionary[kSecCodeInfoTeamIdentifier as String] as? String,
                entitlements?["com.apple.security.application-groups"] as? [String] ?? [])
    }

    // MARK: - 找留下的文件

    /// App 本身排第一，后面按地方排；library 是「资源库」（测试时换成临时文件夹）
    static func scan(_ app: App, library: URL = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library", directoryHint: .isDirectory)) -> [Item] {
        var items = [Item(url: app.url, place: .app)]
        var seen: Set<String> = [app.url.standardizedFileURL.path(percentEncoded: false)]
        func add(_ url: URL, _ place: Place, _ doubt: Doubt?) {
            guard seen.insert(url.standardizedFileURL.path(percentEncoded: false)).inserted else { return }
            items.append(Item(url: url, place: place, doubt: doubt))
        }
        let ids = app.relatedIDs
        let names = Set([app.name, app.url.deletingPathExtension().lastPathComponent, app.executable].compactMap { $0 }
            .filter { $0.count >= 3 }.map { $0.lowercased() })
        // 文件名（去掉 .plist 这类后缀以后）和某个 ID 正好一样：勾上；以「ID.」开头：有疑问
        func matchID(_ name: String, suffixes: [String] = []) -> (matched: Bool, doubt: Doubt?) {
            var base = name
            for suffix in suffixes where base.hasSuffix(suffix) {
                base = String(base.dropLast(suffix.count))
                break
            }
            if ids.contains(base) { return (true, nil) }
            if ids.contains(where: { base.hasPrefix($0 + ".") }) { return (true, .prefix) }
            return (false, nil)
        }
        func look(_ path: String, _ place: Place, suffixes: [String] = [], byName: Bool = false) {
            let folder = library.appending(path: path, directoryHint: .isDirectory)
            guard let entries = try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false)) else { return }
            for entry in entries.sorted() where !entry.hasPrefix(".") {
                let match = matchID(entry, suffixes: suffixes)
                if match.matched {
                    add(folder.appending(path: entry), place, match.doubt)
                } else if byName, names.contains(entry.lowercased()) {
                    add(folder.appending(path: entry), place, nil)
                }
            }
        }
        look("Application Support", .support, byName: true)
        look("Caches", .caches, byName: true)
        look("HTTPStorages", .caches, suffixes: [".binarycookies"])
        look("Preferences", .preferences, suffixes: [".plist"])
        // ByHost 里的是「ID.硬件 UUID.plist」
        let byHost = library.appending(path: "Preferences/ByHost", directoryHint: .isDirectory)
        if let entries = try? FileManager.default.contentsOfDirectory(atPath: byHost.path(percentEncoded: false)) {
            for entry in entries.sorted() where entry.hasSuffix(".plist") {
                let parts = entry.dropLast(".plist".count).split(separator: ".")
                guard parts.count > 1 else { continue }
                if ids.contains(parts.dropLast().joined(separator: ".")) {
                    add(byHost.appending(path: entry), .preferences, nil)
                }
            }
        }
        look("Containers", .containers)
        // 共享容器：签名里写着的 App 组，还有名字里带着 bundle ID 的；都可能和别的 App 共用
        let groupFolder = library.appending(path: "Group Containers", directoryHint: .isDirectory)
        if let entries = try? FileManager.default.contentsOfDirectory(atPath: groupFolder.path(percentEncoded: false)) {
            for entry in entries.sorted() where app.groups.contains(entry) || ids.contains(where: { entry.hasSuffix("." + $0) }) {
                add(groupFolder.appending(path: entry), .groupContainers, .shared)
            }
        }
        look("Saved Application State", .savedState, suffixes: [".savedState"])
        look("WebKit", .webData)
        look("Cookies", .webData, suffixes: [".binarycookies"])
        look("Logs", .logs, byName: true)
        look("LaunchAgents", .launchAgents, suffixes: [".plist"])
        look("Application Scripts", .scripts)
        return items
    }

    // MARK: - 大小

    /// 文件或者文件夹占的空间（字节）；读不了时为 nil
    static func size(of url: URL) -> UInt64? {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
        func bytes(_ values: URLResourceValues) -> UInt64 {
            UInt64(max(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0, 0))
        }
        guard values.isDirectory == true else { return bytes(values) }
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys)) else { return nil }
        var total: UInt64 = 0
        for case let file as URL in enumerator {
            guard let values = try? file.resourceValues(forKeys: keys), values.isRegularFile == true else { continue }
            total += bytes(values)
        }
        return total
    }

    static func format(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .file)
    }

    /// 「~/Library/Caches/com.example.app」这样短一点的路径
    static func displayPath(_ url: URL) -> String {
        let path = url.path(percentEncoded: false)
        let home = FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)
        let trimmed = path.hasSuffix("/") ? String(path.dropLast()) : path
        guard trimmed.hasPrefix(home) else { return trimmed }
        let rest = String(trimmed.dropFirst(home.count))
        return rest.hasPrefix("/") ? "~" + rest : "~/" + rest
    }
}
