import AppKit
import Combine
import ImageIO
import SwiftUI

/// 剪贴板历史面板上的分类
enum ClipboardFilter: String, CaseIterable, Identifiable {
    case all, text, image, files, pinned

    var id: Self { self }

    var title: String {
        switch self {
        case .all: return String(localized: "全部")
        case .text: return String(localized: "文字")
        case .image: return String(localized: "图片")
        case .files: return String(localized: "文件")
        case .pinned: return String(localized: "固定")
        }
    }

    func includes(_ item: ClipboardItem) -> Bool {
        switch self {
        case .all: return true
        case .text: return item.kind == .text
        case .image: return item.kind == .image
        case .files: return item.kind == .files
        case .pinned: return item.pinned
        }
    }
}

@MainActor
final class ClipboardHistoryModel: ObservableObject {
    @Published var query = "" {
        didSet { reload() }
    }
    @Published var filter: ClipboardFilter = .all {
        didSet { reload() }
    }
    @Published private(set) var items: [ClipboardItem] = []
    @Published var selection = 0
    /// ⌘ 点选的几条文字，按点选的顺序；回车时合在一起粘贴
    @Published private(set) var marked: [ClipboardItem] = []

    let service: ClipboardService
    var onPaste: (ClipboardItem) -> Void = { _ in }
    /// 几条合在一起粘贴
    var onPasteText: (String) -> Void = { _ in }
    var onOpenSettings: () -> Void = {}
    /// 右键菜单里的「翻译」「贴到屏幕」「识别文字」，由协调器处理
    var onTranslate: (String) -> Void = { _ in }
    var onPin: (ClipboardItem) -> Void = { _ in }
    var onRecognize: (ClipboardItem) -> Void = { _ in }
    var onAnnotate: (ClipboardItem) -> Void = { _ in }
    var onRecognizeTable: (ClipboardItem) -> Void = { _ in }
    var onSaveSnippet: (ClipboardItem) -> Void = { _ in }

    private var cancellable: AnyCancellable?

    init(service: ClipboardService) {
        self.service = service
        reload()
        cancellable = service.changes
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.reload(keepSelection: true)
            }
    }

    var isEnabled: Bool { service.isEnabled }

    var selectedItem: ClipboardItem? {
        items.indices.contains(selection) ? items[selection] : nil
    }

    func reload(keepSelection: Bool = false) {
        let selectedID = keepSelection ? selectedItem?.id : nil
        items = service.items(matching: query).filter(filter.includes)
        if let selectedID, let index = items.firstIndex(where: { $0.id == selectedID }) {
            selection = index
        } else {
            selection = min(keepSelection ? selection : 0, max(items.count - 1, 0))
        }
    }

    func move(_ delta: Int) {
        guard !items.isEmpty else { return }
        selection = min(max(selection + delta, 0), items.count - 1)
    }

    func paste(_ item: ClipboardItem) {
        onPaste(item)
    }

    /// 点一条：按着 ⌘ 时加入（或移出）多选，否则直接粘贴
    func click(_ item: ClipboardItem) {
        if NSEvent.modifierFlags.contains(.command) {
            toggleMark(item)
        } else {
            paste(item)
        }
    }

    /// 只有文字能合在一起
    func toggleMark(_ item: ClipboardItem) {
        guard item.kind == .text else { return }
        if let index = marked.firstIndex(where: { $0.id == item.id }) {
            marked.remove(at: index)
        } else {
            marked.append(item)
        }
    }

    /// 在多选里排第几（从 1 开始）；没选时为 nil
    func markNumber(of item: ClipboardItem) -> Int? {
        marked.firstIndex { $0.id == item.id }.map { $0 + 1 }
    }

    /// 多选的几条按点选的顺序、每条一行合起来
    var mergedText: String {
        marked.map(\.text).joined(separator: "\n")
    }

    /// 搜索时图片是因为里面的文字被找到的：显示找到的那一段
    func matchedImageText(for item: ClipboardItem) -> String? {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard item.kind == .image, !keyword.isEmpty, let text = item.recognizedText else { return nil }
        return Self.excerpt(of: text, around: keyword)
    }

    /// 关键词前后各留几个字：「…会议改到周五下午…」
    static func excerpt(of text: String, around keyword: String, context: Int = 8) -> String? {
        let flat = text.replacingOccurrences(of: "\n", with: " ")
        guard let range = flat.range(of: keyword, options: [.caseInsensitive, .diacriticInsensitive]) else { return nil }
        let start = flat.index(range.lowerBound, offsetBy: -context, limitedBy: flat.startIndex) ?? flat.startIndex
        let end = flat.index(range.upperBound, offsetBy: context, limitedBy: flat.endIndex) ?? flat.endIndex
        return (start > flat.startIndex ? "…" : "") + flat[start..<end] + (end < flat.endIndex ? "…" : "")
    }

    func togglePin(_ item: ClipboardItem) {
        service.setPinned(!item.pinned, item: item)
    }

    func delete(_ item: ClipboardItem) {
        service.delete(item)
    }

    /// ↑↓ 选择，回车粘贴，⌘1–9 直接粘贴，⌘P 固定，⌘⌫ 删除；多选时回车合在一起粘贴、⌘C 合在一起复制、Esc 取消多选。
    /// 返回 true 表示已处理，不再交给搜索框。
    func handleKey(_ event: NSEvent) -> Bool {
        let command = event.modifierFlags.contains(.command)
        switch event.keyCode {
        case 53: // Esc
            guard !marked.isEmpty else { return false }
            marked = []
            return true
        case 125: // ↓
            move(1)
            return true
        case 126: // ↑
            move(-1)
            return true
        case 36, 76: // Return / Enter
            if !marked.isEmpty {
                onPasteText(mergedText)
            } else if let item = selectedItem {
                paste(item)
            }
            return true
        case 51, 117: // ⌫ / ⌦
            guard command else { return false }
            if let item = selectedItem {
                delete(item)
            }
            return true
        default:
            break
        }
        guard command, let characters = event.charactersIgnoringModifiers?.lowercased() else { return false }
        if characters == "c", !marked.isEmpty {
            service.copy(text: mergedText)
            marked = []
            return true
        }
        if characters == "p" {
            if let item = selectedItem {
                togglePin(item)
            }
            return true
        }
        if let digit = Int(characters), (1...9).contains(digit) {
            if items.indices.contains(digit - 1) {
                paste(items[digit - 1])
            }
            return true
        }
        return false
    }
}

