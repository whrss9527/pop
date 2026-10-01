import AppKit
@testable import Pop

/// 插件包「字幕工具」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopSubtitlesEntry)
final class SubtitlesEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [SubtitlesPlugin()]
    }

    @MainActor static func didLoad(_ host: PluginHost.Registrar) {
        // CI 截图：一份中文、一份英文的示例字幕，合成双语（不碰真的文件）
        host.addDemoScene(PluginHost.DemoScene(name: "subtitles", after: "pdfPages", order: 8, delay: 1.4, hold: 0, show: { demo in
            let model = SubtitlesModel(sources: SubtitlesPlugin.demoSources())
            model.shift = 1.5
            demo.overlay.showCard(SubtitlesView(model: model, onReveal: { _ in }, onClose: {}), anchor: demo.center)
            return demo.cardRegion
        }))
    }
}

struct SubtitlesPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.subtitles, name: String(localized: "字幕工具"), symbol: "captions.bubble",
                          summary: String(localized: "选中字幕文件（SRT、WebVTT、ASS、LRC），整体提前或推后、换帧率、去掉样式标签和听障说明，转成 SRT、WebVTT、LRC 或纯文字；选两份字幕可以合成一份双语字幕"),
                          accepts: [.files], check: .custom(CustomContentCheck("subtitleFiles") { subject in
                              subject.split(separator: "\n").contains { SubtitleTools.isSubtitle(URL(fileURLWithPath: String($0))) }
                          }))

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        let files = Array(content.files.filter(SubtitleTools.isSubtitle).prefix(2))
        guard !files.isEmpty else {
            return .failure(String(localized: "没有选中字幕文件"))
        }
        let sources = await runInBackground { files.compactMap(SubtitlesModel.load) }
        guard sources.count == files.count else {
            let unreadable = files.filter { file in !sources.contains { $0.url == file } }.map(\.lastPathComponent)
            return .failure(String(localized: "读不了「\(unreadable.joinedAsList())」：不是字幕，或者里面没有一句"))
        }
        return .present(PluginPresentation { session in
            let model = SubtitlesModel(sources: sources)
            session.showCard(SubtitlesView(model: model, onReveal: { urls in
                NSWorkspace.shared.activateFileViewerSelecting(urls)
                session.end()
            }, onClose: { session.end() }))
        })
    }

    /// 演示用：一段发布会的中文字幕和英文字幕
    static func demoSources() -> [SubtitlesModel.Source] {
        let folder = URL(fileURLWithPath: "/Users/Shared/发布会", isDirectory: true)
        let chinese = """
        1
        00:00:05,200 --> 00:00:08,600
        大家好，欢迎来到今天的发布会

        2
        00:00:08,900 --> 00:00:12,400
        <i>先看一下这一年我们做了什么</i>

        3
        00:00:12,800 --> 00:00:16,100
        长按右键，圆盘就出来了
        """
        let english = """
        WEBVTT

        00:00:05.300 --> 00:00:08.500
        Hello everyone, welcome to today's keynote.

        00:00:08.900 --> 00:00:12.300
        Let's look back at what we did this year.

        00:00:12.900 --> 00:00:16.000
        Press and hold the right button to bring up the ring.
        """
        return [(chinese, "发布会.zh.srt", SubtitleTools.Format.srt), (english, "发布会.en.vtt", .vtt)].map { text, name, format in
            SubtitlesModel.Source(url: folder.appending(path: name), format: format, encoding: "UTF-8",
                                  cues: SubtitleTools.parse(text, format: format), data: Data(text.utf8))
        }
    }
}
