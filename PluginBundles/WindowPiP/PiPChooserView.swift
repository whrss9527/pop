import AppKit
import ScreenCaptureKit
import SwiftUI
@testable import Pop

/// 选窗口的卡片：屏幕上能放进小窗的窗口，指针下的那个排第一个、先选中；缩略图拍好一个显示一个
@MainActor
final class PiPChooserModel: ObservableObject {
    static let columns = 2

    let items: [PiPWindows.Item]
    @Published var selection: CGWindowID?
    @Published private(set) var thumbnails: [CGWindowID: CGImage] = [:]
    /// 已经开着几个小窗
    let openCount: Int
    /// 已经在小窗里的窗口
    let showing: Set<CGWindowID>
    var onChoose: (PiPWindows.Item) -> Void = { _ in }
    var onCloseAll: () -> Void = {}
    private let icon: (pid_t) -> NSImage?

    init(items: [PiPWindows.Item], under: CGWindowID?, openCount: Int = 0, showing: Set<CGWindowID> = [],
         thumbnails: [CGWindowID: CGImage] = [:], icon: @escaping (pid_t) -> NSImage? = { NSRunningApplication(processIdentifier: $0)?.icon }) {
        var ordered = items
        if let under, let index = ordered.firstIndex(where: { $0.id == under }) {
            ordered.insert(ordered.remove(at: index), at: 0)
        }
        self.items = ordered
        selection = ordered.first?.id
        self.openCount = openCount
        self.showing = showing
        self.thumbnails = thumbnails
        self.icon = icon
    }

    var selectedItem: PiPWindows.Item? {
        items.first { $0.id == selection }
    }

    func icon(for item: PiPWindows.Item) -> NSImage? {
        icon(item.pid)
    }

    /// 方向键：左右换一个，上下换一行；到头了停住
    func move(_ offset: Int) {
        guard !items.isEmpty else { return }
        let current = items.firstIndex { $0.id == selection } ?? 0
        selection = items[min(max(current + offset, 0), items.count - 1)].id
    }

    func choose(_ item: PiPWindows.Item? = nil) {
        guard let item = item ?? selectedItem else { return }
        selection = item.id
        onChoose(item)
    }

    func closeAll() {
        onCloseAll()
    }

    func setThumbnail(_ image: CGImage, for id: CGWindowID) {
        thumbnails[id] = image
    }

    /// 方向键换窗口，回车放进小窗
    func handleKey(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 123:
            move(-1)
        case 124:
            move(1)
        case 125:
            move(Self.columns)
        case 126:
            move(-Self.columns)
        case 36, 76:
            choose()
        default:
            return false
        }
        return true
    }

    /// 按顺序一个个拍缩略图，拍好一个显示一个
    func loadThumbnails(_ windows: [CGWindowID: SCWindow]) {
        let items = items
        Task { [weak self] in
            for item in items {
                // 卡片关掉了（或者已经选好了窗口）就不拍了
                guard self != nil, !Task.isCancelled else { return }
                guard let window = windows[item.id], let image = await PiPCapture.thumbnail(of: window) else { continue }
                self?.setThumbnail(image, for: item.id)
            }
        }
    }
}

struct PiPChooserView: View {
    @ObservedObject var model: PiPChooserModel
    var onClose: () -> Void

    var body: some View {
        CardContainer(title: String(localized: "窗口画中画"), width: 440, onClose: onClose) {
            Text("选一个窗口，它的画面会一直浮在屏幕角落；双击小窗回到原来的窗口")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: PiPChooserModel.columns), spacing: 8) {
                        ForEach(model.items) { item in
                            PiPTile(item: item, thumbnail: model.thumbnails[item.id], icon: model.icon(for: item),
                                    isSelected: item.id == model.selection, isShowing: model.showing.contains(item.id)) {
                                model.choose(item)
                            }
                            .id(item.id)
                        }
                    }
                    .padding(2)
                }
                .frame(height: gridHeight)
                .onChange(of: model.selection) { _, id in
                    if let id {
                        proxy.scrollTo(id)
                    }
                }
            }
            HStack(spacing: 8) {
                if model.openCount > 0 {
                    Text("已经开着 \(model.openCount) 个小窗")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("全部关掉", action: model.closeAll)
                }
                Spacer()
                Button("放进小窗") { model.choose() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.selection == nil)
            }
        }
        .controlSize(.small)
    }

    /// 最多露出三行，再多就滚动
    private var gridHeight: CGFloat {
        let rows = (model.items.count + PiPChooserModel.columns - 1) / PiPChooserModel.columns
        return CGFloat(min(max(rows, 1), 3)) * (PiPTile.height + 8) - 8 + 4
    }
}

/// 一个窗口：缩略图（还没拍好时是 App 的图标），下面是 App 图标和窗口名字
private struct PiPTile: View {
    static let height: CGFloat = 124

    let item: PiPWindows.Item
    let thumbnail: CGImage?
    let icon: NSImage?
    let isSelected: Bool
    let isShowing: Bool
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                    Group {
                        if let thumbnail {
                            Image(decorative: thumbnail, scale: 2)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                                .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                                .padding(6)
                        } else if let icon {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 36, height: 36)
                                .opacity(0.8)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if isShowing {
                        Label("已在小窗里", systemImage: "pip")
                            .labelStyle(.iconOnly)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(4)
                            .background(Circle().fill(Color.accentColor))
                            .padding(4)
                            .help("已在小窗里")
                    }
                }
                .frame(height: Self.height - 31)
                HStack(spacing: 5) {
                    if let icon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 14, height: 14)
                    }
                    Text(verbatim: item.displayTitle)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(height: 16)
            }
            .padding(5)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(hovering ? 0.05 : 0)))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.65) : Color.clear, lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(item.displayTitle)
    }
}
