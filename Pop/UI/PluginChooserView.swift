import AppKit
import SwiftUI

/// 「全部功能」列表：列出能处理当前内容的所有功能，可以搜索（支持拼音首字母）。
/// 搜索时也列出没装的插件包，点一下装上，装好就用。
@MainActor
final class PluginChooserModel: ObservableObject {
    private struct Entry {
        let info: PluginInfo
        let keys: [String]
    }

    private struct PackageEntry {
        let package: PluginPackage
        let keys: [String]
    }

    private let entries: [Entry]
    private let packageEntries: [PackageEntry]
    @Published var query = "" {
        didSet { refilter() }
    }
    @Published private(set) var results: [PluginInfo]
    /// 和搜索的字对得上、还没装的插件包（排在已装的功能后面）
    @Published private(set) var packages: [PluginPackage] = []
    /// 选中的行：先是已装的功能，接着是没装的插件包
    @Published var selection = 0
    var onRun: (PluginInfo) -> Void = { _ in }
    var onInstall: (PluginPackage) -> Void = { _ in }
    /// 最近用过的功能（排在列表前面，行上带一个小钟）
    let recent: Set<String>
    /// 插件包的安装状态、下载大小从这里读
    let manager: PluginManager?
    private var managerChanges: AnyCancellable?

    init(plugins: [PluginInfo], recent: Set<String> = [], packages: [PluginPackage] = [], manager: PluginManager? = nil) {
        entries = plugins.map { Entry(info: $0, keys: SearchText.keys(for: $0.name) + [$0.summary.lowercased()]) }
        // 插件包的 ID 和功能 ID 也能搜（zip、jwt 这样的）
        packageEntries = packages.map { package in
            PackageEntry(package: package, keys: SearchText.keys(for: package.name) + [package.summary.lowercased(), package.id.lowercased()]
                + package.functions.map { $0.lowercased() })
        }
        results = plugins
        self.recent = recent
        self.manager = manager
        // 正在下载、装好了、装失败了：列表跟着变
        managerChanges = manager?.objectWillChange.sink { [weak self] _ in
            MainActor.assumeIsolated {
                self?.objectWillChange.send()
            }
        }
    }

    private func refilter() {
        results = entries.filter { SearchText.matches(query, keys: $0.keys) }.map(\.info)
        // 没装的只在搜索时列出来，不然列表太长
        let searching = !query.allSatisfy(\.isWhitespace)
        packages = searching ? packageEntries.filter { SearchText.matches(query, keys: $0.keys) }.map(\.package) : []
        selection = 0
    }

    private var rowCount: Int {
        results.count + packages.count
    }

    func move(_ delta: Int) {
        guard rowCount > 0 else { return }
        selection = min(max(selection + delta, 0), rowCount - 1)
    }

    /// 已装的功能直接用，没装的插件包先装上
    func activate(_ index: Int) {
        if results.indices.contains(index) {
            onRun(results[index])
        } else if packages.indices.contains(index - results.count) {
            onInstall(packages[index - results.count])
        }
    }

    /// 选中那一行在列表里的 ID（滚动到它用）
    var selectedRowID: String? {
        if results.indices.contains(selection) {
            return results[selection].id
        }
        guard packages.indices.contains(selection - results.count) else { return nil }
        return Self.rowID(packages[selection - results.count])
    }

    static func rowID(_ package: PluginPackage) -> String {
        "package-\(package.id)"
    }

    func status(of package: PluginPackage) -> PluginManager.Status {
        manager?.status(of: package) ?? .notInstalled
    }

    func downloadSize(of package: PluginPackage) -> Int64? {
        manager?.index?.entry(id: package.id)?.size
    }

    /// ↑↓ 选择，回车执行，⌘1–9 直接执行。返回 true 表示已处理。
    func handleKey(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 125:
            move(1)
            return true
        case 126:
            move(-1)
            return true
        case 36, 76:
            activate(selection)
            return true
        default:
            break
        }
        if event.modifierFlags.contains(.command),
           let characters = event.charactersIgnoringModifiers, let digit = Int(characters), (1...9).contains(digit) {
            if results.indices.contains(digit - 1) {
                onRun(results[digit - 1])
            }
            return true
        }
        return false
    }
}

struct PluginChooserView: View {
    @ObservedObject var model: PluginChooserModel
    var onClose: () -> Void
    @FocusState private var searchFocused: Bool
    @Namespace private var selectionSpace

    var body: some View {
        CardContainer(title: String(localized: "全部功能"), subtitle: String(localized: "↑↓ 选择 · ⏎ 执行"), onClose: onClose) {
            TextField("搜索功能，比如 fy 找到翻译", text: $model.query)
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(model.results.enumerated()), id: \.element.id) { index, info in
                            PluginChooserRow(info: info, index: index, isRecent: model.recent.contains(info.id))
                                .selectionHighlight(index == model.selection, in: selectionSpace)
                                .id(info.id)
                                .onTapGesture {
                                    model.onRun(info)
                                }
                        }
                        if !model.packages.isEmpty {
                            Text("没装的插件 · 点一下装上就能用")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 8)
                                .padding(.top, model.results.isEmpty ? 0 : 8)
                                .padding(.bottom, 2)
                            ForEach(Array(model.packages.enumerated()), id: \.element.id) { offset, package in
                                let index = model.results.count + offset
                                PluginPackageChooserRow(package: package, status: model.status(of: package),
                                                        downloadSize: model.downloadSize(of: package))
                                    .selectionHighlight(index == model.selection, in: selectionSpace)
                                    .id(PluginChooserModel.rowID(package))
                                    .onTapGesture {
                                        model.activate(index)
                                    }
                            }
                        }
                    }
                    .animation(Motion.selection, value: model.selection)
                }
                .frame(height: 300)
                .overlay {
                    if model.results.isEmpty && model.packages.isEmpty {
                        Text("没有匹配的功能")
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: model.selection) { _, _ in
                    guard let id = model.selectedRowID else { return }
                    proxy.scrollTo(id)
                }
            }
        }
        .task {
            searchFocused = true
        }
    }
}

struct PluginChooserRow: View {
    let info: PluginInfo
    let index: Int
    var isRecent = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: info.symbol)
                .font(.system(size: 15))
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(info.name)
                Text(info.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if isRecent {
                Image(systemName: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help("最近用过")
            }
            if info.source == .user {
                Text("插件")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if index < 9 {
                Text("⌘\(index + 1)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// 「全部功能」里没装的插件包：写着装上要下载多大；正在下载、装失败也显示在这一行
struct PluginPackageChooserRow: View {
    let package: PluginPackage
    let status: PluginManager.Status
    let downloadSize: Int64?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: package.symbol)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(package.name)
                    .foregroundStyle(.secondary)
                if case .failed(let message) = status {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                        .help(message)
                } else {
                    Text(package.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            trailing
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var trailing: some View {
        switch status {
        case .installing:
            ProgressView()
                .controlSize(.small)
        case .installed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            badge(String(localized: "重试"))
        case .notInstalled:
            badge(downloadSize.map { String(localized: "安装 · \(ByteCountFormatter.string(fromByteCount: $0, countStyle: .file))") }
                  ?? String(localized: "安装"))
        }
    }

    private func badge(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.accentColor.opacity(0.14)))
    }
}
