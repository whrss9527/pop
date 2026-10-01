import SwiftUI
@testable import Pop

/// 截图美化卡片：换背景、留白、比例、圆角和阴影时，预览跟着变；复制、存储、贴到屏幕时按原图大小画一张。
@MainActor
final class BeautifyModel: ObservableObject {
    let image: CGImage
    @Published var options: ScreenshotBeautifier.Options {
        didSet { schedulePreview() }
    }
    @Published private(set) var preview: CGImage?
    /// 预览用缩小过的截图
    private let thumbnail: CGImage
    /// 连着改的时候只画最后一次
    private var generation = 0

    init(image: CGImage, options: ScreenshotBeautifier.Options = .saved) {
        self.image = image
        self.options = options
        thumbnail = ScreenshotBeautifier.downscaled(image, maxSide: 900)
        schedulePreview()
    }

    /// 马上画好预览（演示用）
    func prepare() async {
        generation += 1
        let thumbnail = self.thumbnail
        let options = self.options
        preview = await runInBackground { ScreenshotBeautifier.render(thumbnail, options: options) }
    }

    /// 按原图大小画好的 PNG；顺便记住这次的样子
    func renderPNG() async -> Data? {
        options.save()
        let image = self.image
        let options = self.options
        return await runInBackground {
            ScreenshotBeautifier.render(image, options: options).flatMap(ScreenshotBeautifier.png)
        }
    }

    private func schedulePreview() {
        generation += 1
        let current = generation
        let thumbnail = self.thumbnail
        let options = self.options
        Task { [weak self] in
            let rendered = await runInBackground { ScreenshotBeautifier.render(thumbnail, options: options) }
            guard let self, current == self.generation else { return }
            self.preview = rendered
        }
    }
}

struct BeautifyView: View {
    @ObservedObject var model: BeautifyModel
    var onCopy: () -> Void
    var onSave: () -> Void
    var onPin: () -> Void
    var onClose: () -> Void

    var body: some View {
        CardContainer(title: String(localized: "截图美化"), subtitle: "\(model.image.width) × \(model.image.height)", width: 440, onClose: onClose) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(0.05))
                if let preview = model.preview {
                    Image(decorative: preview, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(6)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .frame(height: 220)
            // 左边一列按最长的那个名字排齐（英文的「Background」比中文长）
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    label(String(localized: "背景"))
                    HStack(spacing: 8) {
                        ForEach(AnnotationBackground.allCases) { background in
                            swatchButton(background)
                        }
                        swatchButton(nil)
                    }
                }
                GridRow {
                    label(String(localized: "留白"))
                    Picker("留白", selection: $model.options.padding) {
                        ForEach(ScreenshotBeautifier.Padding.allCases) { padding in
                            Text(padding.title).tag(padding)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                GridRow {
                    label(String(localized: "比例"))
                    Picker("比例", selection: $model.options.ratio) {
                        ForEach(ScreenshotBeautifier.Ratio.allCases) { ratio in
                            Text(ratio.title).tag(ratio)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
            }
            HStack(spacing: 14) {
                Toggle("圆角", isOn: $model.options.corners)
                Toggle("阴影", isOn: $model.options.shadow)
                Spacer()
            }
            .toggleStyle(.checkbox)
            HStack(spacing: 8) {
                Spacer()
                Button("贴到屏幕", action: onPin)
                Button("存到「下载」", action: onSave)
                Button("复制图片", action: onCopy)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .controlSize(.small)
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize()
    }

    /// 背景色块：渐变的圆点，透明（nil）是虚线圈；选中的外面加一圈
    private func swatchButton(_ background: AnnotationBackground?) -> some View {
        let title = background?.title ?? String(localized: "透明")
        return Button {
            model.options.background = background
        } label: {
            ZStack {
                if let background {
                    Circle()
                        .fill(LinearGradient(colors: background.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                } else {
                    Circle()
                        .strokeBorder(Color.primary.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                }
            }
            .frame(width: 20, height: 20)
            .padding(3)
            .overlay(Circle().strokeBorder(model.options.background == background ? Color.accentColor : Color.clear, lineWidth: 2))
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
    }
}
