import AppKit
@testable import Pop

/// 插件包「显示按键」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopShowKeystrokesEntry)
final class ShowKeystrokesEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [ShowKeystrokesPlugin()]
    }

    @MainActor static func willUninstall() {
        KeystrokeOverlay.shared.stop()
    }
}

struct ShowKeystrokesPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.showKeystrokes, name: String(localized: "显示按键"), symbol: "command.square",
                          summary: String(localized: "演示、录教程时在屏幕下方显示按下的组合键（⌘C、⇧⌘4、方向键这些），普通打字不显示；再用一次关闭。录屏时也可以勾选一起录进去"),
                          accepts: [])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        let overlay = KeystrokeOverlay.shared
        if overlay.isActive {
            overlay.stop()
            return .done(toast: String(localized: "不再显示按键"))
        }
        if let problem = overlay.start() {
            return .failure(problem)
        }
        return .done(toast: String(localized: "开始显示按下的组合键，再用一次就关闭"))
    }
}
