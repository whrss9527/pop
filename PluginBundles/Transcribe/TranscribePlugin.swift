import AppKit
@testable import Pop

/// 插件包「语音转文字」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopTranscribeEntry)
final class TranscribeEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [TranscribePlugin()]
    }
}

struct TranscribePlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.transcribe, name: String(localized: "语音转文字"), symbol: "captions.bubble",
                          summary: String(localized: "把录音、视频里说的话转成文字和 SRT 字幕，存在原文件旁边；普通话、英语、粤语、日语，这台 Mac 支持时在本机识别"),
                          accepts: [.files], pattern: Transcriber.pattern)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let file = content.files.first(where: Transcriber.isMedia) else { return .failure(String(localized: "没有选中录音或视频")) }
        let languages = Transcriber.languages()
        guard !languages.isEmpty else { return .failure(String(localized: "这台 Mac 上用不了语音识别")) }
        var rows = [ResultCard.Row(label: String(localized: "文件"), value: file.lastPathComponent)]
        if let duration = await Transcriber.duration(of: file) {
            rows.append(ResultCard.Row(label: String(localized: "时长"), value: CountdownTimer.clock(Int(duration.rounded()))))
        }
        return .card(ResultCard(title: String(localized: "语音转文字"), body: String(localized: "说的是哪种话？"),
                                detail: String(localized: "识别完，文字（.txt）和字幕（.srt）存在原文件旁边；长录音要等一会儿"),
                                rows: rows,
                                buttons: languages.map { CardButton(title: $0.title, action: .transcribe(file, language: $0.identifier)) }))
    }
}
