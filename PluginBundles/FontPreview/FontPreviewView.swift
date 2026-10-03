import AppKit
import SwiftUI
@testable import Pop

/// 字体预览卡片：上面是要预览的文字、大小和筛选，下面一行一个字体，用它显示这段文字。
/// 默认只列能完整显示这段文字的字体；点星号收藏，右键复制字体名、CSS，或者把这一行复制成图片。
/// 选中的是字体文件时，列出文件里的每一款，可以装上。
@MainActor
final class FontPreviewModel: ObservableObject {
    nonisolated static let favoritesKey = "pop.fontPreview.favorites"
    nonisolated static let sizeKey = "pop.fontPreview.size"

    /// 字体文件里的一款（还没装）
    struct Face: Identifiable {
        let postScriptName: String
        let displayName: String
        let font: CTFont

        var id: String { postScriptName }
    }

    @Published var text: String { didSet { scheduleCoverage() } }
    @Published var size: Double { didSet { UserDefaults.standard.set(size, forKey: Self.sizeKey) } }
    @Published var filter: FontCatalog.Filter
    @Published var search = ""
    /// 只列能完整显示这段文字的（选了文字时默认打开；示例文字里有汉字，打开的话西文字体都看不到）
    @Published var onlyCovering: Bool
    @Published private(set) var families: [FontCatalog.Family]
    @Published private(set) var coverage: [String: Bool] = [:]
    @Published private(set) var favorites: Set<String>
    /// 选中的字体文件
    let files: [URL]
    let faces: [Face]
    @Published private(set) var installed: [URL]? = nil
    @Published private(set) var installError: String? = nil
    private var coverageTask: Task<Void, Never>?

    init(text: String?, families: [FontCatalog.Family], files: [URL] = [], faces: [Face] = []) {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let preview = trimmed.isEmpty ? FontCatalog.sample : String(trimmed.prefix(200))
        self.text = preview
        self.families = families
        self.files = files
        self.faces = faces
        let saved = UserDefaults.standard.double(forKey: Self.sizeKey)
        size = saved >= 10 ? saved : 24
        favorites = Set(UserDefaults.standard.stringArray(forKey: Self.favoritesKey) ?? [])
        // 选中的文字有汉字时先看中文字体
        filter = !trimmed.isEmpty && trimmed.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) } ? .chinese : .all
        onlyCovering = !trimmed.isEmpty
        coverage = Self.coverage(of: families, text: preview)
    }

    /// 每个字体能不能完整显示这段文字
    nonisolated static func coverage(of families: [FontCatalog.Family], text: String) -> [String: Bool] {
        var result: [String: Bool] = [:]
        for family in families {
            let font = CTFontCreateWithName(family.postScriptName as CFString, 16, nil)
            result[family.name] = FontCatalog.covers(font, text)
        }
        return result
    }

    /// 文字改了以后在后台重新看一遍（停下打字 0.3 秒以后）
    private func scheduleCoverage() {
        coverageTask?.cancel()
        let families = families
        let text = text
        coverageTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            let result = await runInBackground { Self.coverage(of: families, text: text) }
            guard !Task.isCancelled else { return }
            coverage = result
        }
    }

    var shown: [FontCatalog.Family] {
        FontCatalog.filter(families, by: filter, favorites: favorites, search: search, covering: onlyCovering ? text : nil, coverage: coverage)
    }

    /// 「82 种字体能显示这段文字」
    var summary: String {
        let count = shown.count
        if count == 0 && onlyCovering {
            return String(localized: "没有能完整显示这段文字的字体，取消「只看能显示的」再看看")
        }
        return onlyCovering ? String(localized: "\(count) 种字体能完整显示这段文字") : String(localized: "\(count) 种字体")
    }

    func toggleFavorite(_ family: FontCatalog.Family) {
        if favorites.contains(family.name) {
            favorites.remove(family.name)
        } else {
            favorites.insert(family.name)
        }
        UserDefaults.standard.set(favorites.sorted(), forKey: Self.favoritesKey)
    }

    /// 把这段文字用这个字体画成 PNG（两倍大，透明底）
    func image(_ font: Font) -> Data? {
        let renderer = ImageRenderer(content: Text(text).font(font).foregroundStyle(Color.black).padding(8)
            .frame(maxWidth: 900, alignment: .leading).fixedSize(horizontal: false, vertical: true))
        renderer.scale = 2
        guard let image = renderer.cgImage else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    /// 装上选中的字体文件
    func install(into folder: URL? = nil) {
        do {
            installed = try folder.map { try FontCatalog.install(files, into: $0) } ?? FontCatalog.install(files)
            installError = nil
        } catch {
            installError = String(localized: "装不上：\(error.localizedDescription)")
        }
    }
}

