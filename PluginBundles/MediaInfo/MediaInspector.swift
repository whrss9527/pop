import AVFoundation
import CoreMedia
import Foundation
import UniformTypeIdentifiers
@testable import Pop

/// 媒体信息：视频的编码、分辨率、帧率、码率、HDR 和色域，音频的编码、声道、采样率和语言，字幕轨，
/// 还有拍摄设备、拍摄时间和拍摄地点（手机拍的视频里带着）。音乐文件读标题、艺人、专辑和封面。
enum MediaInspector {
    struct Failure: Error, Equatable {
        let message: String
    }

    struct VideoTrack: Equatable {
        /// 「HEVC（H.265）」「H.264」「ProRes 422 HQ」……
        let codec: String
        /// 播放时的宽高（竖着拍的已经转过来）
        let width: Int
        let height: Int
        /// 帧/秒
        let frameRate: Double
        /// 比特/秒；读不到为 0
        let bitRate: Double
        /// 「Dolby Vision（HLG）」「HDR10」「HLG」；不是 HDR 为 nil
        let hdr: String?
        /// 色域：「BT.709」「BT.2020」「Display P3」
        let colorPrimaries: String?
        /// 每种颜色几位：8、10
        let bitDepth: Int?
    }

    struct AudioTrack: Equatable {
        let codec: String
        let channels: Int
        /// 赫兹
        let sampleRate: Double
        /// 比特/秒；读不到为 0
        let bitRate: Double
        /// 「英语」；没写语言时为 nil
        let language: String?
    }

    /// 纬度、经度
    struct Location: Equatable {
        let latitude: Double
        let longitude: Double
    }

    struct Report: Equatable {
        let url: URL
        /// 「MP4」「QuickTime」「M4A」……
        let container: String
        /// 秒
        let duration: Double
        let bytes: Int64
        let video: [VideoTrack]
        let audio: [AudioTrack]
        /// 字幕轨的语言（没写语言的叫「字幕」）
        let subtitles: [String]
        /// 音乐文件的标题、艺人、专辑
        var title: String? = nil
        var artist: String? = nil
        var album: String? = nil
        /// 拍摄设备：「Apple iPhone 15 Pro」
        var device: String? = nil
        /// 剪辑、导出它的软件
        var software: String? = nil
        var created: Date? = nil
        var location: Location? = nil
        /// 音乐文件的封面
        var artwork: Data? = nil

        /// 整个文件的平均码率（比特/秒）
        var overallBitRate: Double {
            duration > 0 ? Double(bytes) * 8 / duration : 0
        }
    }

    static func isMedia(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else { return false }
        return type.conforms(to: .audiovisualContent)
    }

