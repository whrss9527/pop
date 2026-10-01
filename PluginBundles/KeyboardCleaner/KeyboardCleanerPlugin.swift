import AppKit
@testable import Pop

/// 插件包「清洁键盘」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopKeyboardCleanerEntry)
final class KeyboardCleanerEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [KeyboardCleanerPlugin()]
    }

    @MainActor static func willUninstall() {
        KeyboardCleaner.shared.stop()
    }
}

struct KeyboardCleanerPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.cleanKeyboard, name: String(localized: "清洁键盘"), symbol: "keyboard",
                          summary: String(localized: "锁住键盘一分钟，擦键盘时不会误触；亮度、音量键也不起作用，用鼠标点「结束清洁」随时恢复"),
                          accepts: [], hidesOverlay: true)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        let cleaner = KeyboardCleaner.shared
        if cleaner.isActive {
            cleaner.stop()
            return .done(toast: nil)
        }
        if let problem = cleaner.start() {
            return .failure(problem)
        }
        return .done(toast: nil)
    }
}
