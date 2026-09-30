import SwiftUI

/// 截取片段卡片：写上开始和结束的时间，截出这一段另存一份。
@MainActor
final class MediaTrimModel: ObservableObject {
    let file: URL
    /// 时长（秒）
    let duration: Double
    @Published var input = ""

    init(file: URL, duration: Double) {
        self.file = file
        self.duration = duration
    }

    var range: ClosedRange<Double>? {
        MediaTrim.range(input, duration: duration)
    }

    var isInvalid: Bool {
        !input.trimmingCharacters(in: .whitespaces).isEmpty && range == nil
    }

    var summary: String {
        if input.trimmingCharacters(in: .whitespaces).isEmpty {
            return "一共 \(MediaTrim.label(duration))。写上开始和结束的时间，比如 0:10-1:25（1:25- 是到结尾）"
        }
        guard let range else { return "时间写得不对，或者超出了 0:00–\(MediaTrim.label(duration))" }
        return "从 \(MediaTrim.label(range.lowerBound)) 到 \(MediaTrim.label(range.upperBound))，"
            + "一共 \(MediaTrim.label(range.upperBound - range.lowerBound))"
    }
}

struct MediaTrimView: View {
    @ObservedObject var model: MediaTrimModel
    var onTrim: (ClosedRange<Double>) -> Void
    var onClose: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        CardContainer(title: "截取片段", subtitle: model.file.lastPathComponent, width: 400, onClose: onClose) {
            TextField("开始-结束，比如 0:10-1:25", text: $model.input)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit(submit)
            Text(model.summary)
                .font(.caption)
                .foregroundStyle(model.isInvalid ? Color.red : Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Spacer()
                Button("截取这一段", action: submit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.range == nil)
            }
            .controlSize(.small)
        }
        .task {
            focused = true
        }
    }

    private func submit() {
        if let range = model.range {
            onTrim(range)
        }
    }
}
