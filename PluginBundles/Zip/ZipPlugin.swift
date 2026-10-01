import AppKit
@testable import Pop

/// 插件包「压缩和解压」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopZipEntry)
final class ZipEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [ZipPlugin(), UnzipPlugin()]
    }
}

struct ZipPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.zip, name: String(localized: "压缩"), symbol: "doc.zipper",
                          summary: String(localized: "把选中的文件或文件夹压缩成 zip，存在原来的文件夹里"), accepts: [.files])
    /// 完成后在访达里选中结果（测试时换掉）
    var reveal: @MainActor ([URL]) -> Void = { NSWorkspace.shared.activateFileViewerSelecting($0) }

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        let files = content.files
        guard let first = files.first else { return .failure(String(localized: "没有选中文件")) }
        let folder = first.deletingLastPathComponent()
        guard files.allSatisfy({ $0.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL }) else {
            return .failure(String(localized: "选中的文件不在同一个文件夹里"))
        }
        let base = files.count == 1 ? first.deletingPathExtension().lastPathComponent : String(localized: "归档")
        let destination = FileNames.available(in: folder, base: base, extension: "zip")
        let result: Result<ProcessRunner.Output, PluginRunError>
        if files.count == 1 {
            // ditto 和访达的「压缩」一样：保留扩展属性，解压后还是原来的样子
            result = await ProcessRunner.run(URL(fileURLWithPath: "/usr/bin/ditto"),
                                             arguments: ["-c", "-k", "--sequesterRsrc", "--keepParent",
                                                         first.path(percentEncoded: false), destination.path(percentEncoded: false)],
                                             stdin: nil, environment: [:], timeout: 600)
        } else {
            // 多个文件：在它们所在的文件夹里用相对路径打包，压缩包里不带上层目录
            result = await ProcessRunner.run(URL(fileURLWithPath: "/bin/zsh"),
                                             arguments: ["-c", #"cd "$1" && dest="$2" && shift 2 && /usr/bin/zip -r -q -y "$dest" "$@""#, "zsh",
                                                         folder.path(percentEncoded: false), destination.path(percentEncoded: false)]
                                                 + files.map(\.lastPathComponent),
                                             stdin: nil, environment: [:], timeout: 600)
        }
        if let problem = Self.problem(in: result) {
            try? FileManager.default.removeItem(at: destination)
            return .failure(String(localized: "压缩失败：\(problem)"))
        }
        reveal([destination])
        return .done(toast: String(localized: "已压缩成 \(destination.lastPathComponent)"))
    }

    /// 子进程失败时的原因；成功返回 nil
    static func problem(in result: Result<ProcessRunner.Output, PluginRunError>) -> String? {
        switch result {
        case .failure(let error):
            return error.message
        case .success(let output):
            if output.timedOut {
                return String(localized: "超时了")
            }
            guard output.status == 0 else {
                let message = output.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                return message.isEmpty ? String(localized: "退出码 \(Int(output.status))") : String(message.prefix(300))
            }
            return nil
        }
    }
}

struct UnzipPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.unzip, name: String(localized: "解压"), symbol: "archivebox",
                          summary: String(localized: "把选中的 zip 解压到旁边的同名文件夹里"), accepts: [.files], pattern: #"(?i)\.zip$"#)
    /// 完成后在访达里选中结果（测试时换掉）
    var reveal: @MainActor ([URL]) -> Void = { NSWorkspace.shared.activateFileViewerSelecting($0) }

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        let archives = content.files.filter { $0.pathExtension.lowercased() == "zip" }
        guard !archives.isEmpty else { return .failure(String(localized: "没有选中 zip 文件")) }
        var folders: [URL] = []
        for archive in archives {
            let destination = FileNames.available(in: archive.deletingLastPathComponent(),
                                                  base: archive.deletingPathExtension().lastPathComponent)
            let result = await ProcessRunner.run(URL(fileURLWithPath: "/usr/bin/ditto"),
                                                 arguments: ["-x", "-k", archive.path(percentEncoded: false),
                                                             destination.path(percentEncoded: false)],
                                                 stdin: nil, environment: [:], timeout: 600)
            if let problem = ZipPlugin.problem(in: result) {
                return .failure(String(localized: "解压「\(archive.lastPathComponent)」失败：\(problem)"))
            }
            folders.append(destination)
        }
        reveal(folders)
        return .done(toast: folders.count == 1 ? String(localized: "已解压到「\(folders[0].lastPathComponent)」") : String(localized: "已解压 \(folders.count) 个文件"))
    }
}
