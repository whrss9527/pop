import AVFoundation
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 视频转换：转成 GIF、转成 MP4、压缩到 720p、提取音频。结果存在原视频旁边，不覆盖原文件。
enum VideoConverter {
    enum Operation: String, CaseIterable, Identifiable {
        case gif
        case mp4
        case compress
        case audio
        case contactSheet

        var id: String { rawValue }

        var title: String {
            switch self {
            case .gif: return String(localized: "转成 GIF")
            case .mp4: return String(localized: "转成 MP4")
            case .compress: return String(localized: "压缩到 720p")
            case .audio: return String(localized: "提取音频")
            case .contactSheet: return String(localized: "拼缩略图")
            }
        }

        /// 开始转换时的提示
        var progress: String {
            switch self {
            case .gif: return String(localized: "正在转成 GIF…")
            case .mp4: return String(localized: "正在转成 MP4…")
            case .compress: return String(localized: "正在压缩视频…")
            case .audio: return String(localized: "正在提取音频…")
            case .contactSheet: return String(localized: "正在拼缩略图…")
            }
        }

        /// 转换好了的提示
        var done: String {
            switch self {
            case .gif: return String(localized: "已转成 GIF")
            case .mp4: return String(localized: "已转成 MP4")
            case .compress: return String(localized: "已压缩到 720p")
            case .audio: return String(localized: "已提取音频")
            case .contactSheet: return String(localized: "已拼成缩略图")
            }
        }

        var fileExtension: String {
            switch self {
            case .gif: return "gif"
            case .mp4, .compress: return "mp4"
            case .audio: return "m4a"
            case .contactSheet: return "jpg"
            }
        }
    }

    struct Failure: Error, Equatable {
        let message: String
    }

    /// GIF 每秒几帧
    static let gifFrameRate: Double = 10
    /// GIF 最宽多少像素
    static let gifMaxWidth: CGFloat = 640
    /// GIF 最多转前多少秒
    static let gifMaxDuration: Double = 60

