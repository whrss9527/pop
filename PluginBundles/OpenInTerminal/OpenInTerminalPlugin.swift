import AppKit
@testable import Pop

/// 插件包「在终端打开」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopOpenInTerminalEntry)
final class OpenInTerminalEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [OpenInTerminalPlugin()]
    }
}

struct OpenInTerminalPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.openInTerminal, name: String(localized: "在终端打开"), symbol: "apple.terminal",
                          summary: String(localized: "在「终端」里打开选中的文件夹（选中文件时打开它所在的文件夹）"), accepts: [.files])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let first = content.files.first else { return .failure(String(localized: "没有选中文件")) }
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: first.path(percentEncoded: false), isDirectory: &isDirectory)
        guard exists else { return .failure(String(localized: "文件不存在")) }
        let folder = isDirectory.boolValue ? first : first.deletingLastPathComponent()
        guard let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else {
            return .failure(String(localized: "找不到「终端」App"))
        }
        NSWorkspace.shared.open([folder], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
        return .done(toast: nil)
    }
}
