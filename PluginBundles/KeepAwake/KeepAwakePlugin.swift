import AppKit
@testable import Pop

/// 插件包「保持唤醒」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopKeepAwakeEntry)
final class KeepAwakeEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [KeepAwakePlugin()]
    }

    @MainActor static func willUninstall() {
        KeepAwake.shared.stop()
    }
}

struct KeepAwakePlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.keepAwake, name: String(localized: "保持唤醒"), symbol: "cup.and.saucer",
                          summary: String(localized: "一段时间内不让屏幕变暗、电脑睡眠，适合看文档、演示、等下载"), accepts: [])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        let awake = KeepAwake.shared
        var buttons = KeepAwake.presets.map { CardButton(title: KeepAwake.title(minutes: $0), action: .keepAwake(minutes: $0)) }
        buttons.append(CardButton(title: String(localized: "一直保持"), action: .keepAwake(minutes: nil)))
        if awake.isActive {
            buttons.append(CardButton(title: String(localized: "停止"), action: .stopKeepAwake))
        }
        let body = awake.statusText() ?? String(localized: "选一个时长，这段时间里屏幕不会变暗，电脑也不会自己睡眠；合上盖子照常睡眠。")
        return .card(ResultCard(title: String(localized: "保持唤醒"), body: body,
                                detail: awake.isActive ? String(localized: "重新选一个时长会从现在开始算") : nil, buttons: buttons))
    }
}