    static func isVideo(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension)?.conforms(to: .movie) == true
    }

    /// 新文件名：「原名.gif」；压缩的叫「原名 720p.mp4」，缩略图叫「原名 缩略图.jpg」，原来就是 MP4 的叫「原名 转换.mp4」；
    /// 已经有同名文件时再加编号
    static func outputURL(for url: URL, operation: Operation) -> URL {
        var base = url.deletingPathExtension().lastPathComponent
        switch operation {
        case .compress:
            base += " 720p"
        case .contactSheet:
            base += String(localized: " 缩略图")
        case .mp4 where url.pathExtension.lowercased() == operation.fileExtension:
            base += String(localized: " 转换")
        default:
            break
        }
        return FileNames.available(in: url.deletingLastPathComponent(), base: base, extension: operation.fileExtension)
    }

    /// 转换一个视频，返回新文件的位置，以及需要告诉用户的话（比如 GIF 只转了前 60 秒）
    static func convert(_ url: URL, _ operation: Operation) async throws -> (url: URL, note: String?) {
        let asset = AVURLAsset(url: url)
        let output = outputURL(for: url, operation: operation)
        do {
            var note: String?
            switch operation {
            case .gif:
                note = try await makeGIF(from: asset, to: output)
            case .mp4:
                try await export(asset, preset: AVAssetExportPresetHighestQuality, to: output, as: .mp4)
            case .compress:
                try await export(asset, preset: AVAssetExportPreset1280x720, to: output, as: .mp4)
            case .audio:
                let tracks = try await asset.loadTracks(withMediaType: .audio)
                guard !tracks.isEmpty else { throw Failure(message: String(localized: "「\(url.lastPathComponent)」没有声音")) }
                try await export(asset, preset: AVAssetExportPresetAppleM4A, to: output, as: .m4a)
            case .contactSheet:
                let bytes = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
                try await ContactSheet.make(from: asset, name: url.lastPathComponent, fileSize: bytes, to: output)
            }
            return (output, note)
        } catch let failure as Failure {
            try? FileManager.default.removeItem(at: output)
            throw failure
        } catch {
            try? FileManager.default.removeItem(at: output)
            throw Failure(message: String(localized: "转换「\(url.lastPathComponent)」失败：\(error.localizedDescription)"))
        }
    }

    private static func export(_ asset: AVURLAsset, preset: String, to output: URL, as fileType: AVFileType) async throws {
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw Failure(message: String(localized: "这台 Mac 不支持这样转换"))
        }
        session.shouldOptimizeForNetworkUse = true
        try await session.export(to: output, as: fileType)
    }

    /// 按固定的帧率取画面，存成循环播放的 GIF；太长的只转前 60 秒
    private static func makeGIF(from asset: AVURLAsset, to output: URL) async throws -> String? {
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else { throw Failure(message: String(localized: "读不到视频的时长")) }
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard !videoTracks.isEmpty else { throw Failure(message: String(localized: "这个文件里没有画面")) }
        let times = frameTimes(duration: min(duration, gifMaxDuration), frameRate: gifFrameRate)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        // 宽度不超过 640（竖着拍的视频也按宽度算），不会放大
        generator.maximumSize = CGSize(width: gifMaxWidth, height: gifMaxWidth * 4)
        // 取时间点附近的那一帧，不要就近的关键帧，不然会一顿一顿的
        let tolerance = CMTime(seconds: 0.5 / gifFrameRate, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance

        guard let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.gif.identifier as CFString,
                                                                times.count, nil) else {
            throw Failure(message: ImageConverter.cannotCreateMessage(output, type: .gif))
        }
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        let delay = 1 / gifFrameRate
        let frameProperties = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay,
                                                               kCGImagePropertyGIFUnclampedDelayTime: delay]] as CFDictionary
        // 某一帧取不出来时用上一帧补上，帧数和时间都不乱
        var last: CGImage?
        var missing = 0
        for await result in generator.images(for: times.map { CMTime(seconds: $0, preferredTimescale: 600) }) {
            try Task.checkCancellation()
            switch result {
            case .success(requestedTime: _, image: let image, actualTime: _):
                for _ in 0...missing {
                    CGImageDestinationAddImage(destination, image, frameProperties)
                }
                missing = 0
                last = image
            case .failure(requestedTime: _, error: _):
                if let last {
                    CGImageDestinationAddImage(destination, last, frameProperties)
                } else {
                    missing += 1
                }
            }
        }
        guard last != nil else { throw Failure(message: String(localized: "没能从视频里取出画面")) }
        guard CGImageDestinationFinalize(destination) else { throw Failure(message: String(localized: "存储 GIF 失败")) }
        return duration > gifMaxDuration ? String(localized: "视频比较长，只转了前 \(Int(gifMaxDuration)) 秒") : nil
    }

    /// 按帧率均匀取的时间点（秒）：从 0 开始，不超过视频的长度，至少一帧
    static func frameTimes(duration: Double, frameRate: Double) -> [Double] {
        guard duration > 0, frameRate > 0 else { return [] }
        let count = max(Int((duration * frameRate + 1e-9).rounded(.down)), 1)
        return (0..<count).map { Double($0) / frameRate }
    }

    /// 视频的时长、画面大小、文件大小
    static func summary(of url: URL) async -> [ResultCard.Row] {
        let asset = AVURLAsset(url: url)
        var rows: [ResultCard.Row] = []
        if let time = try? await asset.load(.duration), time.seconds.isFinite, time.seconds > 0 {
            rows.append(ResultCard.Row(label: String(localized: "时长"), value: FileInfo.duration(time.seconds)))
        }
        if let track = try? await asset.loadTracks(withMediaType: .video).first,
           let size = try? await track.load(.naturalSize), size.width > 0,
           let transform = try? await track.load(.preferredTransform) {
            // 手机竖着拍的视频画面是横着存的，按播放时的方向算
            let upright = size.applying(transform)
            rows.append(ResultCard.Row(label: String(localized: "画面"), value: "\(Int(abs(upright.width).rounded())) × \(Int(abs(upright.height).rounded()))"))
        }
        if let bytes = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
            rows.append(ResultCard.Row(label: String(localized: "大小"), value: ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)))
        }
        return rows
    }
}
