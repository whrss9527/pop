import AppKit
@testable import Pop

/// 插件包「对比文件」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopFileCompareEntry)
final class FileCompareEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [FileComparePlugin()]
    }
}

struct FileComparePlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.compareFiles, name: String(localized: "对比文件"), symbol: "doc.on.doc",
                          summary: String(localized: "对比选中的两个文本文件（代码、Markdown、配置、CSV……），标出删去和新增的行，改动的地方逐词标出；按修改时间，旧的当原文"),
                          accepts: [.files], check: .custom(CustomContentCheck("twoTextFiles") { subject in
                              // 圆盘按选中文件的路径（一行一个）检查
                              let paths = subject.components(separatedBy: "\n").filter { !$0.isEmpty }
                              return paths.count == 2 && paths.allSatisfy { FileDiff.isTextFile(URL(fileURLWithPath: $0)) }
                          }))

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard content.files.count == 2, content.files.allSatisfy(FileDiff.isTextFile) else {
            return .failure(String(localized: "选中两个文本文件才能对比"))
        }
        let (older, newer) = FileDiff.ordered(content.files[0], content.files[1])
        let result: Result<TextDiff.Result, FileDiff.Failure> = await runInBackground {
            do {
                let oldText = try FileDiff.read(older)
                let newText = try FileDiff.read(newer)
                return .success(TextDiff.compare(oldText, newText))
            } catch let failure as FileDiff.Failure {
                return .failure(failure)
            } catch {
                return .failure(FileDiff.Failure(message: error.localizedDescription))
            }
        }
        switch result {
        case .failure(let failure):
            return .failure(failure.message)
        case .success(let diff):
            if diff.isIdentical {
                return .done(toast: String(localized: "两个文件内容相同"))
            }
            return .card(FileDiff.card(old: older, new: newer, result: diff))
        }
    }
}
