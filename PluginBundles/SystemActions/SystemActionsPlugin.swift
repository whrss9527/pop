import AppKit
@testable import Pop

/// 插件包「系统操作」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopSystemActionsEntry)
final class SystemActionsEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [SystemActionsPlugin()]
    }
}

struct SystemActionsPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.systemActions, name: String(localized: "系统操作"), symbol: "switch.2",
                          summary: String(localized: "锁屏、熄屏、睡眠、打开屏幕保护程序、切换深色和浅色模式、静音、隐藏或显示桌面图标、显示隐藏文件、推出所有磁盘"), accepts: [])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        .card(SystemActions.card(desktopIconsVisible: SystemActions.desktopIconsVisible(), darkMode: SystemActions.isDarkMode(),
                                 ejectable: SystemActions.ejectableVolumes().count, muted: SystemActions.isMuted() ?? false,
                                 hiddenFilesShown: SystemActions.hiddenFilesShown()))
    }
}
