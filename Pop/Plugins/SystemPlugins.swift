import AppKit

// MARK: - 保持唤醒

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

// MARK: - 屏幕标尺

struct RulerPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.ruler, name: String(localized: "屏幕标尺"), symbol: "ruler",
                          summary: String(localized: "定格屏幕，量出指针处到上下左右边缘的距离，拖动量一块区域的宽高；单击复制尺寸"),
                          accepts: [], hidesOverlay: true)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        if let problem = await ScreenRuler.start() {
            return .failure(problem)
        }
        return .done(toast: nil)
    }
}

// MARK: - 计时器

struct TimerPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.timer, name: String(localized: "计时器"), symbol: "timer",
                          summary: String(localized: "倒计时：选一个时长，或者选中「25 分钟」「1:30」这样的文字直接开始；到点时响一声、发通知"),
                          accepts: [], optionalContent: true)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        let countdown = CountdownTimer.shared
        // 选中的文字就是一个时长：直接开始
        if let text = content.text, let seconds = DurationParser.parse(text), seconds <= 24 * 3600 {
            countdown.start(seconds: seconds)
            return .done(toast: String(localized: "开始计时 \(CountdownTimer.title(seconds: seconds))"))
        }
        var buttons = CountdownTimer.presets.map { minutes -> CardButton in
            let seconds = TimeInterval(minutes * 60)
            return CardButton(title: CountdownTimer.title(seconds: seconds), action: .startTimer(seconds: seconds))
        }
        if countdown.isRunning {
            buttons.append(CardButton(title: String(localized: "取消计时"), action: .cancelTimer))
        }
        let body = countdown.statusText() ?? String(localized: "选一个时长开始倒计时；到点时响一声、发一条通知。也可以选中「25 分钟」「1:30」这样的文字再用它。")
        return .card(ResultCard(title: String(localized: "计时器"), body: body, buttons: buttons))
    }
}
