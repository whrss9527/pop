import Foundation

// MARK: - 拼接图片

struct StitchImagesPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.stitchImages, name: String(localized: "拼接图片"), symbol: "square.split.1x2",
                          summary: String(localized: "把选中的几张图片按文件名的顺序竖着或者横着拼成一张，或者合成一张动图，存在第一张旁边"),
                          accepts: [.imageFile])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        let images = ImageStitcher.ordered(content.files.filter(ContentClassifier.isImageFile))
        guard images.count >= 2 else { return .failure(String(localized: "选中两张以上的图片才能拼接")) }
        guard images.count <= ImageStitcher.maxCount else { return .failure(String(localized: "一次最多拼 \(ImageStitcher.maxCount) 张")) }
        let shown = 8
        var names = images.prefix(shown).map(\.lastPathComponent)
        if images.count > shown {
            names.append(String(localized: "……还有 \(images.count - shown) 张"))
        }
        let delay = Int(ImageStitcher.gifFrameDelay)
        let stitch = ImageStitcher.Direction.allCases.map { direction in
            CardButton(title: direction.title, action: .stitchImages(images, direction))
        }
        return .card(ResultCard(title: String(localized: "拼接图片"), body: names.joined(separator: "\n"),
                                detail: String(localized: "\(images.count) 张图片按上面的顺序拼接；宽度（横着拼时是高度）不一样时按最小的那张缩放。合成动图时每张停 \(delay) 秒，画面大小按第一张"),
                                buttons: stitch + [CardButton(title: String(localized: "合成动图"), action: .animateImages(images))]))
    }
}

// MARK: - 加水印

struct WatermarkPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.watermark, name: String(localized: "加水印"), symbol: "signature",
                          summary: String(localized: "给选中的图片或 PDF 斜着铺满一层半透明的文字（比如「仅供办理业务使用」），另存一份放在原文件旁边"),
                          accepts: [.files], pattern: #"(?im)\.(pdf|jpe?g|png|heic|heif|tiff?|gif|bmp|webp)$"#)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        let files = content.files.filter { ContentClassifier.isImageFile($0) || ImageWatermark.isPDF($0) }
        guard !files.isEmpty else { return .failure(String(localized: "没有选中图片或 PDF")) }
        return .watermark(files)
    }
}

// MARK: - 视频转换

struct IDPhotoPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.idPhoto, name: String(localized: "证件照"), symbol: "person.crop.rectangle",
                          summary: String(localized: "把人像照片换成白底、蓝底或红底，按人脸位置裁成一寸、二寸（300 dpi）；在本机处理，另存一份放在原图旁边"),
                          accepts: [.imageFile])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let file = content.files.first(where: IDPhoto.isImage) else { return .failure(String(localized: "没有选中照片")) }
        return .idPhoto(file)
    }
}

struct CropImagePlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.cropImage, name: String(localized: "裁剪图片"), symbol: "crop",
                          summary: String(localized: "把选中的图片裁成 1:1、4:3、3:4、16:9、9:16，自动对准画面里的主体；另存一份放在原图旁边"),
                          accepts: [.imageFile])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        let images = content.files.filter(ContentClassifier.isImageFile)
        guard !images.isEmpty else { return .failure(String(localized: "没有选中图片")) }
        return .card(Self.card(images))
    }

    static func card(_ images: [URL]) -> ResultCard {
        let question = images.count == 1 ? String(localized: "把「\(images[0].lastPathComponent)」裁成哪种比例？") : String(localized: "把 \(images.count) 张图片裁成哪种比例？")
        return ResultCard(title: String(localized: "裁剪图片"), body: question,
                          detail: String(localized: "在这个比例下裁出最大的一块，自动对准画面里的主体；另存一份放在原图旁边，原图不动"),
                          buttons: SmartCrop.Ratio.allCases.map { CardButton(title: $0.title, action: .cropImages(images, $0)) })
    }
}

struct RedactPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.redact, name: String(localized: "隐私打码"), symbol: "eye.slash",
                          summary: String(localized: "找出选中图片里的人脸、电话号码、邮箱、身份证号、银行卡号和车牌，打上马赛克另存一份；在本机识别，另存的那份不带拍摄信息和位置"),
                          accepts: [.imageFile])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        let images = content.files.filter(ContentClassifier.isImageFile)
        guard let first = images.first else { return .failure(String(localized: "没有选中图片")) }
        let result: Result<Redaction.Preview, Redaction.Failure> = await runInBackground {
            do {
                return .success(try Redaction.preview(first, targets: Redaction.defaultTargets))
            } catch let failure as Redaction.Failure {
                return .failure(failure)
            } catch {
                return .failure(Redaction.Failure(message: error.localizedDescription))
            }
        }
        switch result {
        case .failure(let failure):
            return .failure(failure.message)
        case .success(let preview):
            return .card(Self.card(images, preview: preview))
        }
    }

    /// 预览打好码的第一张；没找到人脸和个人信息时只能选「文字也全部打码」
    static func card(_ images: [URL], preview: Redaction.Preview) -> ResultCard {
        let found = Redaction.summary(preview.regions)
        let detail: String
        if preview.regions.isEmpty {
            detail = String(localized: "没找到人脸和个人信息；要把图里的文字都打上码，点「文字也全部打码」")
        } else if images.count == 1 {
            detail = String(localized: "找到\(found)，预览里已经打上马赛克；存的时候另存一份，原图不动")
        } else {
            detail = String(localized: "第一张找到\(found)；存的时候 \(images.count) 张都会打码，各自另存一份")
        }
        var buttons: [CardButton] = []
        if !preview.regions.isEmpty || images.count > 1 {
            buttons.append(CardButton(title: String(localized: "存到原图旁边"), action: .redactImages(images, Redaction.defaultTargets)))
        }
        buttons.append(CardButton(title: String(localized: "文字也全部打码"), action: .redactImages(images, [.faces, .allText])))
        return ResultCard(title: String(localized: "隐私打码"), detail: detail, image: preview.png, buttons: buttons)
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

// MARK: - 截取片段

struct TrimMediaPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.trimMedia, name: String(localized: "截取片段"), symbol: "scissors",
                          summary: String(localized: "截取选中的音频或视频的一段（写上开始和结束的时间），存在原文件旁边"),
                          accepts: [.files], pattern: #"(?im)\.(mov|mp4|m4v|3gp|m4a|mp3|wav|aiff?|aac|caf|flac)$"#)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let file = content.files.first(where: MediaTrim.isMedia) else { return .failure(String(localized: "没有选中音频或视频文件")) }
        return .trimMedia(file)
    }
}

// MARK: - 批量重命名

struct BatchRenamePlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.batchRename, name: String(localized: "批量重命名"), symbol: "rectangle.and.pencil.and.ellipsis",
                          summary: String(localized: "给选中的文件统一改名：编号、替换文字、加前后缀、按照片的拍摄时间、改大小写，先看预览再改，改完可以撤销"),
                          accepts: [.files])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard !content.files.isEmpty else { return .failure(String(localized: "没有选中文件")) }
        return .rename(content.files)
    }
}