    static func inspect(_ url: URL) async throws -> Report {
        let asset = AVURLAsset(url: url)
        guard let tracks = try? await asset.load(.tracks), !tracks.isEmpty else {
            throw Failure(message: String(localized: "读不了「\(url.lastPathComponent)」：系统不认识这种格式"))
        }
        let time = try? await asset.load(.duration)
        let duration = time.map(\.seconds).flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? 0
        var video: [VideoTrack] = []
        var audio: [AudioTrack] = []
        var subtitles: [String] = []
        for track in tracks {
            switch track.mediaType {
            case .video:
                if let item = await videoTrack(track) { video.append(item) }
            case .audio:
                if let item = await audioTrack(track) { audio.append(item) }
            case .subtitle, .closedCaption, .text:
                subtitles.append(await language(of: track) ?? String(localized: "字幕"))
            default:
                break
            }
        }
        let bytes = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        var report = Report(url: url, container: container(of: url), duration: duration, bytes: bytes,
                            video: video, audio: audio, subtitles: subtitles)
        let items = (try? await asset.load(.commonMetadata)) ?? []
        func string(_ identifier: AVMetadataIdentifier) async -> String? {
            guard let item = AVMetadataItem.metadataItems(from: items, filteredByIdentifier: identifier).first,
                  let value = try? await item.load(.stringValue) else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        report.title = await string(.commonIdentifierTitle)
        report.artist = await string(.commonIdentifierArtist)
        report.album = await string(.commonIdentifierAlbumName)
        report.device = device(make: await string(.commonIdentifierMake), model: await string(.commonIdentifierModel))
        report.software = await string(.commonIdentifierSoftware)
        if let item = AVMetadataItem.metadataItems(from: items, filteredByIdentifier: .commonIdentifierCreationDate).first {
            report.created = try? await item.load(.dateValue)
        }
        report.location = (await string(.commonIdentifierLocation)).flatMap(location(iso6709:))
        if let item = AVMetadataItem.metadataItems(from: items, filteredByIdentifier: .commonIdentifierArtwork).first {
            report.artwork = try? await item.load(.dataValue)
        }
        return report
    }

    // MARK: - 视频

    private static func videoTrack(_ track: AVAssetTrack) async -> VideoTrack? {
        guard let (descriptions, size, transform, rate, dataRate) = try? await track.load(
            .formatDescriptions, .naturalSize, .preferredTransform, .nominalFrameRate, .estimatedDataRate) else { return nil }
        // 竖着拍的视频画面是横着存的，播放时按 preferredTransform 转过来
        let shown = size.applying(transform)
        let width = Int(abs(shown.width).rounded())
        let height = Int(abs(shown.height).rounded())
        guard let description = descriptions.first else {
            return VideoTrack(codec: String(localized: "认不出"), width: width, height: height, frameRate: Double(rate),
                              bitRate: Double(dataRate), hdr: nil, colorPrimaries: nil, bitDepth: nil)
        }
        let code = fourCC(CMFormatDescriptionGetMediaSubType(description))
        return VideoTrack(codec: videoCodec(code), width: width, height: height, frameRate: Double(rate), bitRate: Double(dataRate),
                          hdr: hdr(description), colorPrimaries: colorPrimaries(description), bitDepth: bitDepth(description))
    }

    static func videoCodec(_ code: String) -> String {
        switch code {
        case "avc1", "avc3": return "H.264"
        case "hvc1", "hev1", "dvh1", "dvhe": return String(localized: "HEVC（H.265）")
        case "av01", "dav1": return "AV1"
        case "vp09": return "VP9"
        case "vp08": return "VP8"
        case "apco": return "ProRes 422 Proxy"
        case "apcs": return "ProRes 422 LT"
        case "apcn": return "ProRes 422"
        case "apch": return "ProRes 422 HQ"
        case "ap4h": return "ProRes 4444"
        case "ap4x": return "ProRes 4444 XQ"
        case "aprn": return "ProRes RAW"
        case "aprh": return "ProRes RAW HQ"
        case "mp4v": return "MPEG-4"
        case "mp2v", "mpg2": return "MPEG-2"
        case "jpeg", "mjpa", "mjpb": return "Motion JPEG"
        case "h263", "s263": return "H.263"
        case "dvc ", "dvcp", "dvpp", "dv5n", "dv5p": return "DV"
        case "png ": return "PNG"
        case "rle ": return "Animation"
        default: return code.trimmingCharacters(in: .whitespaces).uppercased()
        }
    }

    private static func extensions(_ description: CMFormatDescription) -> [String: Any] {
        CMFormatDescriptionGetExtensions(description) as? [String: Any] ?? [:]
    }

    private static func atoms(_ description: CMFormatDescription) -> [String: Any] {
        extensions(description)[kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms as String] as? [String: Any] ?? [:]
    }

    /// HDR：传输函数是 HLG 或者 PQ（HDR10）；带杜比视界的配置（dvcC、dvvC）时是 Dolby Vision
    static func hdr(_ description: CMFormatDescription) -> String? {
        let transfer = extensions(description)[kCMFormatDescriptionExtension_TransferFunction as String] as? String
        let base: String?
        if transfer == kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG as String {
            base = "HLG"
        } else if transfer == kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ as String {
            base = "HDR10"
        } else {
            base = nil
        }
        let code = fourCC(CMFormatDescriptionGetMediaSubType(description))
        let dolby = ["dvh1", "dvhe", "dav1"].contains(code) || ["dvcC", "dvvC", "dvwC"].contains { atoms(description)[$0] != nil }
        guard dolby else { return base }
        return base.map { String(localized: "Dolby Vision（\($0)）") } ?? "Dolby Vision"
    }

    static func colorPrimaries(_ description: CMFormatDescription) -> String? {
        guard let primaries = extensions(description)[kCMFormatDescriptionExtension_ColorPrimaries as String] as? String else { return nil }
        let names: [String: String] = [
            kCMFormatDescriptionColorPrimaries_ITU_R_709_2 as String: "BT.709",
            kCMFormatDescriptionColorPrimaries_ITU_R_2020 as String: "BT.2020",
            kCMFormatDescriptionColorPrimaries_P3_D65 as String: "Display P3",
            kCMFormatDescriptionColorPrimaries_DCI_P3 as String: "DCI-P3",
            kCMFormatDescriptionColorPrimaries_SMPTE_C as String: "SMPTE C",
            kCMFormatDescriptionColorPrimaries_EBU_3213 as String: "EBU 3213",
        ]
        return names[primaries]
    }

    /// 每种颜色几位：格式里写了就用它，没写时看 HEVC、H.264 的档次（Main 10、High 10 是 10 位）
    static func bitDepth(_ description: CMFormatDescription) -> Int? {
        if let bits = extensions(description)["BitsPerComponent"] as? Int {
            return bits
        }
        let boxes = atoms(description)
        if let hvcC = boxes["hvcC"] as? Data, hvcC.count > 1 {
            switch hvcC[hvcC.startIndex + 1] & 0x1F {
            case 1: return 8
            case 2: return 10
            default: return nil
            }
        }
        if let avcC = boxes["avcC"] as? Data, avcC.count > 1 {
            switch avcC[avcC.startIndex + 1] {
            case 66, 77, 88, 100: return 8
            case 110, 122: return 10
            default: return nil
            }
        }
        return nil
    }

    // MARK: - 音频

    private static func audioTrack(_ track: AVAssetTrack) async -> AudioTrack? {
        guard let (descriptions, dataRate) = try? await track.load(.formatDescriptions, .estimatedDataRate),
              let description = descriptions.first,
              let format = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee else { return nil }
        return AudioTrack(codec: audioCodec(fourCC(format.mFormatID)), channels: Int(format.mChannelsPerFrame),
                          sampleRate: format.mSampleRate, bitRate: Double(dataRate), language: await language(of: track))
    }

    static func audioCodec(_ code: String) -> String {
        switch code {
        case "aac ": return "AAC"
        case "aach": return "HE-AAC"
        case "aacp": return "HE-AAC v2"
        case "aacl": return "AAC-LC"
        case "aace", "aacf", "aacg": return "AAC-ELD"
        case "alac": return String(localized: "ALAC（无损）")
        case "flac": return String(localized: "FLAC（无损）")
        case "lpcm": return String(localized: "PCM（不压缩）")
        case ".mp3": return "MP3"
        case ".mp2": return "MP2"
        case "ac-3": return String(localized: "Dolby Digital（AC-3）")
        case "ec-3": return String(localized: "Dolby Digital Plus（E-AC-3）")
        case "opus": return "Opus"
        case "apac": return String(localized: "APAC（空间音频）")
        case "samr": return "AMR"
        case "sawb": return "AMR-WB"
        case "ulaw": return "μ-law"
        case "alaw": return "A-law"
        case "ima4": return "IMA ADPCM"
        default: return code.trimmingCharacters(in: CharacterSet(charactersIn: " .")).uppercased()
        }
    }

    /// 「单声道」「立体声」「5.1 声道」
    static func channels(_ count: Int) -> String {
        switch count {
        case 1: return String(localized: "单声道")
        case 2: return String(localized: "立体声")
        case 6: return String(localized: "5.1 声道")
        case 8: return String(localized: "7.1 声道")
        default: return String(localized: "\(String(count)) 声道")
        }
    }

    // MARK: - 其他

    /// 轨道的语言；没写或者写的是 und（未定）时为 nil
    static func language(of track: AVAssetTrack) async -> String? {
        let tag = try? await track.load(.extendedLanguageTag)
        let code = try? await track.load(.languageCode)
        guard let identifier = [tag, code].compactMap({ $0 }).first(where: { !$0.isEmpty && $0 != "und" }) else { return nil }
        return languageName(identifier)
    }

    /// 「eng」「en-US」→「英语」「英语（美国）」（按界面的语言写）
    static func languageName(_ identifier: String) -> String {
        let canonical = Locale.canonicalLanguageIdentifier(from: identifier)
        return Localization.locale.localizedString(forIdentifier: canonical) ?? identifier
    }

    /// 容器格式：按扩展名
    static func container(of url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "mov", "qt": return "QuickTime"
        case "mp4": return "MP4"
        case "m4v": return "M4V"
        case "m4a": return "M4A"
        case "3gp": return "3GP"
        case "aif", "aiff": return "AIFF"
        case "mts", "m2ts": return "AVCHD"
        case let other: return other.uppercased()
        }
    }

