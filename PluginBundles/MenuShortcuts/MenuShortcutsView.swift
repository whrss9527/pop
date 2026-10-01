import AppKit
import SwiftUI
@testable import Pop

/// 「快捷键一览」列表：搜索（支持拼音首字母），只看有快捷键的或者全部菜单项，↑↓ 选择，回车执行，⇥ 切换。
@MainActor
final class MenuShortcutsModel: ObservableObject {
    enum Scope: Hashable {
        case shortcuts
        case all
    }

    private struct Entry {
        let item: MenuShortcuts.Item
        let keys: [String]
    }

    let appName: String
    @Published private(set) var isLoading = true
    @Published private(set) var failure: String?
    @Published var query = "" {
        didSet { refilter() }
    }
    @Published var scope = Scope.shortcuts {
        didSet { refilter() }
    }
    @Published private(set) var results: [MenuShortcuts.Item] = []
    @Published var selection = 0
    @Published private(set) var shortcutCount = 0
    @Published private(set) var totalCount = 0
    private var entries: [Entry] = []
    var onRun: (MenuShortcuts.Item) -> Void = { _ in }

    init(appName: String) {
        self.appName = appName
    }

    /// 读到了菜单：一个快捷键都没有的 App 直接列出全部菜单项
    func load(_ nodes: [MenuShortcuts.Node]) {
        let items = MenuShortcuts.flatten(nodes)
        entries = items.map { Entry(item: $0, keys: MenuShortcuts.searchKeys(for: $0)) }
        totalCount = items.count
        shortcutCount = items.filter { $0.shortcut != nil }.count
        isLoading = false
        if items.isEmpty {
            failure = String(localized: "没读到「\(appName)」的菜单")
        }
        if shortcutCount == 0 {
            scope = .all
        }
        refilter()
    }

    func fail(_ message: String) {
        isLoading = false
        failure = message
    }

    private func refilter() {
        let onlyShortcuts = scope == .shortcuts
        results = entries.filter { entry in
            (!onlyShortcuts || entry.item.shortcut != nil) && SearchText.matches(query, keys: entry.keys)
        }.map(\.item)
        selection = 0
    }

    func move(_ delta: Int) {
        guard !results.isEmpty else { return }
        selection = min(max(selection + delta, 0), results.count - 1)
    }

    /// 执行一项；现在用不了（菜单里是灰的）的不执行
    func run(_ item: MenuShortcuts.Item) {
        guard item.enabled else { return }
        onRun(item)
    }

    func handleKey(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 125: // ↓
            move(1)
            return true
        case 126: // ↑
            move(-1)
            return true
        case 36, 76: // Return / Enter
            if results.indices.contains(selection) {
                run(results[selection])
            }
            return true
        case 48: // Tab
            scope = scope == .shortcuts ? .all : .shortcuts
            return true
        default:
            return false
        }
    }
}

struct MenuShortcutsView: View {
    @ObservedObject var model: MenuShortcutsModel
    var onClose: () -> Void
    @FocusState private var searchFocused: Bool
    @Namespace private var selectionSpace

    var body: some View {
        CardContainer(title: String(localized: "快捷键一览"), subtitle: model.appName, width: 420, onClose: onClose) {
            if model.isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在读「\(model.appName)」的菜单…")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 60)
            } else if let failure = model.failure {
                Text(failure)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(spacing: 8) {
                    TextField("搜索菜单和快捷键", text: $model.query)
                        .textFieldStyle(.roundedBorder)
                        .focused($searchFocused)
                    Picker("", selection: $model.scope) {
                        Text("有快捷键（\(model.shortcutCount)）").tag(MenuShortcutsModel.Scope.shortcuts)
                        Text("全部（\(model.totalCount)）").tag(MenuShortcutsModel.Scope.all)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                list
                Text("↑↓ 选择 · ⏎ 执行 · ⇥ 切换")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .task {
            searchFocused = true
        }
        .onChange(of: model.isLoading) { _, _ in
            searchFocused = true
        }
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(model.results.enumerated()), id: \.element.id) { index, item in
                        if index == 0 || model.results[index - 1].path.first != item.path.first {
                            Text(item.path.first ?? "")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.top, index == 0 ? 2 : 8)
                        }
                        MenuShortcutRow(item: item)
                            .selectionHighlight(index == model.selection, in: selectionSpace)
                            .id(item.id)
                            .onTapGesture {
                                model.run(item)
                            }
                    }
                }
                .animation(Motion.selection, value: model.selection)
            }
            .frame(height: 320)
            .overlay {
                if model.results.isEmpty {
                    Text(model.query.isEmpty ? String(localized: "这个 App 的菜单里没有快捷键") : String(localized: "没有匹配的菜单项"))
                        .foregroundStyle(.secondary)
                }
            }
            .onChange(of: model.selection) { _, selection in
                guard model.results.indices.contains(selection) else { return }
                proxy.scrollTo(model.results[selection].id)
            }
        }
    }
}

private struct MenuShortcutRow: View {
    let item: MenuShortcuts.Item

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .lineLimit(1)
                // 子菜单里的项：写上在哪个子菜单
                if item.path.count > 2 {
                    Text(item.path.dropFirst().dropLast().joined(separator: " › "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let shortcut = item.shortcut {
                Text(shortcut)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.primary.opacity(0.08)))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .opacity(item.enabled ? 1 : 0.45)
        .help(item.enabled ? item.path.joined(separator: " › ") : String(localized: "现在用不了"))
    }
}
