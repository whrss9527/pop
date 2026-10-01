import AppKit
import SwiftUI
@testable import Pop

/// 「表情和符号」卡片的状态：搜什么、看哪一类、选中了哪一个、肤色
@MainActor
final class EmojiSymbolsModel: ObservableObject {
    enum Section: String, CaseIterable, Identifiable {
        case recent, emoji, symbols

        var id: String { rawValue }

        var title: String {
            switch self {
            case .recent: return String(localized: "最近")
            case .emoji: return String(localized: "表情")
            case .symbols: return String(localized: "符号")
            }
        }
    }

    static let toneKey = "pop.emojiSymbols.tone"
    /// 一行几个
    static let columns = 10
    /// 肤色菜单里的样子：默认的黄色，再从浅到深
    static let toneSamples = ["✋", "✋🏻", "✋🏼", "✋🏽", "✋🏾", "✋🏿"]

    @Published var query: String {
        didSet { refresh() }
    }
    @Published var section: Section {
        didSet { refresh() }
    }
    @Published var emojiCategory = EmojiSymbols.Category.smileys {
        didSet { refresh() }
    }
    @Published var symbolCategory = EmojiSymbols.Category.math {
        didSet { refresh() }
    }
    @Published var tone: Int {
        didSet { defaults.set(tone, forKey: Self.toneKey) }
    }
    /// 现在列出来的
    @Published private(set) var visibleItems: [EmojiSymbols.Item] = []
    /// 方向键选中的（在 visibleItems 里的位置）
    @Published var selection = 0
    /// 指针停着的
    @Published var hovered: EmojiSymbols.Item?

    /// 插到原来的 App 里（替换选中的文字）
    var onInsert: (String) -> Void = { _ in }
    var onCopy: (String) -> Void = { _ in }

    private let defaults: UserDefaults
    private let recents: EmojiRecents

    /// 选中了一小段文字时拿它来搜（选中「猫」换成 🐱）
    init(query: String = "", defaults: UserDefaults = .standard) {
        self.defaults = defaults
        recents = EmojiRecents(defaults: defaults)
        self.query = query
        section = recents.ids.isEmpty ? .emoji : .recent
        tone = min(max(defaults.integer(forKey: Self.toneKey), 0), 5)
        refresh()
    }

    var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 底下写名字的那个：指针停着的，没有的话是方向键选中的
    var focused: EmojiSymbols.Item? {
        hovered ?? (visibleItems.indices.contains(selection) ? visibleItems[selection] : nil)
    }

    /// 列表空着时的说明
    var emptyText: String {
        if isSearching {
            return String(localized: "没有找到，换个说法试试：中文、拼音或者英文")
        }
        return String(localized: "还没用过。插入过的表情和符号会排在这里")
    }

    func text(for item: EmojiSymbols.Item) -> String {
        item.text(tone: tone)
    }

    func insert(_ item: EmojiSymbols.Item) {
        recents.record(item.id)
        onInsert(text(for: item))
    }

    func copy(_ item: EmojiSymbols.Item) {
        recents.record(item.id)
        onCopy(text(for: item))
    }

    /// 方向键挪选中的，回车插入，⌘C 复制
    func handleKey(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 123: // ←
            return move(-1)
        case 124: // →
            return move(1)
        case 125: // ↓
            return move(Self.columns)
        case 126: // ↑
            return move(-Self.columns)
        case 36, 76: // Return / Enter
            guard visibleItems.indices.contains(selection) else { return true }
            insert(visibleItems[selection])
            return true
        default:
            break
        }
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "c", visibleItems.indices.contains(selection) {
            copy(visibleItems[selection])
            return true
        }
        return false
    }

    /// 左右键在搜索框里有字时留给光标
    private func move(_ step: Int) -> Bool {
        if abs(step) == 1, isSearching {
            return false
        }
        guard !visibleItems.isEmpty else { return true }
        hovered = nil
        selection = min(max(selection + step, 0), visibleItems.count - 1)
        return true
    }

    private func refresh() {
        if isSearching {
            visibleItems = EmojiSymbols.search(query)
        } else {
            switch section {
            case .recent:
                visibleItems = recents.ids.compactMap { EmojiSymbols.item($0) }
            case .emoji:
                visibleItems = EmojiSymbols.items(in: emojiCategory)
            case .symbols:
                visibleItems = EmojiSymbols.items(in: symbolCategory)
            }
        }
        selection = 0
        hovered = nil
    }
}

