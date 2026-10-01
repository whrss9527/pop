import AppKit
@testable import Pop

/// 插件包「朗读」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopSpeakEntry)
final class SpeakEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [SpeakPlugin()]
    }

    @MainActor static func willUninstall() {
        Speaker.shared.stop()
    }
}

struct SpeakPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.speak, name: String(localized: "朗读"), symbol: "speaker.wave.2",
                          summary: String(localized: "用系统语音朗读选中的文字，朗读中再用一次就停止"), accepts: [.text])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        if Speaker.shared.isSpeaking {
            Speaker.shared.stop()
            return .done(toast: String(localized: "已停止朗读"))
        }
        guard let text = content.text else { return .failure(String(localized: "没有可朗读的文字")) }
        let language = content.language ?? ContentClassifier.dominantLanguage(text)
        Speaker.shared.speak(text, language: language)
        return .done(toast: String(localized: "正在朗读…"))
    }
}
