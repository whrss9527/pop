import AVFoundation
import Foundation
@testable import Pop

/// 把文字用系统语音读出来存成音频（AAC 的 .m4a）：配音、听力材料都能用。
final class SpeechExporter {
    struct Failure: Error, Equatable {
        let message: String
    }

    /// 存好的文件和多长（秒）
    struct Output: Equatable {
        let url: URL
        let duration: TimeInterval
    }

    private let synthesizer = AVSpeechSynthesizer()
    private var file: AVAudioFile?
    private var frames: AVAudioFramePosition = 0
    private var finished = false

    /// 读完、写完以后返回。语音不能导出（有的 Siri 语音不行）时报错
    func export(_ text: String, voice: AVSpeechSynthesisVoice?, to url: URL) async throws -> Output {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        return try await withCheckedThrowingContinuation { continuation in
            // 回调一个接一个地来，最后来一个空的表示读完了
            synthesizer.write(utterance) { buffer in
                guard !self.finished, let pcm = buffer as? AVAudioPCMBuffer else { return }
                if pcm.frameLength == 0 {
                    self.finished = true
                    let rate = self.file?.processingFormat.sampleRate ?? 0
                    // 放掉文件，写完关上
                    self.file = nil
                    if self.frames > 0, rate > 0 {
                        continuation.resume(returning: Output(url: url, duration: Double(self.frames) / rate))
                    } else {
                        try? FileManager.default.removeItem(at: url)
                        continuation.resume(throwing: Failure(message: String(localized: "这个语音不能存成音频，到「系统设置 → 辅助功能 → 朗读内容」里换一个系统语音试试")))
                    }
                    return
                }
                do {
                    if self.file == nil {
                        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: pcm.format.sampleRate,
                                                       AVNumberOfChannelsKey: pcm.format.channelCount, AVEncoderBitRateKey: 64_000]
                        self.file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: pcm.format.commonFormat,
                                                    interleaved: pcm.format.isInterleaved)
                    }
                    try self.file?.write(from: pcm)
                    self.frames += AVAudioFramePosition(pcm.frameLength)
                } catch {
                    self.finished = true
                    self.file = nil
                    self.synthesizer.stopSpeaking(at: .immediate)
                    continuation.resume(throwing: Failure(message: String(localized: "存音频时出错了：\(error.localizedDescription)")))
                }
            }
        }
    }

    /// 和朗读用一样的语音：中文用普通话（繁体用台湾的），其他按语言找
    static func voice(for language: String?) -> AVSpeechSynthesisVoice? {
        guard let language else { return nil }
        let code: String
        if language.hasPrefix("zh-Hant") {
            code = "zh-TW"
        } else if language.hasPrefix("zh") {
            code = "zh-CN"
        } else {
            code = language
        }
        let voices = AVSpeechSynthesisVoice.speechVoices()
        return voices.first { $0.language == code } ?? voices.first { $0.language.hasPrefix(code) }
    }

    /// 文件名：「朗读 」加上开头的几个字（去掉换行和不能用的字符）
    static func fileName(for text: String, limit: Int = 12) -> String {
        let words = text.components(separatedBy: .newlines).joined(separator: " ")
            .replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let head = words.count > limit ? String(words.prefix(limit)).trimmingCharacters(in: .whitespaces) + "…" : words
        return head.isEmpty ? String(localized: "朗读") : String(localized: "朗读 \(head)")
    }

    /// 「1 分 20 秒」「12 秒」
    static func describe(_ duration: TimeInterval) -> String {
        let seconds = max(Int(duration.rounded()), 1)
        if seconds < 60 { return String(localized: "\(seconds) 秒") }
        return seconds % 60 == 0 ? String(localized: "\(seconds / 60) 分钟") : String(localized: "\(seconds / 60) 分 \(seconds % 60) 秒")
    }
}
