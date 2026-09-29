import AppKit
import Combine
import ImageIO
import SwiftUI

@MainActor
final class ClipboardHistoryModel: ObservableObject {
    @Published var query = "" {
        didSet { reload() }
    }
    @Published private(set) var items: [ClipboardItem] = []
    @Published var selection = 0

    let service: ClipboardService
    var onPaste: (ClipboardItem) -> Void = { _ in }
    var onOpenSettings: () -> Void = {}

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
        items = service.items(matching: query)
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

    func togglePin(_ item: ClipboardItem) {
        service.setPinned(!item.pinned, item: item)
    }

    func delete(_ item: ClipboardItem) {
        service.delete(item)
    }

    /// ↑↓ 选择，回车粘贴，⌘1–9 直接粘贴，⌘P 固定，⌘⌫ 删除。返回 true 表示已处理，不再交给搜索框。
    func handleKey(_ event: NSEvent) -> Bool {
        let command = event.modifierFlags.contains(.command)
        switch event.keyCode {
        case 125: // ↓
            move(1)
            return true
        case 126: // ↑
            move(-1)
            return true
        case 36, 76: // Return / Enter
            if let item = selectedItem {
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
        CardContainer(title: "剪贴板历史", subtitle: subtitle, width: 460, onClose: onClose) {
            if model.isEnabled {
                TextField("搜索", text: $model.query)
                    .textFieldStyle(.roundedBorder)
                    .focused($searchFocused)
                list
                Text("⏎ 粘贴 · ⌘1–9 快速粘贴 · ⌘P 固定 · ⌘⌫ 删除 · 右键更多")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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
        model.items.isEmpty ? "" : "\(model.items.count) 条"
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                        ClipboardRow(item: item, index: index, imageURL: model.service.store.imageURL(for: item))
                            .selectionHighlight(index == model.selection, in: selectionSpace)
                            .id(item.id)
                            .onTapGesture {
                                model.paste(item)
                            }
                            .contextMenu {
                                Button("粘贴") { model.paste(item) }
                                Button("只复制") { model.service.copy(item) }
                                Button(item.pinned ? "取消固定" : "固定") { model.togglePin(item) }
                                Divider()
                                Button("删除") { model.delete(item) }
                            }
                    }
                }
                .animation(Motion.selection, value: model.selection)
            }
            .frame(height: 340)
            .overlay {
                if model.items.isEmpty {
                    Text(model.query.isEmpty ? "还没有记录，复制点什么试试" : "没有匹配的记录")
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

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
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
                Text(item.fileURLs.map(\.lastPathComponent).joined(separator: "、"))
                    .font(.system(size: 12))
                    .lineLimit(2)
            }
        case .image:
            HStack(spacing: 8) {
                ClipboardThumbnail(url: imageURL)
                    .frame(width: 72, height: 44)
                Text("图片 · \(ByteCountFormatter.string(fromByteCount: Int64(item.byteSize), countStyle: .file))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
