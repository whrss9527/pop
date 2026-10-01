import AppKit
@testable import Pop

/// 插件包「隔空投送」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopAirDropEntry)
final class AirDropEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [AirDropPlugin()]
    }
}

struct AirDropPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.airDrop, name: String(localized: "隔空投送"), symbol: "dot.radiowaves.left.and.right",
                          summary: String(localized: "用隔空投送把选中的文件、图片、链接或文字发到附近的 iPhone、iPad 或 Mac"),
                          accepts: [.text, .files, .image])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        let items: [Any]
        if !content.files.isEmpty {
            items = content.files
        } else if case .image(let data) = content.selection, let image = NSImage(data: data) {
            items = [image]
        } else if let url = content.url {
            items = [url]
        } else if let text = content.text {
            items = [text]
        } else {
            return .failure(String(localized: "没有可以发送的内容"))
        }
        guard let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: items) else {
            return .failure(String(localized: "现在用不了隔空投送。请确认无线局域网和蓝牙都已打开，「隔空投送」没有被关闭。"))
        }
        // 隔空投送的窗口要显示在最前面
        NSApp.activate()
        service.perform(withItems: items)
        return .done(toast: nil)
    }
}
