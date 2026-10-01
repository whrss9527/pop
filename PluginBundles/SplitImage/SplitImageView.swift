import SwiftUI
@testable import Pop

/// 切分图片卡片：换切法时预览跟着变（用不到的部分压暗，画出格线和编号），「切好存下」按原图切。
@MainActor
final class SplitImageModel: ObservableObject {
    nonisolated static let layoutKey = "pop.splitImage.layout"

    /// 上次用的切法，没用过时切九宫格
    nonisolated static var savedLayout: ImageSplitter.Layout {
        UserDefaults.standard.string(forKey: layoutKey).flatMap(ImageSplitter.Layout.init(rawValue:)) ?? .nine
    }

    let image: CGImage
    /// 卡片上显示用的小图
    let preview: CGImage
    let name: String
    /// 画面里最吸引注意的地方（像素），网格尽量对准它
    let focus: CGRect?
    @Published var layout: ImageSplitter.Layout

    init(image: CGImage, name: String, focus: CGRect?, layout: ImageSplitter.Layout? = nil) {
        self.image = image
        self.name = name
        self.focus = focus
        preview = Self.downscaled(image, maxSide: 900)
        // 长图先按分页切；不是长图时没有分页这一项
        let long = ImageSplitter.isLong(CGSize(width: image.width, height: image.height))
        let wanted = layout ?? (long ? .pages : Self.savedLayout)
        self.layout = wanted == .pages && !long ? .nine : wanted
    }

    var size: CGSize {
        CGSize(width: image.width, height: image.height)
    }

    /// 能选的切法：长图才有分页
    var layouts: [ImageSplitter.Layout] {
        ImageSplitter.Layout.allCases.filter { $0 != .pages || ImageSplitter.isLong(size) }
    }

    var plan: ImageSplitter.Plan {
        ImageSplitter.plan(size, layout: layout, focus: focus)
    }

    /// 存的文件夹叫什么（同名的已经有了时实际会在后面加 2、3）
    var folderName: String {
        (name as NSString).deletingPathExtension + " " + layout.title
    }

    func remember() {
        UserDefaults.standard.set(layout.rawValue, forKey: Self.layoutKey)
    }

    private static func downscaled(_ image: CGImage, maxSide: Int) -> CGImage {
        let longest = max(image.width, image.height)
        guard longest > maxSide else { return image }
        let scale = CGFloat(maxSide) / CGFloat(longest)
        let width = max(Int((CGFloat(image.width) * scale).rounded()), 1)
        let height = max(Int((CGFloat(image.height) * scale).rounded()), 1)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }
}

struct SplitImageView: View {
    @ObservedObject var model: SplitImageModel
    var onSplit: () -> Void
    var onClose: () -> Void

    var body: some View {
        let plan = model.plan
        CardContainer(title: String(localized: "切分图片"), subtitle: model.name, width: 440, onClose: onClose) {
            Picker("切法", selection: $model.layout) {
                ForEach(model.layouts) { layout in
                    Text(layout.title).tag(layout)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            preview(plan)
                .frame(height: 260)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
            Text(String(localized: "\(ImageSplitter.describe(plan))，按编号的顺序存在原图旁边的「\(model.folderName)」文件夹"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Spacer()
                Button("切好存下", action: onSplit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(plan.tiles.isEmpty)
            }
        }
        .controlSize(.small)
    }

    /// 预览：用不到的部分压暗，每张画上框和编号
    private func preview(_ plan: ImageSplitter.Plan) -> some View {
        GeometryReader { proxy in
            let width = CGFloat(model.image.width)
            let height = CGFloat(model.image.height)
            let scale = min((proxy.size.width - 12) / width, (proxy.size.height - 12) / height)
            let shown = CGSize(width: width * scale, height: height * scale)
            ZStack {
                Image(decorative: model.preview, scale: 1)
                    .resizable()
                    .interpolation(.high)
                Canvas { context, size in
                    let ratio = size.width / width
                    func scaled(_ rect: CGRect) -> CGRect {
                        CGRect(x: rect.minX * ratio, y: rect.minY * ratio, width: rect.width * ratio, height: rect.height * ratio)
                    }
                    var outside = Path(CGRect(origin: .zero, size: size))
                    outside.addRect(scaled(plan.region))
                    context.fill(outside, with: .color(.black.opacity(0.55)), style: FillStyle(eoFill: true))
                    context.drawLayer { layer in
                        layer.addFilter(.shadow(color: .black.opacity(0.5), radius: 1.5))
                        for (index, tile) in plan.tiles.enumerated() {
                            let rect = scaled(tile)
                            layer.stroke(Path(rect), with: .color(.white.opacity(0.95)), lineWidth: 1.5)
                            layer.draw(Text(verbatim: "\(index + 1)").font(.system(size: 13, weight: .semibold)).foregroundColor(.white),
                                       at: CGPoint(x: rect.midX, y: rect.midY))
                        }
                    }
                }
            }
            .frame(width: shown.width, height: shown.height)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
    }
}
