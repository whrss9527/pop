import AppKit
@testable import Pop

/// 插件包「代码行数」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopCodeStatsEntry)
final class CodeStatsEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [CodeStatsPlugin()]
    }
}

struct CodeStatsPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.codeStats, name: String(localized: "代码行数"), symbol: "chevron.left.forwardslash.chevron.right",
                          summary: String(localized: "按语言统计选中的文件夹里有多少个代码文件、多少行，可以复制成 Markdown 表格"),
                          accepts: [.files], check: .folder)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        let folders = content.files.filter { FolderTree.isFolder($0.path(percentEncoded: false)) }
        guard !folders.isEmpty else { return .failure(String(localized: "没有选中文件夹")) }
        let result = await runInBackground { CodeStats.scan(folders) }
        guard !result.languages.isEmpty else { return .failure(String(localized: "选中的文件夹里没有认得出的代码文件")) }
        var detail = String(localized: "\(result.files.formatted()) 个文件，\(result.lines.formatted()) 行（空行 \(result.blank.formatted()) 行）；不算隐藏文件夹和 node_modules 这类依赖")
        if result.skipped > 0 {
            detail += String(localized: "，跳过 \(result.skipped) 个太大或不是文字的文件")
        }
        if result.truncated {
            detail += String(localized: "，只数了前 \(CodeStats.fileLimit.formatted()) 个")
        }
        let rows = result.languages.map { language in
            ResultCard.Row(label: language.name, value: String(localized: "\(language.lines.formatted()) 行，\(language.files.formatted()) 个文件"))
        }
        return .card(ResultCard(title: String(localized: "代码行数"), detail: detail, copyText: CodeStats.markdown(result), rows: rows))
    }
}
