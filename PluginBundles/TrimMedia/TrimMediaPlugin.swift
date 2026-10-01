import AppKit
@testable import Pop

/// 插件包「截取片段」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopTrimMediaEntry)
final class TrimMediaEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [TrimMediaPlugin()]
    }
}

struct TrimMediaPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.trimMedia, name: String(localized: "截取片段"), symbol: "scissors",
                          summary: String(localized: "截取选中的音频或视频的一段（写上开始和结束的时间），存在原文件旁边"),
                          accepts: [.files], pattern: #"(?im)\.(mov|mp4|m4v|3gp|m4a|mp3|wav|aiff?|aac|caf|flac)$"#)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let file = content.files.first(where: MediaTrim.isMedia) else { return .failure(String(localized: "没有选中音频或视频文件")) }
        return .trimMedia(file)
    }
}
