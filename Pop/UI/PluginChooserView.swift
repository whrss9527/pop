import AppKit
import SwiftUI

/// 「全部功能」列表：列出能处理当前内容的所有功能，可以搜索（支持拼音首字母）。
@MainActor
final class PluginChooserModel: ObservableObject {
    private struct Entry {
        let info: PluginInfo
        let keys: [String]
    }

    private let entries: [Entry]
    @Published var query = "" {
        didSet { refilter() }
    }
    @Published private(set) var results: [PluginInfo]
    @Published var selection = 0
    var onRun: (PluginInfo) -> Void = { _ in }
    /// 最近用过的功能（排在列表前面，行上带一个小钟）
    let recent: Set<String>

    init(plugins: [PluginInfo], recent: Set<String> = []) {
        entries = plugins.map { Entry(info: $0, keys: SearchText.keys(for: $0.name) + [$0.summary.lowercased()]) }
        results = plugins
        self.recent = recent
    }

    private func refilter() {
        results = entries.filter { SearchText.matches(query, keys: $0.keys) }.map(\.info)
        selection = 0
    }

    func move(_ delta: Int) {
        guard !results.isEmpty else { return }
        selection = min(max(selection + delta, 0), results.count - 1)
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
            if results.indices.contains(selection) {
                onRun(results[selection])
            }
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
        CardContainer(title: "全部功能", subtitle: "↑↓ 选择 · ⏎ 执行", onClose: onClose) {
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
                    }
                    .animation(Motion.selection, value: model.selection)
                }
                .frame(height: 300)
                .overlay {
                    if model.results.isEmpty {
                        Text("没有匹配的功能")
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: model.selection) { _, selection in
                    guard model.results.indices.contains(selection) else { return }
                    proxy.scrollTo(model.results[selection].id)
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