struct EmojiSymbolsView: View {
    @ObservedObject var model: EmojiSymbolsModel
    var onClose: () -> Void
    @FocusState private var searchFocused: Bool

    private let cell: CGFloat = 38

    var body: some View {
        CardContainer(title: String(localized: "表情和符号"), width: 440, onClose: onClose) {
            HStack(spacing: 8) {
                TextField("搜表情和符号：笑、猫、对勾、箭头、smile", text: $model.query)
                    .textFieldStyle(.roundedBorder)
                    .focused($searchFocused)
                Menu {
                    ForEach(EmojiSymbolsModel.toneSamples.indices, id: \.self) { index in
                        Button(EmojiSymbolsModel.toneSamples[index]) { model.tone = index }
                    }
                } label: {
                    Text(EmojiSymbolsModel.toneSamples[model.tone])
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("肤色")
            }
            if !model.isSearching {
                Picker("分类", selection: $model.section) {
                    ForEach(EmojiSymbolsModel.Section.allCases) { section in
                        Text(section.title).tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                if model.section != .recent {
                    categoryBar
                }
            }
            grid
            footer
        }
        .controlSize(.small)
        .onAppear { searchFocused = true }
    }

    /// 一排分类：表情的画一个表情，符号的画一个符号
    private var categoryBar: some View {
        let categories = model.section == .emoji ? EmojiSymbols.Category.emojiCategories : EmojiSymbols.Category.symbolCategories
        let current = model.section == .emoji ? model.emojiCategory : model.symbolCategory
        return HStack(spacing: 2) {
            ForEach(categories) { category in
                Button {
                    if model.section == .emoji {
                        model.emojiCategory = category
                    } else {
                        model.symbolCategory = category
                    }
                } label: {
                    Text(category.icon)
                        .font(.system(size: category.isEmoji ? 16 : 14))
                        .frame(maxWidth: .infinity, minHeight: 26)
                        .background(RoundedRectangle(cornerRadius: 6)
                            .fill(category == current ? Color.accentColor.opacity(0.18) : Color.clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(category.title)
            }
        }
    }

    private var grid: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if model.visibleItems.isEmpty {
                    Text(model.emptyText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(cell), spacing: 2), count: EmojiSymbolsModel.columns), spacing: 2) {
                        ForEach(Array(model.visibleItems.enumerated()), id: \.element.id) { index, item in
                            ItemCell(text: model.text(for: item), isEmoji: item.isEmoji, isSelected: index == model.selection, size: cell)
                                .id(item.id)
                                .onTapGesture { model.insert(item) }
                                .onHover { inside in
                                    if inside {
                                        model.hovered = item
                                    } else if model.hovered == item {
                                        model.hovered = nil
                                    }
                                }
                                .contextMenu {
                                    Button("插入") { model.insert(item) }
                                    Button("复制") { model.copy(item) }
                                }
                                .help(item.name)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .frame(height: 4 * (cell + 2) + 40)
            .onChange(of: model.selection) { _, selection in
                guard model.visibleItems.indices.contains(selection) else { return }
                proxy.scrollTo(model.visibleItems[selection].id)
            }
        }
    }

    /// 底下：选中的放大一点，写着名字和编码；右边是怎么用
    private var footer: some View {
        HStack(spacing: 10) {
            if let item = model.focused {
                Text(model.text(for: item))
                    .font(.system(size: 26))
                    .frame(width: 40, height: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.name)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    Text(verbatim: "\(item.otherName) · \(item.codePoints)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 8)
            Text("回车插入 · ⌘C 复制")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(height: 36)
    }
}

/// 格子里的一个表情或者符号；方向键选中的带底色
private struct ItemCell: View {
    let text: String
    let isEmoji: Bool
    let isSelected: Bool
    let size: CGFloat
    @State private var hovering = false

    var body: some View {
        Text(text)
            .font(.system(size: isEmoji ? 24 : 19))
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: 7)
                .fill(isSelected ? Color.accentColor.opacity(0.22) : Color.primary.opacity(hovering ? 0.08 : 0)))
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
    }
}
