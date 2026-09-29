import AppKit
import Carbon.HIToolbox
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

// MARK: - 窗口布局

struct WindowLayoutPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.windowLayout, name: "窗口布局", symbol: "rectangle.split.2x1",
                          summary: "把当前窗口放到屏幕的左半边、右半边、三分之一、最大化、居中，或者移到另一个显示器", accepts: [])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        .showWindowLayouts
    }
}

struct WindowLayoutCardView: View {
    var hasMultipleDisplays: Bool
    var onChoose: (WindowLayout) -> Void
    var onClose: () -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 5)

    var body: some View {
        CardContainer(title: "窗口布局", subtitle: "方向键放到半屏，回车最大化", width: 404, onClose: onClose) {
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(WindowLayout.allCases) { layout in
                    LayoutTile(layout: layout, enabled: layout != .nextDisplay || hasMultipleDisplays) {
                        onChoose(layout)
                    }
                }
            }
        }
    }

    /// 键盘选择：← → ↑ ↓ 放到对应的半屏，回车最大化，C 居中，1–3 放到三分之一
    static func layout(for event: NSEvent) -> WindowLayout? {
        guard event.modifierFlags.intersection([.command, .option, .control]).isEmpty else { return nil }
        switch Int(event.keyCode) {
        case kVK_LeftArrow: return .leftHalf
        case kVK_RightArrow: return .rightHalf
        case kVK_UpArrow: return .topHalf
        case kVK_DownArrow: return .bottomHalf
        case kVK_Return, kVK_ANSI_KeypadEnter: return .maximize
        case kVK_ANSI_C: return .center
        case kVK_ANSI_1: return .leftThird
        case kVK_ANSI_2: return .centerThird
        case kVK_ANSI_3: return .rightThird
        default: return nil
        }
    }
}

private struct LayoutTile: View {
    let layout: WindowLayout
    let enabled: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: layout.symbol)
                    .font(.system(size: 17))
                    .frame(height: 22)
                Text(layout.title)
                    .font(.system(size: 10))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(hovering && enabled ? 0.14 : 0.05)))
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .help(layout.title)
        .onHover { hovering = $0 }
        .animation(Motion.content, value: hovering)
    }
}

// MARK: - 图片转换

struct ImageConvertPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.imageConvert, name: "图片转换", symbol: "photo.on.rectangle.angled",
                          summary: "把选中的图片文件转成 PNG、JPEG、HEIC，缩小一半、压缩体积，旋转、左右翻转，或者去掉照片里的位置和拍摄信息；结果存在原图旁边",
                          accepts: [.imageFile])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        let files = content.files.filter(ContentClassifier.isImageFile)
        guard !files.isEmpty else { return .failure("没有选中图片文件") }
        let rows = files.count == 1 ? ImageInfo.rows(for: files[0]) : []
        let what = files.count == 1 ? files[0].lastPathComponent : "\(files.count) 张图片"
        // 照片里有位置、拍摄信息时才给去掉的按钮
        let metadata = files.prefix(200).compactMap(PhotoMetadata.read)
        let hasLocation = metadata.contains { $0.hasLocation }
        let hasCapture = metadata.contains { !$0.isEmpty }
        let operations = ImageConverter.Operation.allCases.filter { operation in
            switch operation {
            case .removeLocation: return hasLocation
            case .removeMetadata: return hasCapture
            default: return true
            }
        }
        return .card(ResultCard(title: "图片转换", detail: "\(what)，转换后存在原图旁边", rows: rows,
                                buttons: operations.map { operation in
                                    CardButton(title: operation.title, action: .convertImages(files, operation))
                                }))
    }
}

enum ImageInfo {
    /// 尺寸、格式、文件大小
    static func rows(for url: URL) -> [ResultCard.Row] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return [] }
        var rows: [ResultCard.Row] = []
        if let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int {
            rows.append(ResultCard.Row(label: "尺寸", value: "\(width) × \(height)"))
        }
        if let identifier = CGImageSourceGetType(source) as String?, let type = UTType(identifier) {
            rows.append(ResultCard.Row(label: "格式", value: type.preferredFilenameExtension?.uppercased() ?? identifier))
        }
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
            rows.append(ResultCard.Row(label: "大小", value: ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)))
        }
        return rows
    }
}

// MARK: - 换行排列

/// 一行放不下时自动换到下一行的排列（结果卡片底部的按钮）
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var width: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            width = max(width, x + size.width)
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: proposal.width ?? width, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
