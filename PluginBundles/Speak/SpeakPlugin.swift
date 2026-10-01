import AppKit
@testable import Pop

/// 插件包「朗读」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopSpeakEntry)
final class SpeakEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [SpeakPlugin(), SpeakToFilePlugin()]
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

struct SpeakToFilePlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.speakToFile, name: String(localized: "朗读存成音频"), symbol: "waveform",
                          summary: String(localized: "用系统语音把选中的文字读出来，存成音频文件（.m4a）放进「下载」，配音、听力材料都能用"),
                          accepts: [.text])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure(String(localized: "没有可朗读的文字"))
        }
        let language = content.language ?? ContentClassifier.dominantLanguage(text)
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: "Downloads", directoryHint: .isDirectory)
        let url = FileNames.available(in: downloads, base: SpeechExporter.fileName(for: text), extension: "m4a")
        return .present(PluginPresentation { session in
            // 长的文字要存一会儿，先说一声；存好时再提示一次
            session.finish(toast: String(localized: "正在存成音频…"))
            Task { @MainActor in
                do {
                    let output = try await SpeechExporter().export(text, voice: SpeechExporter.voice(for: language), to: url)
                    NSWorkspace.shared.activateFileViewerSelecting([output.url])
                    session.finish(toast: String(localized: "存好了「\(output.url.lastPathComponent)」，长 \(SpeechExporter.describe(output.duration))"))
                } catch let failure as SpeechExporter.Failure {
                    session.finish(toast: failure.message)
                } catch {
                    session.finish(toast: error.localizedDescription)
                }
            }
        })
    }
}
