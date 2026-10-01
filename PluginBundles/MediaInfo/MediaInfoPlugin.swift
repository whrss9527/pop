import AppKit
@testable import Pop

/// 插件包「媒体信息」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopMediaInfoEntry)
final class MediaInfoEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [MediaInfoPlugin()]
    }

    @MainActor static func didLoad(_ host: PluginHost.Registrar) {
        // CI 截图：一段示例视频的信息（不读真的文件）
        host.addDemoScene(PluginHost.DemoScene(name: "mediaInfo", after: "pdfPages", order: 7, delay: 1.4, hold: 0, show: { demo in
            let model = MediaInfoModel(report: MediaInfoPlugin.demoReport(), strip: { $0 })
            demo.overlay.showCard(MediaInfoView(model: model, onReveal: { _ in }, onCopy: {}, onOpenMap: { _ in }, onClose: {}),
                                  anchor: demo.center)
            return demo.cardRegion
        }))
    }
}

struct MediaInfoPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.mediaInfo, name: String(localized: "媒体信息"), symbol: "film.stack",
                          summary: String(localized: "看选中的视频或音频用的什么编码、分辨率、帧率、码率，是不是 HDR，有几条音轨和字幕，用什么设备在哪拍的；带着拍摄地点时可以去掉位置另存一份"),
                          accepts: [.files], check: .custom(CustomContentCheck("mediaInfoFiles") { subject in
                              subject.split(separator: "\n").contains { MediaInspector.isMedia(URL(fileURLWithPath: String($0))) }
                          }))

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let url = content.files.first(where: MediaInspector.isMedia) else {
            return .failure(String(localized: "没有选中视频或音频"))
        }
        let report: MediaInspector.Report
        do {
            report = try await MediaInspector.inspect(url)
        } catch let failure as MediaInspector.Failure {
            return .failure(failure.message)
        } catch {
            return .failure(error.localizedDescription)
        }
        return .present(PluginPresentation { session in
            let model = MediaInfoModel(report: report)
            let artwork = report.artwork.flatMap(NSImage.init(data:))
            session.showCard(MediaInfoView(model: model, artwork: artwork,
                                           onReveal: { file in
                                               NSWorkspace.shared.activateFileViewerSelecting([file])
                                               session.end()
                                           },
                                           onCopy: { session.perform(.copy(model.text)) },
                                           onOpenMap: { map in
                                               NSWorkspace.shared.open(map)
                                               session.end()
                                           },
                                           onClose: { session.end() }))
        })
    }

    /// 演示用：一段手机拍的 4K 杜比视界视频，带着拍摄地点
    static func demoReport() -> MediaInspector.Report {
        var report = MediaInspector.Report(
            url: URL(fileURLWithPath: "/Users/Shared/旅行.mov"), container: "QuickTime", duration: 83.4, bytes: 412_000_000,
            video: [MediaInspector.VideoTrack(codec: String(localized: "HEVC（H.265）"), width: 3840, height: 2160, frameRate: 29.97,
                                              bitRate: 38_200_000, hdr: String(localized: "Dolby Vision（\("HLG")）"), colorPrimaries: "BT.2020", bitDepth: 10)],
            audio: [MediaInspector.AudioTrack(codec: "AAC", channels: 2, sampleRate: 48_000, bitRate: 128_000, language: nil)],
            subtitles: [])
        report.device = "Apple iPhone 15 Pro"
        report.created = Date(timeIntervalSince1970: 1_790_000_000)
        report.location = MediaInspector.Location(latitude: 31.2304, longitude: 121.4737)
        return report
    }
}
