import SwiftUI
@testable import Pop

/// 对比图片卡片：并排、滑动、叠加、差异四种看法。复制、存储、贴到屏幕的是当前看到的样子，按原图大小画。
@MainActor
final class ImageCompareModel: ObservableObject {
    nonisolated static let modeKey = "pop.compareImages.mode"
    nonisolated static let subtleKey = "pop.compareImages.ignoreSubtle"

    /// 上次用的看法，没用过时看差异
    nonisolated static var savedMode: ImageDiff.Mode {
        UserDefaults.standard.string(forKey: modeKey).flatMap(ImageDiff.Mode.init(rawValue:)) ?? .difference
    }

    nonisolated static var savedIgnoringSubtle: Bool {
        UserDefaults.standard.bool(forKey: subtleKey)
    }

    let prepared: ImageDiff.Prepared
    /// 旧的（修改时间早的）在前
    let firstName: String
    let secondName: String
    @Published private(set) var outcome: ImageDiff.Outcome
    @Published var mode: ImageDiff.Mode {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: Self.modeKey) }
    }
    /// 滑动时分界线的位置（0 是最左边）
    @Published var split = 0.5
    /// 叠加时新图的不透明度
    @Published var opacity = 0.5
    @Published var ignoringSubtle: Bool {
        didSet {
            guard ignoringSubtle != oldValue else { return }
            UserDefaults.standard.set(ignoringSubtle, forKey: Self.subtleKey)
            recompare()
        }
    }
    /// 连着切换时只用最后一次的结果
    private var generation = 0

    init(prepared: ImageDiff.Prepared, outcome: ImageDiff.Outcome, firstName: String, secondName: String,
         mode: ImageDiff.Mode = ImageCompareModel.savedMode, ignoringSubtle: Bool = ImageCompareModel.savedIgnoringSubtle) {
        self.prepared = prepared
        self.outcome = outcome
        self.firstName = firstName
        self.secondName = secondName
        self.mode = mode
        self.ignoringSubtle = ignoringSubtle
    }

    /// 怎么比的、找到几处
    var details: String {
        [outcome.summary, ImageDiff.note(prepared.canvas)].compactMap { $0 }.joined(separator: String(localized: "；"))
    }

    /// 按原图大小画好当前看到的样子
    func renderPNG() async -> Data? {
        let mode = self.mode
        let split = self.split
        let opacity = self.opacity
        let prepared = self.prepared
        let difference = outcome.difference
        return await runInBackground {
            ImageDiff.compose(mode, first: prepared.first, second: prepared.second, difference: difference,
                              split: split, opacity: opacity).flatMap(ImageDiff.png)
        }
    }

    private func recompare() {
        generation += 1
        let current = generation
        let prepared = self.prepared
        let ignoring = ignoringSubtle
        Task { [weak self] in
            let outcome = await runInBackground { ImageDiff.outcome(prepared, ignoringSubtle: ignoring) }
            guard let self, current == self.generation else { return }
            self.outcome = outcome
        }
    }
}

struct ImageCompareView: View {
    @ObservedObject var model: ImageCompareModel
    var onCopy: () -> Void
    var onSave: () -> Void
    var onPin: () -> Void
    var onClose: () -> Void

