import AVFoundation
import Foundation
import Speech

/// 语音转文字：用系统的语音识别把录音、视频里说的话转成文字和 SRT 字幕。
/// 这台 Mac 能在本机识别这种语言时只在本机识别（不上传音频）；不能的话交给苹果的服务器，很长的录音可能只识别出一部分。
enum Transcriber {
    /// 识别出来的一个词（或者一个字）和它在录音里的时间
    struct Segment: Equatable {
        var text: String
        var start: TimeInterval
        var duration: TimeInterval

        var end: TimeInterval { start + duration }
    }

    /// 一条字幕
    struct Cue: Equatable {
        var start: TimeInterval
        var end: TimeInterval
        var text: String
    }

    struct Transcript: Equatable {
        var text: String
        var segments: [Segment]
        /// 是不是在本机识别的
        var onDevice: Bool
    }

    struct Failure: LocalizedError, Equatable {
        let message: String

        var errorDescription: String? { message }
    }

    struct Language: Equatable {
        var title: String
        var identifier: String
    }

    static let mediaExtensions: Set<String> = ["m4a", "mp3", "wav", "aac", "aif", "aiff", "caf", "flac", "mov", "mp4", "m4v", "3gp"]
    static let videoExtensions: Set<String> = ["mov", "mp4", "m4v", "3gp"]
    /// 插件的匹配规则：选中的文件里有音频或视频
    static let pattern = #"(?im)\.(m4a|mp3|wav|aac|aif|aiff|caf|flac|mov|mp4|m4v|3gp)$"#

    static func isMedia(_ url: URL) -> Bool {
        mediaExtensions.contains(url.pathExtension.lowercased())
    }

    /// 卡片上能选的语言：这台 Mac 认不了的不列；系统语言不是中文时英语排在前面
    static func languages(preferred: String = Locale.preferredLanguages.first ?? "zh-Hans") -> [Language] {
        var all = [Language(title: String(localized: "普通话"), identifier: "zh-CN"), Language(title: String(localized: "英语"), identifier: "en-US"),
                   Language(title: String(localized: "粤语"), identifier: "zh-HK"), Language(title: String(localized: "日语"), identifier: "ja-JP")]
        if !preferred.hasPrefix("zh"), let english = all.firstIndex(where: { $0.identifier == "en-US" }) {
            let moved = all.remove(at: english)
            all.insert(moved, at: 0)
        }
        return all.filter { SFSpeechRecognizer(locale: Locale(identifier: $0.identifier)) != nil }
    }

    /// 录音或视频有多长（秒）；读不到时为 nil
    static func duration(of url: URL) async -> TimeInterval? {
        guard let seconds = try? await AVURLAsset(url: url).load(.duration).seconds, seconds.isFinite, seconds > 0 else { return nil }
        return seconds
    }