struct FontPreviewView: View {
    @ObservedObject var model: FontPreviewModel
    var onCopy: (String) -> Void
    var onCopyImage: (Data) -> Void
    var onReveal: (URL) -> Void
    var onClose: () -> Void

    var body: some View {
        CardContainer(title: String(localized: "字体预览"), subtitle: model.files.first?.lastPathComponent, width: 480, onClose: onClose) {
            TextField("要预览的文字", text: $model.text, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...3)
            HStack(spacing: 8) {
                Image(systemName: "textformat.size.smaller")
                    .foregroundStyle(.secondary)
                Slider(value: $model.size, in: 12...72)
                    .frame(width: 140)
                Image(systemName: "textformat.size.larger")
                    .foregroundStyle(.secondary)
                Text(String(Int(model.size.rounded())))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 22, alignment: .trailing)
                Spacer()
                if model.faces.isEmpty {
                    TextField("搜索字体", text: $model.search)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                }
            }
            if model.faces.isEmpty {
                installedList
            } else {
                fileFaces
            }
        }
        .controlSize(.small)
    }

    /// 装着的字体
    @ViewBuilder
    private var installedList: some View {
        // 分段和勾选框一行放不下时（英文），勾选框放到下一行，不挤成一个字一行
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                filterPicker
                coveringToggle
            }
            VStack(alignment: .leading, spacing: 6) {
                filterPicker
                coveringToggle
            }
        }
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(model.shown) { family in
                    row(family)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 330)
        Text(model.summary)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private var filterPicker: some View {
        Picker("筛选", selection: $model.filter) {
            ForEach(FontCatalog.Filter.allCases) { filter in
                Text(filter.title).tag(filter)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }

    private var coveringToggle: some View {
        Toggle("只看能显示的", isOn: $model.onlyCovering)
            .toggleStyle(.checkbox)
            .fixedSize()
    }

    private func row(_ family: FontCatalog.Family) -> some View {
        let font = Font.custom(family.postScriptName, size: model.size)
        let favorite = model.favorites.contains(family.name)
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(family.displayName)
                    .font(.caption.weight(.semibold))
                if family.displayName != family.name {
                    Text(family.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(String(localized: "\(family.styles) 种样式"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 0)
                Button {
                    model.toggleFavorite(family)
                } label: {
                    Image(systemName: favorite ? "star.fill" : "star")
                        .foregroundStyle(favorite ? Color.yellow : Color.secondary)
                }
                .buttonStyle(.plain)
                .help(favorite ? String(localized: "取消收藏") : String(localized: "加到收藏"))
            }
            Text(model.text)
                .font(font)
                .lineLimit(2)
                .textSelection(.enabled)
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button("复制字体名") { onCopy(family.name) }
            Button("复制 PostScript 名") { onCopy(family.postScriptName) }
            Button("复制 CSS") { onCopy(FontCatalog.css(family)) }
            Button("复制成图片") {
                if let data = model.image(font) { onCopyImage(data) }
            }
            if let file = family.file {
                Divider()
                Button("在访达中显示字体文件") { onReveal(file) }
            }
        }
    }

    /// 选中的字体文件：每一款显示一行，可以装上
    @ViewBuilder
    private var fileFaces: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(model.faces) { face in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(face.displayName)
                            .font(.caption.weight(.semibold))
                        Text(model.text)
                            .font(Font(CTFontCreateCopyWithAttributes(face.font, model.size, nil, nil)))
                            .lineLimit(2)
                    }
                    .contextMenu {
                        Button("复制 PostScript 名") { onCopy(face.postScriptName) }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: min(CGFloat(model.faces.count) * (model.size * 1.4 + 24), 330))
        if let error = model.installError {
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
        }
        HStack(spacing: 8) {
            if let installed = model.installed {
                Text(String(localized: "装好了，在「字体册」里也能看到"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("在访达中显示") { onReveal(installed[0]) }
                Button("完成", action: onClose)
                    .keyboardShortcut(.defaultAction)
            } else {
                Text(String(localized: "装到「~/资源库/Fonts」，只给你自己用"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("安装") { model.install() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}
