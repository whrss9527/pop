import AppKit
@testable import Pop

/// 插件包「录音」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopVoiceRecorderEntry)
final class VoiceRecorderEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [VoiceRecorderPlugin()]
    }

    @MainActor static func didLoad(_ host: PluginHost.Registrar) {
        // 录屏时不录屏幕上方的录音小条
        host.excludeFromRecording {
            [VoiceRecorder.shared.windowNumber].compactMap { $0 }
        }
        // CI 截图：录了 42 秒的小条（不开麦克风）
        host.addDemoScene(PluginHost.DemoScene(name: "voiceRecorder", after: "pdfPages", order: 12, delay: 1.4, hold: 0, show: { demo in
            let frame = VoiceRecorder.shared.showForDemo(on: demo.screen)
            // 小条很小，左右多截一些
            return frame.insetBy(dx: -40, dy: -8)
        }, hide: {
            VoiceRecorder.shared.close()
        }))
    }

    @MainActor static func willUninstall() {
        VoiceRecorder.shared.close()
    }
}

struct VoiceRecorderPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.voiceRecorder, name: String(localized: "录音"), symbol: "mic",
                          summary: String(localized: "用麦克风录一段声音，存成 .m4a 放进「下载」；录的时候屏幕上方有个小条，看得到时长和音量，可以暂停，录好能接着转成文字。正在录的时候再用一次就停止"),
                          accepts: [], hidesOverlay: true)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        let recorder = VoiceRecorder.shared
        if recorder.isRecording {
            recorder.stop()
            return .done(toast: nil)
        }
        // 装了「语音转文字」、这台 Mac 能识别时，存好后可以接着转成文字
        let canTranscribe = context.settings.isInstalled(BuiltinPluginID.transcribe) && !Transcriber.languages().isEmpty
        if let problem = await recorder.start(near: context.anchor ?? NSEvent.mouseLocation, canTranscribe: canTranscribe) {
            return .failure(problem)
        }
        return .done(toast: nil)
    }
}
