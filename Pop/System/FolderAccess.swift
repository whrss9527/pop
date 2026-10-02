import AppKit

/// App Store 版开了沙盒，只能读写用户自己选过的位置。在访达里选中文件再唤起 Pop 时，Pop 从剪贴板拿到的只是路径，
/// 没有权限读，图片识别文字、压缩这些都用不了。所以请用户选一次文件夹（一般就选个人文件夹），存成 security-scoped
/// bookmark，每次启动时打开，这个文件夹里的文件之后都能读写。GitHub 版没开沙盒，用不着这些。
@MainActor
final class FolderAccess: ObservableObject {
    static let shared = FolderAccess()

    private static let bookmarksKey = "pop.folderAccess.bookmarks"

    /// 允许 Pop 读写的文件夹，和保存的 bookmark 一一对应
    @Published private(set) var folders: [URL] = []
    private var bookmarks: [Data] = []
    private var didStart = false

    /// 启动时打开保存过的文件夹，之后一直开着
    func start() {
        guard Distribution.isAppStore, !didStart else { return }
        didStart = true
        for data in UserDefaults.standard.array(forKey: Self.bookmarksKey) as? [Data] ?? [] {
            var stale = false
            guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil,
                                     bookmarkDataIsStale: &stale),
                  url.startAccessingSecurityScopedResource() else { continue }
            folders.append(url)
            // 文件夹改过名、搬过家时 bookmark 会过期，换成新的
            bookmarks.append(stale ? (Self.bookmark(for: url) ?? data) : data)
        }
        save()
    }

    /// 请用户选一个允许 Pop 读写的文件夹（默认指向个人文件夹），选好后马上生效
    func requestAccess() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "允许访问")
        panel.message = String(localized: "选一个文件夹，Pop 就能读写里面的文件，比如在访达里选中图片后识别文字、转换格式。一般选个人文件夹就行。")
        panel.directoryURL = Self.homeFolder
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url,
              !folders.contains(url),
              let data = Self.bookmark(for: url),
              url.startAccessingSecurityScopedResource() else { return }
        folders.append(url)
        bookmarks.append(data)
        save()
    }

    /// 不再允许访问这个文件夹
    func remove(_ url: URL) {
        guard let index = folders.firstIndex(of: url) else { return }
        url.stopAccessingSecurityScopedResource()
        folders.remove(at: index)
        bookmarks.remove(at: index)
        save()
    }

    /// 这些文件里 Pop 读不了的（只有 App Store 版会有）
    nonisolated static func unreadable(_ urls: [URL]) -> [URL] {
        guard Distribution.isAppStore else { return [] }
        return urls.filter { !canRead($0) }
    }

    /// 真去打开一下：沙盒拦不拦只有打开时才知道
    nonisolated static func canRead(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let path = url.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else { return true }
        if isDirectory.boolValue {
            return (try? FileManager.default.contentsOfDirectory(atPath: path)) != nil
        }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        try? handle.close()
        return true
    }

    /// 真正的个人文件夹：沙盒里 homeDirectoryForCurrentUser 是 App 自己的容器
    nonisolated static var homeFolder: URL {
        if let home = getpwuid(getuid())?.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: home), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    private static func bookmark(for url: URL) -> Data? {
        try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    private func save() {
        UserDefaults.standard.set(bookmarks, forKey: Self.bookmarksKey)
    }
}
