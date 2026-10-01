import AppKit
@testable import Pop

/// 插件包「录屏」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopScreenRecordEntry)
final class ScreenRecordEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [ScreenRecordPlugin()]
    }

    @MainActor static func willUninstall() {
        if ScreenRecorder.shared.isRecording {
            ScreenRecorder.shared.stop()
        }
    }
}

struct ScreenRecordPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.screenRecord, name: String(localized: "录屏"), symbol: "record.circle",
                          summary: String(localized: "拖出一块区域、单击选一个窗口或者按回车录整个屏幕，存成 MP4；可以录上电脑里的声音或者麦克风、显示鼠标点击和按下的键，录好能接着转成 GIF。正在录的时候再用一次就停止"),
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
        // 倒数时按了 Esc：不录了
        if selection.options.countdown, !(await RecordingCountdown.run(in: selection.rect)) {
            return .done(toast: nil)
        }
        do {
            try await recorder.start(selection)
            return .done(toast: nil)
        } catch {
            return .failure((error as? ScreenRecording.Failure)?.message ?? error.localizedDescription)
        }
    }
}