    /// 「Apple」「iPhone 15 Pro」→「Apple iPhone 15 Pro」；型号里已经带着厂商时不重复
    static func device(make: String?, model: String?) -> String? {
        switch (make, model) {
        case let (make?, model?):
            return model.lowercased().hasPrefix(make.lowercased()) ? model : "\(make) \(model)"
        case let (make?, nil): return make
        case let (nil, model?): return model
        case (nil, nil): return nil
        }
    }

    /// ISO 6709 写法「+31.2304+121.4737+012.345/」→ 纬度、经度（第三个数是海拔，不用）
    static func location(iso6709 text: String) -> Location? {
        var numbers: [Double] = []
        var current = ""
        for character in text {
            if character == "+" || character == "-" || character == "/" {
                if let value = Double(current) { numbers.append(value) }
                current = character == "/" ? "" : String(character)
                if character == "/" { break }
            } else {
                current.append(character)
            }
        }
        if let value = Double(current) { numbers.append(value) }
        guard numbers.count >= 2, abs(numbers[0]) <= 90, abs(numbers[1]) <= 180 else { return nil }
        return Location(latitude: numbers[0], longitude: numbers[1])
    }

    static func fourCC(_ code: FourCharCode) -> String {
        let bytes = [24, 16, 8, 0].map { UInt8((code >> $0) & 0xFF) }
        return String(bytes: bytes, encoding: .macOSRoman) ?? String(code)
    }