    /// 请求语音识别权限，返回是否允许
    static func authorize() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return true
        case .notDetermined:
            let status = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status)
                }
            }
            return status == .authorized
        default:
            return false
        }
    }

    static func transcribe(_ url: URL, language identifier: String) async throws -> Transcript {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: identifier)) else {
            throw Failure(message: String(localized: "这台 Mac 认不了这种语言"))
        }
        guard recognizer.isAvailable else {
            throw Failure(message: String(localized: "语音识别现在用不了，稍后再试"))
        }
        let audio = try await audioFile(for: url)
        defer {
            if audio != url {
                try? FileManager.default.removeItem(at: audio)
            }
        }
        let request = SFSpeechURLRecognitionRequest(url: audio)
        request.shouldReportPartialResults = false
        request.addsPunctuation = true
        request.taskHint = .dictation
        let onDevice = recognizer.supportsOnDeviceRecognition
        request.requiresOnDeviceRecognition = onDevice
        do {
            return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Transcript, Error>) in
                let gate = ResumeGate()
                _ = recognizer.recognitionTask(with: request) { [recognizer] result, error in
                    // 识别结束前一直留着识别器
                    withExtendedLifetime(recognizer) {}
                    if let result, result.isFinal {
                        let best = result.bestTranscription
                        let segments = best.segments.map { Segment(text: $0.substring, start: $0.timestamp, duration: $0.duration) }
                        if gate.open() {
                            continuation.resume(returning: Transcript(text: best.formattedString, segments: segments, onDevice: onDevice))
                        }
                    } else if let error, gate.open() {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } catch {
            throw Failure(message: describe(error))
        }
    }

    /// 视频先把声音导出成临时的 m4a
    private static func audioFile(for url: URL) async throws -> URL {
        guard videoExtensions.contains(url.pathExtension.lowercased()) else { return url }
        let asset = AVURLAsset(url: url)
        let tracks = (try? await asset.loadTracks(withMediaType: .audio)) ?? []
        guard !tracks.isEmpty else { throw Failure(message: String(localized: "「\(url.lastPathComponent)」里没有声音")) }
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw Failure(message: String(localized: "读不了「\(url.lastPathComponent)」里的声音"))
        }
        let output = FileManager.default.temporaryDirectory.appending(path: "pop-transcribe-\(UUID().uuidString).m4a")
        do {
            try await session.export(to: output, as: .m4a)
        } catch {
            try? FileManager.default.removeItem(at: output)
            throw Failure(message: String(localized: "读不了「\(url.lastPathComponent)」里的声音：\(error.localizedDescription)"))
        }
        return output
    }

    /// 识别失败的原因，说成用户能照着做的话
    static func describe(_ error: Error) -> String {
        if let failure = error as? Failure {
            return failure.message
        }
        let nsError = error as NSError
        switch (nsError.domain, nsError.code) {
        case ("kAFAssistantErrorDomain", 1110):
            return String(localized: "没有听到有人说话")
        case ("kLSRErrorDomain", 201), ("kAFAssistantErrorDomain", 1700):
            return String(localized: "要先在「系统设置 → 键盘 → 听写」里打开听写，才能在本机识别")
        default:
            return String(localized: "识别失败：\(nsError.localizedDescription)")
        }
    }

    // MARK: 字幕

    /// 把一个个词拼成一条条字幕：一句说完（句号、问号……）、停顿超过 1 秒、超过 maxDuration 秒或者字太多就换一条
    static func cues(_ segments: [Segment], language: String, maxDuration: TimeInterval = 6) -> [Cue] {
        let spaced = !["zh", "ja", "yue"].contains { language.hasPrefix($0) }
        let maxCharacters = spaced ? 42 : 18
        var cues: [Cue] = []
        var current: Cue?
        for segment in segments {
            let word = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !word.isEmpty else { continue }
            if var cue = current {
                let joined = cue.text + (spaced ? " " : "") + word
                if segment.start - cue.end > 1 || segment.end - cue.start > maxDuration || joined.count > maxCharacters {
                    cues.append(cue)
                    current = Cue(start: segment.start, end: segment.end, text: word)
                } else {
                    cue.text = joined
                    cue.end = segment.end
                    current = cue
                }
            } else {
                current = Cue(start: segment.start, end: segment.end, text: word)
            }
            if let last = word.last, "。！？!?….".contains(last), let cue = current {
                cues.append(cue)
                current = nil
            }
        }
        if let current {
            cues.append(current)
        }
        return cues
    }

    /// SRT 格式：序号、「开始 --> 结束」、文字，条与条之间空一行
    static func srt(_ cues: [Cue]) -> String {
        cues.enumerated().map { index, cue in
            "\(index + 1)\n\(timestamp(cue.start)) --> \(timestamp(max(cue.end, cue.start + 0.5)))\n\(cue.text)\n"
        }.joined(separator: "\n")
    }

    /// 3725.5 → 「01:02:05,500」
    static func timestamp(_ seconds: TimeInterval) -> String {
        let milliseconds = Int((max(seconds, 0) * 1000).rounded())
        return String(format: "%02d:%02d:%02d,%03d", milliseconds / 3_600_000, milliseconds / 60_000 % 60,
                      milliseconds / 1000 % 60, milliseconds % 1000)
    }

    // MARK: 结果

    /// 存成「原名.txt」和「原名.srt」放在原文件旁边（有同名的就加 2、3……）
    static func save(_ transcript: Transcript, beside url: URL, language: String) throws -> (text: URL, subtitles: URL) {
        let folder = url.deletingLastPathComponent()
        let base = url.deletingPathExtension().lastPathComponent
        let textURL = FileNames.available(in: folder, base: base, extension: "txt")
        let subtitleURL = FileNames.available(in: folder, base: base, extension: "srt")
        do {
            try transcript.text.write(to: textURL, atomically: true, encoding: .utf8)
            try srt(cues(transcript.segments, language: language)).write(to: subtitleURL, atomically: true, encoding: .utf8)
        } catch {
            throw Failure(message: String(localized: "存不了识别结果：\(error.localizedDescription)"))
        }
        return (textURL, subtitleURL)
    }

    static func card(_ transcript: Transcript, file: URL, language: String) -> ResultCard {
        var detail = String(localized: "文字和字幕已经存在「\(file.lastPathComponent)」旁边")
        if !transcript.onDevice {
            detail += String(localized: "；这台 Mac 不能在本机识别这种话，用的是苹果的服务器")
        }
        return ResultCard(title: String(localized: "语音转文字"), detail: detail,
                          tabs: [ResultCard.Tab(title: String(localized: "文字"), text: transcript.text),
                                 ResultCard.Tab(title: String(localized: "字幕 SRT"), text: srt(cues(transcript.segments, language: language)))])
    }
}

/// 续体只能恢复一次：识别的回调可能不止一次
private final class ResumeGate: @unchecked Sendable {
    private let lock = NSLock()
    private var opened = false

    /// 第一次调用返回 true
    func open() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !opened else { return false }
        opened = true
        return true
    }
}
