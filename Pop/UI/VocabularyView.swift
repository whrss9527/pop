import SwiftUI

/// 生词本卡片的状态：搜索，或者一个个复习还没记住的词。
@MainActor
final class VocabularyModel: ObservableObject {
    let store: VocabularyStore
    @Published var query = ""
    /// 正在复习的词；nil 表示在看列表
    @Published private(set) var reviewing: VocabularyEntry?
    /// 复习时已经翻过来看释义了
    @Published var revealed = false
    /// 这一轮复习还没看过的词
    private var queue: [VocabularyEntry] = []

    init(store: VocabularyStore) {
        self.store = store
    }

    var visible: [VocabularyEntry] {
        let query = self.query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return store.entries }
        return store.entries.filter {
            $0.word.localizedCaseInsensitiveContains(query) || $0.translation.localizedCaseInsensitiveContains(query)
        }
    }

    var remaining: Int { queue.count + (reviewing == nil ? 0 : 1) }

    func startReview() {
        queue = store.reviewQueue
        showNext()
    }

    /// 记住了：以后不再复习；还不熟：这一轮最后再来一次
    func answer(remembered: Bool) {
        guard let current = reviewing else { return }
        store.review(current.id, remembered: remembered)
        if !remembered, let updated = store.entries.first(where: { $0.id == current.id }) {
            queue.append(updated)
        }
        showNext()
    }

    func stopReview() {
        queue = []
        reviewing = nil
        revealed = false
    }

    private func showNext() {
        revealed = false
        reviewing = queue.isEmpty ? nil : queue.removeFirst()
    }
}

struct VocabularyView: View {
    @ObservedObject var model: VocabularyModel
    @ObservedObject var store: VocabularyStore
    var onCopy: (String) -> Void
    var onSpeak: (VocabularyEntry) -> Void
    var onExport: (VocabularyStore.ExportFormat) -> Void
    var onClose: () -> Void

    init(model: VocabularyModel, onCopy: @escaping (String) -> Void, onSpeak: @escaping (VocabularyEntry) -> Void,
         onExport: @escaping (VocabularyStore.ExportFormat) -> Void, onClose: @escaping () -> Void) {
        self.model = model
        store = model.store
        self.onCopy = onCopy
        self.onSpeak = onSpeak
        self.onExport = onExport
        self.onClose = onClose
    }

    private var subtitle: String {
        let learning = store.entries.filter { !$0.mastered }.count
        return store.entries.isEmpty ? "" : "\(store.entries.count) 个，\(learning) 个还没记住"
    }

    var body: some View {
        CardContainer(title: "生词本", subtitle: subtitle, width: 440, onClose: onClose) {
            if let entry = model.reviewing {
                review(entry)
            } else {
                list
            }
        }
    }

    @ViewBuilder
    private var list: some View {
        HStack(spacing: 8) {
            TextField("搜索单词或释义", text: $model.query)
                .textFieldStyle(.roundedBorder)
            Button("复习") { model.startReview() }
                .disabled(store.reviewQueue.isEmpty)
                .help("一个个看还没记住的词，想一想再看释义")
            Menu("导出") {
                ForEach(VocabularyStore.ExportFormat.allCases) { format in
                    Button(format.title) { onExport(format) }
                }
            }
            .fixedSize()
            .disabled(store.entries.isEmpty)
        }
        .controlSize(.small)

        if store.entries.isEmpty {
            Text("还没有生词。翻译卡片上点「加入生词本」，单词和释义就会存到这里。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            let entries = model.visible
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(entries) { entry in
                        row(entry)
                    }
                }
                .padding(.trailing, 6)
            }
            .frame(height: min(CGFloat(max(entries.count, 1)) * 42, 300))
        }
    }

    private func row(_ entry: VocabularyEntry) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.word)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text(entry.translation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if entry.mastered {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                    .help("已经记住了")
            }
            Button {
                onSpeak(entry)
            } label: {
                Image(systemName: "speaker.wave.2")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("朗读")
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .help("\(entry.word)：\(entry.translation)")
        .contextMenu {
            Button("复制单词") { onCopy(entry.word) }
            Button("复制单词和释义") { onCopy("\(entry.word)\t\(entry.translation)") }
            Button(entry.mastered ? "标记为还没记住" : "标记为已经记住") { store.setMastered(entry.id, !entry.mastered) }
            Divider()
            Button("删除") { store.remove([entry.id]) }
        }
    }

    @ViewBuilder
    private func review(_ entry: VocabularyEntry) -> some View {
        VStack(spacing: 10) {
            Text(entry.word)
                .font(.system(size: 22, weight: .semibold))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            if model.revealed {
                Text(entry.translation)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .transition(.opacity)
            } else {
                Button("看释义") { model.revealed = true }
                    .keyboardShortcut(.space, modifiers: [])
            }
        }
        .padding(.vertical, 8)
        .animation(Motion.content, value: model.revealed)

        HStack(spacing: 8) {
            Button { onSpeak(entry) } label: {
                Image(systemName: "speaker.wave.2")
            }
            .help("朗读")
            Text("还剩 \(model.remaining) 个")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("还不熟") { model.answer(remembered: false) }
            Button("记住了") { model.answer(remembered: true) }
                .keyboardShortcut(.defaultAction)
            Button("结束") { model.stopReview() }
        }
        .controlSize(.small)
    }
}
