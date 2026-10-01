import AppKit
@testable import Pop

/// 插件包「收集箱」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopQuickNoteEntry)
final class QuickNoteEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [QuickNotePlugin()]
    }
}

struct QuickNotePlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.quickNote, name: String(localized: "收集箱"), symbol: "tray.and.arrow.down",
                          summary: String(localized: "把选中的文字追加到「文稿/Pop 收集箱.md」"), accepts: [.text])

    static var fileURL: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: "Documents", directoryHint: .isDirectory)
        return documents.appending(path: "Pop 收集箱.md")
    }

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text else { return .failure(String(localized: "没有文字")) }
        do {
            try Self.append(text, source: context.sourceAppName, to: Self.fileURL)
            return .done(toast: String(localized: "已记到收集箱"))
        } catch {
            return .failure(String(localized: "写入收集箱失败：\(error.localizedDescription)"))
        }
    }

    static func entry(_ text: String, source: String?, date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let heading = "## " + formatter.string(from: date) + (source.map { " · \($0)" } ?? "")
        return "\n" + heading + "\n\n" + text + "\n"
    }

    static func append(_ text: String, source: String?, to url: URL, date: Date = Date()) throws {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: url.path(percentEncoded: false)) {
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("# Pop 收集箱\n".utf8).write(to: url)
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        _ = try handle.seekToEnd()
        try handle.write(contentsOf: Data(entry(text, source: source, date: date).utf8))
    }
}
