import SwiftUI

/// 加水印卡片：改文字和浓淡时，预览跟着变；确认后给选中的每张图片另存一份加了水印的。
@MainActor
final class WatermarkModel: ObservableObject {
    let files: [URL]
    @Published var text: String {
        didSet { schedulePreview() }
    }
    @Published var opacity: Double {
        didSet { schedulePreview() }
    }
    @Published private(set) var preview: CGImage?
    /// 连着改的时候只算最后一次
    private var generation = 0

    init(files: [URL], text: String? = nil, opacity: Double = 0.3) {
        self.files = files
        self.text = text ?? UserDefaults.standard.string(forKey: ImageWatermark.textKey) ?? ImageWatermark.defaultText
        self.opacity = opacity
        schedulePreview()
    }

    /// 「张图片」或者（有 PDF 时）「个文件」
    var unit: String {
        files.contains(where: ImageWatermark.isPDF) ? "个文件" : "张图片"
    }

    var canApply: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !files.isEmpty
    }

    /// 下次打开时还用这次的文字
    func remember() {
        UserDefaults.standard.set(text, forKey: ImageWatermark.textKey)
    }

    private func schedulePreview() {
        generation += 1
        let current = generation
        guard let first = files.first else { return }
        let text = self.text
        let opacity = self.opacity
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard let self, current == self.generation else { return }
            let image = await runInBackground { ImageWatermark.preview(first, text: text, opacity: opacity) }
            guard current == self.generation else { return }
            self.preview = image
        }
    }
}

struct WatermarkView: View {
    @ObservedObject var model: WatermarkModel
    var onApply: () -> Void
    var onClose: () -> Void

    private var subtitle: String {
        model.files.count == 1 ? model.files[0].lastPathComponent : "\(model.files.count) \(model.unit)"
    }

    var body: some View {
        CardContainer(title: "加水印", subtitle: subtitle, width: 420, onClose: onClose) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(0.05))
                if let preview = model.preview {
                    Image(decorative: preview, scale: 2)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .padding(6)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .frame(height: 200)
            TextField("水印文字", text: $model.text)
                .textFieldStyle(.roundedBorder)
            HStack(spacing: 8) {
                Text("淡")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: $model.opacity, in: 0.1...0.6)
                Text("浓")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .controlSize(.small)
            Text("斜着铺满整张图（PDF 每一页都铺），另存一份「原名 水印」放在原文件旁边，原文件不动")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Spacer()
                Button(model.files.count == 1 ? "加水印" : "给 \(model.files.count) \(model.unit)加水印", action: onApply)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canApply)
            }
            .controlSize(.small)
        }
    }
}
