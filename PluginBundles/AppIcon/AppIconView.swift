import SwiftUI
@testable import Pop

/// 生成图标卡片：上面是图标在 macOS、iOS 和浏览器标签页上的样子，下面选样式、留边、底色和要生成哪几种。
@MainActor
final class AppIconModel: ObservableObject {
    nonisolated static let styleKey = "pop.appIcon.style"
    nonisolated static let fillKey = "pop.appIcon.fill"
    nonisolated static let outputsKey = "pop.appIcon.outputs"

    let source: IconMaker.Source
    let name: String
    /// 预览用的小图
    private let small: IconMaker.Source
    @Published var options: IconMaker.Options {
        didSet {
            if options != oldValue { refresh() }
        }
    }
    @Published private(set) var macOSPreview: CGImage?
    @Published private(set) var iOSPreview: CGImage?
    @Published private(set) var faviconPreview: CGImage?

    init(source: IconMaker.Source, name: String, options: IconMaker.Options? = nil) {
        self.source = source
        self.name = name
        small = source.shrunk(toAbout: 512)
        self.options = options ?? Self.savedOptions(for: source)
        refresh()
    }

    /// 上次用的样式、底色和要生成的几种；图片有透明的地方时默认留窄边
    nonisolated static func savedOptions(for source: IconMaker.Source) -> IconMaker.Options {
        var options = IconMaker.Options()
        let defaults = UserDefaults.standard
        if let style = defaults.string(forKey: styleKey).flatMap(IconMaker.Style.init(rawValue:)) {
            options.style = style
        }
        if let fill = defaults.string(forKey: fillKey).flatMap(IconMaker.Fill.init(rawValue:)) {
            options.fill = fill
        }
        if let outputs = defaults.string(forKey: outputsKey)?.split(separator: ",").map(String.init), !outputs.isEmpty {
            options.macOS = outputs.contains("macOS")
            options.iOS = outputs.contains("iOS")
            options.web = outputs.contains("web")
        }
        options.margin = source.hasTransparency ? .narrow : .off
        return options
    }

    func remember() {
        let defaults = UserDefaults.standard
        defaults.set(options.style.rawValue, forKey: Self.styleKey)
        defaults.set(options.fill.rawValue, forKey: Self.fillKey)
        let outputs = [options.macOS ? "macOS" : nil, options.iOS ? "iOS" : nil, options.web ? "web" : nil].compactMap { $0 }
        defaults.set(outputs.joined(separator: ","), forKey: Self.outputsKey)
    }

    /// 底色用不用得上：有透明的地方、留了边，或者整张放进去时空出了地方
    var needsFill: Bool {
        source.hasTransparency || options.margin != .off || (!source.isSquare && options.fit == .whole)
    }

    /// 存的文件夹叫什么（同名的已经有了时实际会在后面加 2、3）
    var folderName: String {
        String(localized: "\((name as NSString).deletingPathExtension) 图标")
    }

    var summary: String {
        var parts: [String] = []
        if options.macOS { parts.append(String(localized: "macOS 的 .icns 和图标集")) }
        if options.iOS { parts.append(String(localized: "iOS 的 1024 图标")) }
        if options.web { parts.append(String(localized: "网站的 favicon")) }
        guard !parts.isEmpty else { return String(localized: "至少选一种要生成的图标") }
        return String(localized: "生成 \(parts.joined(separator: String(localized: "、")))，存在原图旁边的「\(folderName)」文件夹")
    }

    private func refresh() {
        macOSPreview = IconMaker.macOS(small, side: 256, options: options)
        iOSPreview = IconMaker.square(small, side: 128, options: options, opaque: true)
        faviconPreview = IconMaker.square(small, side: 32, options: options)
    }
}

struct AppIconView: View {
    @ObservedObject var model: AppIconModel
    var onMake: () -> Void
    var onClose: () -> Void

    var body: some View {
        CardContainer(title: String(localized: "生成图标"), subtitle: model.name, width: 440, onClose: onClose) {
            previews
                .frame(maxWidth: .infinity)
                .frame(height: 170)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
            // 左边一列按最长的那个名字排齐
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    label(String(localized: "样式"))
                    segmented("样式", selection: $model.options.style, IconMaker.Style.allCases)
                }
                GridRow {
                    label(String(localized: "留边"))
                    segmented("留边", selection: $model.options.margin, IconMaker.Margin.allCases)
                }
                if model.needsFill {
                    GridRow {
                        label(String(localized: "底色"))
                        segmented("底色", selection: $model.options.fill, IconMaker.Fill.allCases)
                    }
                }
                if !model.source.isSquare {
                    GridRow {
                        label(String(localized: "裁切"))
                        segmented("裁切", selection: $model.options.fit, IconMaker.Fit.allCases)
                    }
                }
                GridRow {
                    label(String(localized: "生成"))
                    HStack(spacing: 14) {
                        Toggle("macOS", isOn: $model.options.macOS)
                        Toggle("iOS", isOn: $model.options.iOS)
                        Toggle("网站", isOn: $model.options.web)
                    }
                    .toggleStyle(.checkbox)
                }
            }
            Text(model.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Spacer()
                Button("生成", action: onMake)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.options.any)
            }
        }
        .controlSize(.small)
    }

    /// 三种样子：macOS 上的图标、iOS 主屏幕上（系统加了圆角）、浏览器标签页上的 favicon
    private var previews: some View {
        HStack(alignment: .bottom, spacing: 28) {
            preview("macOS") {
                if let image = model.macOSPreview {
                    Image(decorative: image, scale: 2)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 112, height: 112)
                }
            }
            preview("iOS") {
                if let image = model.iOSPreview {
                    Image(decorative: image, scale: 2)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 13.5, style: .continuous))
                        .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                }
            }
            preview(String(localized: "网站")) {
                HStack(spacing: 6) {
                    if let image = model.faviconPreview {
                        Image(decorative: image, scale: 2)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 16, height: 16)
                    }
                    Text((model.name as NSString).deletingPathExtension)
                        .font(.caption)
                        .lineLimit(1)
                        .frame(maxWidth: 80, alignment: .leading)
                }
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.08)))
            }
        }
        .padding(.bottom, 10)
    }

    private func preview<Content: View>(_ caption: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 8) {
            content()
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func segmented<Value: Hashable & Identifiable & IconOption>(_ title: LocalizedStringKey, selection: Binding<Value>,
                                                                     _ values: [Value]) -> some View {
        Picker(title, selection: selection) {
            ForEach(values) { value in
                Text(value.title).tag(value)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize()
    }
}

/// 卡片上能选的一项（分段选择器里显示 title）
protocol IconOption {
    var title: String { get }
}

extension IconMaker.Style: IconOption {}
extension IconMaker.Margin: IconOption {}
extension IconMaker.Fill: IconOption {}
extension IconMaker.Fit: IconOption {}
