import AppKit

// MARK: - 保持唤醒

struct KeepAwakePlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.keepAwake, name: "保持唤醒", symbol: "cup.and.saucer",
                          summary: "一段时间内不让屏幕变暗、电脑睡眠，适合看文档、演示、等下载", accepts: [])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        let awake = KeepAwake.shared
        var buttons = KeepAwake.presets.map { CardButton(title: KeepAwake.title(minutes: $0), action: .keepAwake(minutes: $0)) }
        buttons.append(CardButton(title: "一直保持", action: .keepAwake(minutes: nil)))
        if awake.isActive {
            buttons.append(CardButton(title: "停止", action: .stopKeepAwake))
        }
        let body = awake.statusText() ?? "选一个时长，这段时间里屏幕不会变暗，电脑也不会自己睡眠；合上盖子照常睡眠。"
        return .card(ResultCard(title: "保持唤醒", body: body,
                                detail: awake.isActive ? "重新选一个时长会从现在开始算" : nil, buttons: buttons))
    }
}

// MARK: - 屏幕标尺

struct RulerPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.ruler, name: "屏幕标尺", symbol: "ruler",
                          summary: "定格屏幕，量出指针处到上下左右边缘的距离，拖动量一块区域的宽高；单击复制尺寸",
                          accepts: [], hidesOverlay: true)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        if let problem = await ScreenRuler.start() {
            return .failure(problem)
        }
        return .done(toast: nil)
    }
}
