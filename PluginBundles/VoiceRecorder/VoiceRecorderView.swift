import AppKit
import SwiftUI
@testable import Pop

/// 录音小条的状态：在录、暂停、存好了、出错了
@MainActor
final class VoiceRecorderModel: ObservableObject {
    enum Phase: Equatable {
        case recording
        case paused
        case saved(URL, duration: TimeInterval)
        case failed(String)
    }

    /// 音量条有几根
    nonisolated static let barCount = 24

    @Published var phase: Phase = .recording
    /// 录了多久（暂停的时候不算）
    @Published var elapsed: TimeInterval = 0
    /// 最近的音量（0～1），新的在右边
    @Published private(set) var levels = Array(repeating: 0.0, count: VoiceRecorderModel.barCount)
    /// 存好后能不能接着转成文字：装了「语音转文字」、这台 Mac 能识别
    @Published var canTranscribe = false
    /// 指针在小条上：存好后先不收起
    var isHovering = false

    /// 重新开始录
    func reset(canTranscribe: Bool) {
        phase = .recording
        elapsed = 0
        levels = Array(repeating: 0, count: Self.barCount)
        self.canTranscribe = canTranscribe
    }

    func push(_ level: Double) {
        levels.removeFirst()
        levels.append(min(max(level, 0), 1))
    }

    var isRecording: Bool {
        phase == .recording
    }

    /// 「00:42」
    var elapsedText: String {
        ScreenRecording.durationText(elapsed)
    }

    /// 存好后的说明：「存进了「下载」，长 1 分 20 秒」
    var savedDetail: String? {
        guard case .saved(_, let duration) = phase else { return nil }
        return String(localized: "存进了「下载」，长 \(CountdownTimer.title(seconds: max(duration, 1)))")
    }
}

/// 小条上的按钮
struct VoiceRecorderActions {
    var togglePause: () -> Void
    var stop: () -> Void
    var reveal: () -> Void
    var transcribe: () -> Void
    var close: () -> Void
}

/// 屏幕上方的小条：录的时候是红点、时长、音量条、暂停和停止；存好后是文件名、在访达中显示、转成文字
struct VoiceRecorderCapsule: View {
    @ObservedObject var model: VoiceRecorderModel
    let actions: VoiceRecorderActions

    var body: some View {
        content
            .foregroundStyle(.white)
            .padding(.leading, 12)
            .padding(.trailing, 8)
            .padding(.vertical, 7)
            .background(Capsule().fill(Color.black.opacity(0.82)))
            .environment(\.colorScheme, .dark)
            .controlSize(.small)
            .fixedSize()
            .onHover { model.isHovering = $0 }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .recording, .paused:
            HStack(spacing: 10) {
                // 在录时红点一秒闪一下；暂停时是灰的
                Circle()
                    .fill(model.isRecording ? Color.red : Color.gray)
                    .frame(width: 8, height: 8)
                    .opacity(model.isRecording && Int(model.elapsed * 2) % 2 == 1 ? 0.4 : 1)
                Text(verbatim: model.elapsedText)
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                HStack(alignment: .center, spacing: 2) {
                    ForEach(Array(model.levels.enumerated()), id: \.offset) { _, level in
                        Capsule()
                            .fill(Color.white.opacity(model.isRecording ? 0.85 : 0.35))
                            .frame(width: 2, height: 2 + 16 * level)
                    }
                }
                .frame(height: 18)
                Button(action: actions.togglePause) {
                    Image(systemName: model.isRecording ? "pause.fill" : "record.circle")
                        .frame(width: 14)
                }
                .help(model.isRecording ? String(localized: "暂停") : String(localized: "接着录"))
                Button(action: actions.stop) {
                    Image(systemName: "stop.fill")
                        .frame(width: 14)
                }
                .help(String(localized: "停止并保存"))
            }
        case .saved(let url, _):
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: url.lastPathComponent)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let detail = model.savedDetail {
                        Text(detail)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: 230, alignment: .leading)
                Button("在访达中显示", action: actions.reveal)
                if model.canTranscribe {
                    Button("转成文字", action: actions.transcribe)
                }
                closeButton
            }
        case .failed(let message):
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                Text(message)
                    .font(.system(size: 12))
                    .lineLimit(2)
                    .frame(maxWidth: 320, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                closeButton
            }
        }
    }

    private var closeButton: some View {
        Button(action: actions.close) {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold))
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(0.7))
        .help(String(localized: "关闭"))
    }
}
