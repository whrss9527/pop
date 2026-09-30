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

// MARK: - 系统操作

struct SystemActionsPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.systemActions, name: String(localized: "系统操作"), symbol: "switch.2",
                          summary: String(localized: "锁屏、熄屏、睡眠、打开屏幕保护程序、隐藏或显示桌面图标、推出所有磁盘"), accepts: [])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        .card(SystemActions.card(desktopIconsVisible: SystemActions.desktopIconsVisible(),
                                 ejectable: SystemActions.ejectableVolumes().count))
    }
}

// MARK: - 快捷键一览

struct MenuShortcutsPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.menuShortcuts, name: String(localized: "快捷键一览"), symbol: "command",
                          summary: String(localized: "列出当前 App 菜单里的所有快捷键，可以搜索，点一项直接执行"), accepts: [])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        .showMenuShortcuts
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

// MARK: - 录屏

struct ScreenRecordPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.screenRecord, name: String(localized: "录屏"), symbol: "record.circle",
                          summary: String(localized: "拖出一块区域、单击选一个窗口或者按回车录整个屏幕，存成 MP4；可以录上电脑里的声音或者麦克风、显示鼠标点击，录好能接着转成 GIF。正在录的时候再用一次就停止"),
                          accepts: [], hidesOverlay: true)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        let recorder = ScreenRecorder.shared
        if recorder.isRecording {
            recorder.stop()
            return .done(toast: nil)
        }
        guard CGPreflightScreenCaptureAccess() else {
            // 第一次会弹出系统的授权提示
            _ = CGRequestScreenCaptureAccess()
            return .failure(ScreenRecording.permissionHint)
        }
        guard let selection = await RegionPicker.pick() else { return .done(toast: nil) }
        do {
            try await recorder.start(selection)
            return .done(toast: nil)
        } catch {
            return .failure((error as? ScreenRecording.Failure)?.message ?? error.localizedDescription)
        }
    }
}

// MARK: - 滚动截图

struct ScrollCapturePlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.scrollCapture, name: String(localized: "滚动截图"), symbol: "scroll",
                          summary: String(localized: "框选一块区域，一边往下滚动一边截，拼成一张长图；网页、聊天记录、长文档都能截全，还能接着识别文字。正在截的时候再用一次就是完成"),
                          accepts: [], hidesOverlay: true)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        let capture = ScrollCapture.shared
        if capture.isCapturing {
            capture.finish()
            return .done(toast: nil)
        }
        guard CGPreflightScreenCaptureAccess() else {
            // 第一次会弹出系统的授权提示
            _ = CGRequestScreenCaptureAccess()
            return .failure(ScreenRecording.permissionHint)
        }
        guard let selection = await RegionPicker.pick(for: .scrollCapture) else { return .done(toast: nil) }
        do {
            try await capture.start(selection)
            return .done(toast: nil)
        } catch {
            return .failure((error as? ScrollCapture.Failure)?.message ?? error.localizedDescription)
        }
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
