import AppKit
@testable import Pop

/// 插件包「计时器」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopTimerEntry)
final class TimerEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [TimerPlugin()]
    }

    @MainActor static func willUninstall() {
        CountdownTimer.shared.cancel()
    }
}

struct TimerPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.timer, name: String(localized: "计时器"), symbol: "timer",
                          summary: String(localized: "倒计时：选一个时长，或者选中「25 分钟」「1:30」这样的文字直接开始；到点时响一声、发通知。也有番茄钟：专注 25 分钟、休息 5 分钟，一直循环"),
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
        buttons.append(CardButton(title: String(localized: "番茄钟"), action: .startPomodoro))
        if countdown.isRunning {
            buttons.append(CardButton(title: countdown.pomodoro == nil ? String(localized: "取消计时") : String(localized: "结束番茄钟"), action: .cancelTimer))
        }
        let body = countdown.statusText() ?? String(localized: "选一个时长开始倒计时；到点时响一声、发一条通知。也可以选中「25 分钟」「1:30」这样的文字再用它。番茄钟是专注 25 分钟、休息 5 分钟轮流来（每四个番茄休息 15 分钟），一直到你结束。")
        return .card(ResultCard(title: String(localized: "计时器"), body: body, buttons: buttons))
    }
}