    // MARK: - 写法

    /// 「1:02:05」「3:07」
    static func duration(_ seconds: Double) -> String {
        FileInfo.duration(seconds)
    }

    /// 「38.2 Mbps」「128 kbps」
    static func bitRate(_ bits: Double) -> String {
        if bits >= 1_000_000 {
            return trimmed(String(format: "%.1f", bits / 1_000_000)) + " Mbps"
        }
        return String(format: "%.0f kbps", bits / 1000)
    }

    /// 「29.97」「30」「23.976」
    static func frameRate(_ rate: Double) -> String {
        trimmed(String(format: "%.3f", rate))
    }

    /// 「48 kHz」「44.1 kHz」
    static func sampleRate(_ hertz: Double) -> String {
        trimmed(String(format: "%.1f", hertz / 1000)) + " kHz"
    }

    /// 分辨率的叫法：按长边，4K、1080p……不是常见的尺寸时为 nil
    static func resolutionName(width: Int, height: Int) -> String? {
        let long = max(width, height)
        let short = min(width, height)
        let names: [(long: Int, short: Int, name: String)] = [
            (7680, 4320, "8K"), (4096, 2160, "4K"), (3840, 2160, "4K"), (2560, 1440, "1440p"),
            (1920, 1080, "1080p"), (1280, 720, "720p"), (854, 480, "480p"), (640, 480, "480p"),
        ]
        guard let match = names.first(where: { abs($0.long - long) <= 8 && short <= $0.short + 8 }) else { return nil }
        return width < height ? String(localized: "\(match.name) 竖屏") : match.name
    }

    /// 去掉小数点后面多余的 0
    private static func trimmed(_ text: String) -> String {
        guard text.contains(".") else { return text }
        var result = text
        while result.hasSuffix("0") { result.removeLast() }
        if result.hasSuffix(".") { result.removeLast() }
        return result
    }

    // MARK: - 去掉位置

    /// 去掉拍摄地点这类个人信息另存一份（画面和声音原样复制，不重新编码），存成原文件旁边的「原名 无位置」
    static func exportWithoutLocation(_ url: URL) async throws -> URL {
        let ext = url.pathExtension.lowercased()
        let type: AVFileType = ext == "mp4" ? .mp4 : ext == "m4v" ? .m4v : ext == "m4a" ? .m4a : .mov
        let output = FileNames.available(in: url.deletingLastPathComponent(),
                                         base: String(localized: "\(url.deletingPathExtension().lastPathComponent) 无位置"),
                                         extension: type == .mov ? "mov" : ext)
        guard let session = AVAssetExportSession(asset: AVURLAsset(url: url), presetName: AVAssetExportPresetPassthrough) else {
            throw Failure(message: String(localized: "这台 Mac 处理不了「\(url.lastPathComponent)」"))
        }
        // 留下拍摄时间、设备这类信息，去掉位置和别的能认出人的信息
        session.metadataItemFilter = .forSharing()
        do {
            try await session.export(to: output, as: type)
        } catch {
            try? FileManager.default.removeItem(at: output)
            throw Failure(message: String(localized: "另存「\(url.lastPathComponent)」失败：\(error.localizedDescription)"))
        }
        return output
    }
}
