import AppKit
@testable import Pop

/// 插件包「哈希」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopHashEntry)
final class HashEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [HashPlugin()]
    }
}

struct HashPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.hash, name: String(localized: "哈希"), symbol: "number.square",
                          summary: String(localized: "计算文字或文件的 MD5、SHA-1、SHA-256、SHA-512"), accepts: [.text, .files])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        let files = content.files.filter { !$0.hasDirectoryPath && !Self.isDirectory($0) }
        if !content.files.isEmpty {
            guard !files.isEmpty else { return .failure(String(localized: "文件夹没法计算哈希，请选择文件")) }
            let result: Result<[ResultCard.Row], PluginRunError> = await runInBackground {
                do {
                    if files.count == 1 {
                        return .success(try Digests.rows(forFile: files[0]))
                    }
                    return .success(try files.prefix(20).map { url in
                        ResultCard.Row(label: url.lastPathComponent, value: try Digests.sha256(ofFile: url))
                    })
                } catch {
                    return .failure(PluginRunError(String(localized: "读取文件失败：\(error.localizedDescription)")))
                }
            }
            switch result {
            case .success(let rows):
                let title = files.count == 1 ? files[0].lastPathComponent : String(localized: "SHA-256（\(min(files.count, 20)) 个文件）")
                return .card(ResultCard(title: title, rows: rows))
            case .failure(let error):
                return .failure(error.message)
            }
        }
        guard let text = content.text else { return .failure(String(localized: "没有内容")) }
        let rows = await runInBackground { Digests.rows(for: Data(text.utf8)) }
        return .card(ResultCard(title: String(localized: "哈希（UTF-8）"), rows: rows))
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
