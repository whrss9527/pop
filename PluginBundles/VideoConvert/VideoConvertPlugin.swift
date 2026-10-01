import AppKit
@testable import Pop

/// 插件包「视频转换」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopVideoConvertEntry)
final class VideoConvertEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [VideoConvertPlugin()]
    }
}

struct VideoConvertPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.videoConvert, name: String(localized: "视频转换"), symbol: "film",
                          summary: String(localized: "把选中的视频转成 GIF、转成 MP4、压缩到 720p、提取音频，或者均匀取 16 帧拼成一张缩略图；结果存在原视频旁边"),
                          accepts: [.files], pattern: #"(?im)\.(mov|mp4|m4v|3gp)$"#)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        let videos = content.files.filter(VideoConverter.isVideo)
        guard let first = videos.first else { return .failure(String(localized: "没有选中视频文件")) }
        var rows: [ResultCard.Row] = []
        if videos.count == 1 {
            rows = await VideoConverter.summary(of: first)
        }
        // 本来就是 MP4 的不用再转
        let operations = VideoConverter.Operation.allCases.filter { operation in
            operation != .mp4 || !videos.allSatisfy { $0.pathExtension.lowercased() == "mp4" }
        }
        let gif = String(localized: "GIF 每秒 \(Int(VideoConverter.gifFrameRate)) 帧、宽度不超过 \(Int(VideoConverter.gifMaxWidth))，最多转前 \(Int(VideoConverter.gifMaxDuration)) 秒")
        var buttons = operations.map { operation in
            CardButton(title: operation.title, action: .convertVideos(videos, operation))
        }
        if videos.count == 1 {
            buttons.append(CardButton(title: String(localized: "截取一段…"), action: .trimMedia(first)))
        }
        return .card(ResultCard(title: String(localized: "视频转换"),
                                body: videos.count == 1 ? first.lastPathComponent : String(localized: "\(videos.count) 个视频"),
                                detail: String(localized: "转换后存在原视频旁边；\(gif)"),
                                rows: rows,
                                buttons: buttons))
    }
}
