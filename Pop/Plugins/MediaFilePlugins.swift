import Foundation

// MARK: - 拼接图片

struct StitchImagesPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.stitchImages, name: "拼接图片", symbol: "square.split.1x2",
                          summary: "把选中的几张图片按文件名的顺序竖着或者横着拼成一张，或者合成一张动图，存在第一张旁边",
                          accepts: [.imageFile])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        let images = ImageStitcher.ordered(content.files.filter(ContentClassifier.isImageFile))
        guard images.count >= 2 else { return .failure("选中两张以上的图片才能拼接") }
        guard images.count <= ImageStitcher.maxCount else { return .failure("一次最多拼 \(ImageStitcher.maxCount) 张") }
        let shown = 8
        var names = images.prefix(shown).map(\.lastPathComponent)
        if images.count > shown {
            names.append("……还有 \(images.count - shown) 张")
        }
        let delay = Int(ImageStitcher.gifFrameDelay)
        let stitch = ImageStitcher.Direction.allCases.map { direction in
            CardButton(title: direction.title, action: .stitchImages(images, direction))
        }
        return .card(ResultCard(title: "拼接图片", body: names.joined(separator: "\n"),
                                detail: "\(images.count) 张图片按上面的顺序拼接；宽度（横着拼时是高度）不一样时按最小的那张缩放。"
                                    + "合成动图时每张停 \(delay) 秒，画面大小按第一张",
                                buttons: stitch + [CardButton(title: "合成动图", action: .animateImages(images))]))
    }
}

// MARK: - 视频转换

struct VideoConvertPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.videoConvert, name: "视频转换", symbol: "film",
                          summary: "把选中的视频转成 GIF、转成 MP4、压缩到 720p，或者提取音频；结果存在原视频旁边",
                          accepts: [.files], pattern: #"(?im)\.(mov|mp4|m4v|3gp)$"#)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        let videos = content.files.filter(VideoConverter.isVideo)
        guard let first = videos.first else { return .failure("没有选中视频文件") }
        var rows: [ResultCard.Row] = []
        if videos.count == 1 {
            rows = await VideoConverter.summary(of: first)
        }
        // 本来就是 MP4 的不用再转
        let operations = VideoConverter.Operation.allCases.filter { operation in
            operation != .mp4 || !videos.allSatisfy { $0.pathExtension.lowercased() == "mp4" }
        }
        let gif = "GIF 每秒 \(Int(VideoConverter.gifFrameRate)) 帧、宽度不超过 \(Int(VideoConverter.gifMaxWidth))，最多转前 \(Int(VideoConverter.gifMaxDuration)) 秒"
        var buttons = operations.map { operation in
            CardButton(title: operation.title, action: .convertVideos(videos, operation))
        }
        if videos.count == 1 {
            buttons.append(CardButton(title: "截取一段…", action: .trimMedia(first)))
        }
        return .card(ResultCard(title: "视频转换",
                                body: videos.count == 1 ? first.lastPathComponent : "\(videos.count) 个视频",
                                detail: "转换后存在原视频旁边；\(gif)",
                                rows: rows,
                                buttons: buttons))
    }
}

// MARK: - 截取片段

struct TrimMediaPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.trimMedia, name: "截取片段", symbol: "scissors",
                          summary: "截取选中的音频或视频的一段（写上开始和结束的时间），存在原文件旁边",
                          accepts: [.files], pattern: #"(?im)\.(mov|mp4|m4v|3gp|m4a|mp3|wav|aiff?|aac|caf|flac)$"#)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let file = content.files.first(where: MediaTrim.isMedia) else { return .failure("没有选中音频或视频文件") }
        return .trimMedia(file)
    }
}

// MARK: - 批量重命名

struct BatchRenamePlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.batchRename, name: "批量重命名", symbol: "rectangle.and.pencil.and.ellipsis",
                          summary: "给选中的文件统一改名：编号、替换文字、加前后缀、按照片的拍摄时间、改大小写，先看预览再改，改完可以撤销",
                          accepts: [.files])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard !content.files.isEmpty else { return .failure("没有选中文件") }
        return .rename(content.files)
    }
}
