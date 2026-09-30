import SwiftUI

/// 「设置 → 剪贴板」里的常用短语：添加、编辑、调整顺序、删除。
struct SnippetsSection: View {
    @EnvironmentObject private var store: SettingsStore
    @State private var editing: Snippet? = nil

    var body: some View {
        Section {
            let snippets = store.settings.snippets
            if snippets.isEmpty {
                Text("还没有短语。")
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(snippets.enumerated()), id: \.element.id) { index, snippet in
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(snippet.displayTitle)
                            .lineLimit(1)
                        Text(snippet.text.replacingOccurrences(of: "\n", with: " ⏎ "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button {
                        move(from: index, by: -1)
                    } label: {
                        Image(systemName: "chevron.up")
                    }
                    .buttonStyle(.borderless)
                    .disabled(index == 0)
                    .help("上移")
                    Button {
                        move(from: index, by: 1)
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .buttonStyle(.borderless)
                    .disabled(index == snippets.count - 1)
                    .help("下移")
                    Button("编辑") { editing = snippet }
                        .controlSize(.small)
                    Button {
                        store.update { $0.snippets.removeAll { $0.id == snippet.id } }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("删除")
                }
            }
            Button("添加短语…") {
                editing = Snippet(title: "", text: "")
            }
        } header: {
            Text("常用短语")
        } footer: {
            Text("在圆盘的「常用短语」里选一条就粘贴到当前 App，排在前面的可以用 ⌘1–9 直接粘贴；也可以在「快捷键」里给它设一个快捷键。粘贴完剪贴板会恢复原样。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .sheet(item: $editing) { snippet in
            SnippetEditor(snippet: snippet) { saved in
                store.update { settings in
                    if let index = settings.snippets.firstIndex(where: { $0.id == saved.id }) {
                        settings.snippets[index] = saved
                    } else {
                        settings.snippets.append(saved)
                    }
                }
                editing = nil
            } onCancel: {
                editing = nil
            }
        }
    }

    private func move(from index: Int, by delta: Int) {
        store.update { settings in
            let target = index + delta
            guard settings.snippets.indices.contains(index), settings.snippets.indices.contains(target) else { return }
            settings.snippets.swapAt(index, target)
        }
    }
}

private struct SnippetEditor: View {
    @State var snippet: Snippet
    let onSave: (Snippet) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(snippet.text.isEmpty && snippet.title.isEmpty ? String(localized: "添加短语") : String(localized: "编辑短语"))
                .font(.headline)
            TextField("标题（可选）", text: $snippet.title)
            TextEditor(text: $snippet.text)
                .font(.body)
                .frame(height: 140)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.secondary.opacity(0.3)))
            VStack(alignment: .leading, spacing: 3) {
                Text("可以用的占位符（粘贴时换成当时的内容）：")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(SnippetExpander.placeholders) { placeholder in
                    HStack(spacing: 6) {
                        Button(placeholder.token) {
                            snippet.text += placeholder.token
                        }
                        .buttonStyle(.link)
                        .font(.system(.caption, design: .monospaced))
                        Text(placeholder.meaning)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            HStack {
                Spacer()
                Button("取消", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("保存") { onSave(snippet) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(snippet.text.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}
