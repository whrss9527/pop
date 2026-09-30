import Foundation
import UniformTypeIdentifiers

/// 生词本里的一个词
struct VocabularyEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    var word: String
    var translation: String
    /// 原文和译文的语言（en、zh-Hans 这样的写法）
    var sourceLanguage: String?
    var targetLanguage: String?
    var added: Date
    /// 复习时点过几次「还不熟」
    var misses = 0
    /// 复习时点了「记住了」
    var mastered = false

    init(word: String, translation: String, sourceLanguage: String?, targetLanguage: String?, added: Date) {
        self.word = word
        self.translation = translation
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.added = added
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.lenient(.id, default: UUID())
        word = c.lenient(.word, default: "")
        translation = c.lenient(.translation, default: "")
        sourceLanguage = c.lenient(.sourceLanguage, default: nil)
        targetLanguage = c.lenient(.targetLanguage, default: nil)
        added = c.lenient(.added, default: Date(timeIntervalSince1970: 0))
        misses = c.lenient(.misses, default: 0)
        mastered = c.lenient(.mastered, default: false)
    }
}

/// 生词本：翻译卡片上点「加入生词本」存进来，可以搜索、复习、导出。
/// 存在「~/Library/Application Support/Pop/Vocabulary.json」，最新加的在最前面。
@MainActor
final class VocabularyStore: ObservableObject {
    static let shared = VocabularyStore()

    @Published private(set) var entries: [VocabularyEntry] = []
    let url: URL

    enum ExportFormat: String, CaseIterable, Identifiable {
        case csv
        case anki

        var id: String { rawValue }

        var title: String {
            switch self {
            case .csv: return String(localized: "CSV（表格软件）")
            case .anki: return String(localized: "制表符分隔（Anki 导入）")
            }
        }

        var fileExtension: String { self == .csv ? "csv" : "txt" }
        var contentType: UTType { self == .csv ? .commaSeparatedText : .plainText }
    }

    init(url: URL = VocabularyStore.defaultURL) {
        self.url = url
        load()
    }

    nonisolated static var defaultURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return support.appending(path: "Pop", directoryHint: .isDirectory).appending(path: "Vocabulary.json")
    }

    /// 适合加进生词本的：一个词或者一个短语（不超过 6 个词、60 个字，没有换行）
    nonisolated static func isWordLike(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= 60 && !trimmed.contains(where: \.isNewline)
            && trimmed.split(whereSeparator: \.isWhitespace).count <= 6
    }

    /// 同一个词不分大小写只存一次
    nonisolated static func key(_ word: String) -> String {
        word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    func contains(_ word: String) -> Bool {
        let key = Self.key(word)
        return entries.contains { Self.key($0.word) == key }
    }

    /// 加一个词；已经有了就换成新的释义、挪到最前面、重新算没记住。返回是不是新加的
    @discardableResult
    func add(word: String, translation: String, sourceLanguage: String?, targetLanguage: String?, date: Date = Date()) -> Bool {
        let trimmedWord = word.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTranslation = translation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedWord.isEmpty else { return false }
        let key = Self.key(trimmedWord)
        var isNew = true
        var entry = VocabularyEntry(word: trimmedWord, translation: trimmedTranslation, sourceLanguage: sourceLanguage,
                                    targetLanguage: targetLanguage, added: date)
        if let index = entries.firstIndex(where: { Self.key($0.word) == key }) {
            let existing = entries.remove(at: index)
            entry.id = existing.id
            entry.added = existing.added
            entry.misses = existing.misses
            isNew = false
        }
        entries.insert(entry, at: 0)
        save()
        return isNew
    }

    func remove(_ ids: Set<UUID>) {
        entries.removeAll { ids.contains($0.id) }
        save()
    }

    func setMastered(_ id: UUID, _ mastered: Bool) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].mastered = mastered
        save()
    }

    /// 复习时点了「记住了」或者「还不熟」
    func review(_ id: UUID, remembered: Bool) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        if remembered {
            entries[index].mastered = true
        } else {
            entries[index].misses += 1
        }
        save()
    }

    /// 还没记住的词，按「还不熟」的次数从多到少、加入时间从早到晚排好，复习时一个个来
    var reviewQueue: [VocabularyEntry] {
        entries.filter { !$0.mastered }.sorted {
            $0.misses != $1.misses ? $0.misses > $1.misses : $0.added < $1.added
        }
    }

    /// 导出成文字：CSV 带表头，字段里有逗号、引号、换行时加引号；Anki 格式每行「词<Tab>释义」
    nonisolated static func export(_ entries: [VocabularyEntry], as format: ExportFormat) -> String {
        switch format {
        case .csv:
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withFullDate]
            let header = String(localized: "单词,释义,语言,加入日期,已记住")
            let lines = entries.map { entry in
                [entry.word, entry.translation, entry.sourceLanguage ?? "", formatter.string(from: entry.added),
                 entry.mastered ? String(localized: "是") : String(localized: "否")].map(csvField).joined(separator: ",")
            }
            return ([header] + lines).joined(separator: "\n") + "\n"
        case .anki:
            return entries.map { entry in
                [entry.word, entry.translation].map { $0.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: "<br>") }
                    .joined(separator: "\t")
            }.joined(separator: "\n") + "\n"
        }
    }

    private nonisolated static func csvField(_ text: String) -> String {
        guard text.contains(where: { $0 == "," || $0 == "\"" || $0.isNewline }) else { return text }
        return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private func load() {
        guard let data = try? Data(contentsOf: url) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        entries = ((try? decoder.decode([VocabularyEntry].self, from: data)) ?? []).filter { !$0.word.isEmpty }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(entries) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