struct ClipboardHistoryView: View {
    @ObservedObject var model: ClipboardHistoryModel
    var onClose: () -> Void
    @FocusState private var searchFocused: Bool
    @Namespace private var selectionSpace

    var body: some View {
        CardContainer(title: String(localized: "剪贴板历史"), subtitle: subtitle, width: 460, onClose: onClose) {
            if model.isEnabled {
                TextField("搜索", text: $model.query)
                    .textFieldStyle(.roundedBorder)
                    .focused($searchFocused)
                Picker("", selection: $model.filter) {
                    ForEach(ClipboardFilter.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                list
                Text(model.marked.isEmpty
                     ? String(localized: "⏎ 粘贴 · ⌘1–9 快速粘贴 · ⌘ 点选多条 · ⌘P 固定 · ⌘⌫ 删除 · 右键更多")
                     : String(localized: "已选 \(model.marked.count) 条 · ⏎ 按顺序合在一起粘贴 · ⌘C 合在一起复制 · Esc 取消"))
                    .font(.caption2)
                    .foregroundStyle(model.marked.isEmpty ? Color.secondary : Color.accentColor)
            } else {
                Text("剪贴板历史已关闭，打开后 Pop 会在本机记录你复制过的内容。")
                    .font(.callout)
                Button("去设置里打开", action: model.onOpenSettings)
                    .controlSize(.small)
            }
        }
        .task {
            searchFocused = true
        }
    }

    private var subtitle: String {
        model.items.isEmpty ? "" : String(localized: "\(model.items.count) 条")
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                        ClipboardRow(item: item, index: index, imageURL: model.service.store.imageURL(for: item),
                                     markNumber: model.markNumber(of: item), matchedText: model.matchedImageText(for: item))
                            .selectionHighlight(index == model.selection, in: selectionSpace)
                            .id(item.id)
                            .onTapGesture {
                                model.click(item)
                            }
                            .contextMenu {
                                Button("粘贴") { model.paste(item) }
                                Button("只复制") { model.service.copy(item) }
                                if item.kind == .text {
                                    Button(model.markNumber(of: item) == nil ? String(localized: "加入多选") : String(localized: "移出多选")) { model.toggleMark(item) }
                                }
                                Divider()
                                if item.kind == .text {
                                    Button("翻译") { model.onTranslate(item.text) }
                                    Button("存为常用短语") { model.onSaveSnippet(item) }
                                }
                                if item.kind == .image {
                                    Button("识别文字") { model.onRecognize(item) }
                                    Button("识别表格") { model.onRecognizeTable(item) }
                                    Button("标注…") { model.onAnnotate(item) }
                                }
                                if item.kind != .files {
                                    Button("贴到屏幕") { model.onPin(item) }
                                }
                                Divider()
                                Button(item.pinned ? String(localized: "取消固定") : String(localized: "固定")) { model.togglePin(item) }
                                Button("删除") { model.delete(item) }
                            }
                    }
                }
                .animation(Motion.selection, value: model.selection)
            }
            .frame(height: 340)
            .overlay {
                if model.items.isEmpty {
                    Text(model.query.isEmpty ? String(localized: "还没有记录，复制点什么试试") : String(localized: "没有匹配的记录"))
                        .foregroundStyle(.secondary)
                }
            }
            .onChange(of: model.selection) { _, selection in
                guard model.items.indices.contains(selection) else { return }
                proxy.scrollTo(model.items[selection].id)
            }
        }
    }
}

