import AVFoundation
import Foundation
import UniformTypeIdentifiers

/// 截取音频或视频的一段：写上开始和结束的时间，存成「原名 片段」放在原文件旁边。
/// MP4、MOV、M4A 这些原样截取不重新编码；MP3、WAV 这类存成 M4A。
enum MediaTrim {
    struct Failure: Error, Equatable {
        let message: String
    }

    static func isMedia(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .movie) || type.conforms(to: .audio)
    }

    /// 「1:02:03.5」「1:25」「85」「85.5」→ 秒；分和秒不能超过 59，只有最后一段可以带小数
    static func seconds(_ text: String) -> Double? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return nil }
        var total = 0.0
        for (index, part) in parts.enumerated() {
            let piece = part.trimmingCharacters(in: .whitespaces)
            guard !piece.isEmpty, piece.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }), let value = Double(piece),
                  index == parts.count - 1 || !piece.contains(".") else { return nil }
            if index > 0 && value >= 60 {
                return nil
            }
            total = total * 60 + value
        }
        return total
    }

    /// 「0:10-1:25」「10-85」「1:00-」（到结尾）「-0:30」（从头开始）→ 一段时间（秒）；写错或者超出时长时返回 nil
    static func range(_ text: String, duration: Double) -> ClosedRange<Double>? {
        guard duration > 0 else { return nil }
        var normalized = text.replacingOccurrences(of: "：", with: ":").replacingOccurrences(of: "到", with: "-")
        for dash in ["～", "~", "—", "–", "－"] {
            normalized = normalized.replacingOccurrences(of: dash, with: "-")
        }
        let pieces = normalized.split(separator: "-", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        guard pieces.count == 2, let start = pieces[0].isEmpty ? 0 : seconds(pieces[0]),
              let end = pieces[1].isEmpty ? duration : seconds(pieces[1]) else { return nil }
        // 时长是四舍五入显示的，结束时间多出来不到一秒也算到结尾
        guard end <= duration + 1 else { return nil }
        let clamped = min(end, duration)
        guard start < clamped else { return nil }
        return start...clamped
    }

    /// 65.5 → 1:05.5，3725 → 1:02:05
    static func label(_ seconds: Double) -> String {
        let tenths = Int((seconds * 10).rounded())
        let text = FileInfo.duration(Double(tenths / 10))
        return tenths % 10 == 0 ? text : "\(text).\(tenths % 10)"
    }

    /// 存成什么：原来的格式能原样截取就用原来的，不然视频存 MOV、音频存 M4A
    static func plan(for url: URL) -> (url: URL, type: AVFileType, preset: String) {
        let base = url.deletingPathExtension().lastPathComponent + " 片段"
        let folder = url.deletingLastPathComponent()
        let passthrough: [String: AVFileType] = ["mp4": .mp4, "mov": .mov, "m4v": .m4v, "m4a": .m4a]
        let ext = url.pathExtension.lowercased()
        if let type = passthrough[ext] {
            return (FileNames.available(in: folder, base: base, extension: ext), type, AVAssetExportPresetPassthrough)
        }
        if UTType(filenameExtension: ext)?.conforms(to: .audio) == true {
            return (FileNames.available(in: folder, base: base, extension: "m4a"), .m4a, AVAssetExportPresetAppleM4A)
        }
        return (FileNames.available(in: folder, base: base, extension: "mov"), .mov, AVAssetExportPresetPassthrough)
    }

    /// 时长（秒）；读不到时返回 nil
    static func duration(of url: URL) async -> Double? {
        guard let time = try? await AVURLAsset(url: url).load(.duration), time.seconds.isFinite, time.seconds > 0 else { return nil }
        return time.seconds
    }

    /// 截取一段，返回新文件
    static func trim(_ url: URL, range: ClosedRange<Double>) async throws -> URL {
        let target = plan(for: url)
        guard let session = AVAssetExportSession(asset: AVURLAsset(url: url), presetName: target.preset) else {
            throw Failure(message: "这台 Mac 截取不了「\(url.lastPathComponent)」")
        }
        session.timeRange = CMTimeRange(start: CMTime(seconds: range.lowerBound, preferredTimescale: 600),
                                        end: CMTime(seconds: range.upperBound, preferredTimescale: 600))
        do {
            try await session.export(to: target.url, as: target.type)
        } catch {
            try? FileManager.default.removeItem(at: target.url)
            throw Failure(message: "截取「\(url.lastPathComponent)」失败：\(error.localizedDescription)")
        }
        return target.url
    }
}
