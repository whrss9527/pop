import AppKit
import SwiftUI

/// 「常用短语」列表：搜索（支持拼音首字母），↑↓ 选择，回车粘贴，⌘1–9 直接粘贴。
@MainActor
final class SnippetPickerModel: ObservableObject {
    private struct Entry {
        let snippet: Snippet
        let keys: [String]
    }

    private let entries: [Entry]
    @Published var query = "" {
        didSet { refilter() }
    }
    @Published private(set) var results: [Snippet]
    @Published var selection = 0
    var onPaste: (Snippet) -> Void = { _ in }
    var onOpenSettings: () -> Void = {}

    init(snippets: [Snippet]) {
        entries = snippets.map { Entry(snippet: $0, keys: SearchText.keys(for: $0.displayTitle) + [$0.text.lowercased()]) }
        results = snippets
    }

    var isEmpty: Bool { entries.isEmpty }

    private func refilter() {
        results = entries.filter { SearchText.matches(query, keys: $0.keys) }.map(\.snippet)
        selection = 0
    }

    func move(_ delta: Int) {
        guard !results.isEmpty else { return }
        selection = min(max(selection + delta, 0), results.count - 1)
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
                onPaste(results[selection])
            }
            return true
        default:
            break
        }
        if event.modifierFlags.contains(.command),
           let characters = event.charactersIgnoringModifiers, let digit = Int(characters), (1...9).contains(digit) {
            if results.indices.contains(digit - 1) {
                onPaste(results[digit - 1])
            }
            return true
        }
        return false
    }
}

struct SnippetPickerView: View {
    @ObservedObject var model: SnippetPickerModel
    var onClose: () -> Void
    @FocusState private var searchFocused: Bool
    @Namespace private var selectionSpace

    var body: some View {
        CardContainer(title: "常用短语", subtitle: "↑↓ 选择 · ⏎ 粘贴", onClose: onClose) {
            if model.isEmpty {
                Text("还没有常用短语。在「设置 → 剪贴板」里添加，写一次就能反复粘贴，还可以用 {date}、{clipboard} 这样的占位符。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("去添加", action: model.onOpenSettings)
                    .controlSize(.small)
            } else {
                TextField("搜索短语", text: $model.query)
                    .textFieldStyle(.roundedBorder)
                    .focused($searchFocused)
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(model.results.enumerated()), id: \.element.id) { index, snippet in
                                SnippetRow(snippet: snippet, index: index)
                                    .selectionHighlight(index == model.selection, in: selectionSpace)
                                    .id(snippet.id)
                                    .onTapGesture {
                                        model.onPaste(snippet)
                                    }
                            }
                        }
                        .animation(Motion.selection, value: model.selection)
                    }
                    .frame(height: min(CGFloat(max(model.results.count, 1)) * 46 + 8, 300))
                    .overlay {
                        if model.results.isEmpty {
                            Text("没有匹配的短语")
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
        .task {
            searchFocused = true
        }
    }
}

private struct SnippetRow: View {
    let snippet: Snippet
    let index: Int

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(snippet.displayTitle)
                    .lineLimit(1)
                Text(snippet.text.replacingOccurrences(of: "\n", with: " ⏎ "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
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