struct ClipboardRow: View {
    let item: ClipboardItem
    let index: Int
    let imageURL: URL?
    /// 多选时的顺序号
    var markNumber: Int? = nil
    /// 搜索时在图片里找到的那段文字
    var matchedText: String? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            if let markNumber {
                Text("\(markNumber)")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(Color.accentColor))
                    .transition(.scale.combined(with: .opacity))
            }
            preview
                .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 3) {
                HStack(spacing: 4) {
                    if item.pinned {
                        Image(systemName: "pin.fill")
                            .foregroundStyle(Color.orange)
                    }
                    if let icon = item.sourceApp.flatMap(AppIconCache.icon(for:)) {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 14, height: 14)
                    }
                }
                Text(item.usedAt.formatted(.relative(presentation: .named)))
                if index < 9 {
                    Text("⌘\(index + 1)")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .help(Self.tooltip(item))
    }

    /// 指针停在一条上时显示的完整内容（太长的截掉）
    static func tooltip(_ item: ClipboardItem) -> String {
        let text: String
        switch item.kind {
        case .text, .files:
            text = item.text
        case .image:
            text = item.recognizedText.map { $0.isEmpty ? "" : String(localized: "图片里的文字：\n") + $0 } ?? ""
        }
        return text.count > 1000 ? String(text.prefix(1000)) + "…" : text
    }

    @ViewBuilder
    private var preview: some View {
        switch item.kind {
        case .text:
            Text(Self.snippet(item.text))
                .font(.system(size: 12))
                .lineLimit(2)
        case .files:
            HStack(spacing: 6) {
                Image(systemName: item.fileURLs.count > 1 ? "doc.on.doc" : "doc")
                    .foregroundStyle(.secondary)
                Text(item.fileURLs.map(\.lastPathComponent).joinedAsList())
                    .font(.system(size: 12))
                    .lineLimit(2)
            }
        case .image:
            HStack(spacing: 8) {
                ClipboardThumbnail(url: imageURL)
                    .frame(width: 72, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("图片 · \(ByteCountFormatter.string(fromByteCount: Int64(item.byteSize), countStyle: .file))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let matchedText {
                        Text("图里有「\(matchedText)」")
                            .font(.caption)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    static func snippet(_ text: String) -> String {
        String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300))
    }
}

struct ClipboardThumbnail: View {
    let url: URL?
    @State private var image: CGImage? = nil

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 2)
                    .resizable()
                    .scaledToFit()
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.15))
            }
        }
        .task(id: url) {
            image = await Self.thumbnail(url)
        }
    }

    static func thumbnail(_ url: URL?) async -> CGImage? {
        guard let url else { return nil }
        return await runInBackground {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 176,
            ]
            return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        }
    }
}

/// App 图标查起来不算快，列表滚动时缓存一下。
@MainActor
enum AppIconCache {
    private static var icons: [String: NSImage] = [:]

    static func icon(for bundleID: String) -> NSImage? {
        if let cached = icons[bundleID] {
            return cached
        }
        guard let icon = AppInfo.icon(for: bundleID) else { return nil }
        icons[bundleID] = icon
        return icon
    }
}