    var body: some View {
        CardContainer(title: String(localized: "对比图片"), subtitle: "\(model.firstName) → \(model.secondName)", width: 520,
                      onClose: onClose) {
            // 上面一行：看法，右边是这种看法的设置（高度不变，切换时卡片不跳）
            HStack(spacing: 10) {
                Picker("看法", selection: $model.mode) {
                    ForEach(ImageDiff.Mode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Spacer(minLength: 0)
                modeOptions
            }
            .frame(height: 22)
            stage
                .frame(height: 280)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
            Text(model.details)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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

    @ViewBuilder
    private var modeOptions: some View {
        switch model.mode {
        case .sideBySide:
            EmptyView()
        case .swipe:
            Text("拖动中间的分界线")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .overlay:
            HStack(spacing: 6) {
                Text("旧")
                Slider(value: $model.opacity, in: 0...1)
                    .frame(width: 120)
                Text("新")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        case .difference:
            Toggle("忽略细微差别", isOn: $model.ignoringSubtle)
                .toggleStyle(.checkbox)
                .help(String(localized: "压缩过的照片、导出过的截图会有肉眼看不出的杂色，打开后不算"))
        }
    }

    private var stage: some View {
        GeometryReader { proxy in
            let area = proxy.size
            switch model.mode {
            case .sideBySide:
                let half = CGSize(width: (area.width - 8) / 2, height: area.height)
                let rect = Self.fitted(model.prepared.canvas, in: half)
                HStack(spacing: 8) {
                    picture(model.prepared.firstPreview, rect: rect, in: half, tag: String(localized: "旧"), corner: .topLeading)
                    picture(model.prepared.secondPreview, rect: rect, in: half, tag: String(localized: "新"), corner: .topLeading)
                }
            case .swipe:
                swipe(Self.fitted(model.prepared.canvas, in: area))
            case .overlay:
                let rect = Self.fitted(model.prepared.canvas, in: area)
                ZStack(alignment: .topLeading) {
                    image(model.prepared.firstPreview)
                    image(model.prepared.secondPreview)
                        .opacity(model.opacity)
                }
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
            case .difference:
                let rect = Self.fitted(model.prepared.canvas, in: area)
                Group {
                    if let preview = model.outcome.differencePreview {
                        image(preview)
                    } else {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
            }
        }
    }

    /// 滑动：新图垫在下面，旧图只露出分界线左边；在图上按住拖动分界线
    private func swipe(_ rect: CGRect) -> some View {
        let edge = rect.width * CGFloat(model.split)
        return ZStack(alignment: .topLeading) {
            image(model.prepared.secondPreview)
            image(model.prepared.firstPreview)
                .mask(alignment: .leading) {
                    Rectangle()
                        .frame(width: max(edge, 0))
                }
            Rectangle()
                .fill(Color.white)
                .frame(width: 2, height: rect.height)
                .shadow(color: .black.opacity(0.35), radius: 1)
                .offset(x: edge - 1)
            Circle()
                .fill(Color.white)
                .frame(width: 22, height: 22)
                .shadow(color: .black.opacity(0.3), radius: 2)
                .overlay(Image(systemName: "arrow.left.and.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.65)))
                .offset(x: edge - 11, y: rect.height / 2 - 11)
            tagView(String(localized: "旧"))
                .padding(6)
                .opacity(model.split > 0.12 ? 1 : 0)
            tagView(String(localized: "新"))
                .padding(6)
                .frame(width: rect.width, alignment: .trailing)
                .opacity(model.split < 0.88 ? 1 : 0)
        }
        .frame(width: rect.width, height: rect.height)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { value in
            model.split = Double(min(max(value.location.x / max(rect.width, 1), 0), 1))
        })
        .position(x: rect.midX, y: rect.midY)
    }

    private func picture(_ cgImage: CGImage, rect: CGRect, in area: CGSize, tag: String, corner: Alignment) -> some View {
        ZStack(alignment: corner) {
            image(cgImage)
            tagView(tag)
                .padding(6)
        }
        .frame(width: rect.width, height: rect.height)
        .frame(width: area.width, height: area.height)
    }

    private func image(_ cgImage: CGImage) -> some View {
        Image(decorative: cgImage, scale: 1)
            .resizable()
            .interpolation(.high)
    }

    private func tagView(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.black.opacity(0.55)))
    }

    /// 画布按比例放进 size 里，居中
    static func fitted(_ canvas: ImageDiff.Canvas, in size: CGSize) -> CGRect {
        let width = CGFloat(max(canvas.width, 1))
        let height = CGFloat(max(canvas.height, 1))
        let scale = min(size.width / width, size.height / height)
        let fitted = CGSize(width: width * scale, height: height * scale)
        return CGRect(x: (size.width - fitted.width) / 2, y: (size.height - fitted.height) / 2, width: fitted.width, height: fitted.height)
    }
}
