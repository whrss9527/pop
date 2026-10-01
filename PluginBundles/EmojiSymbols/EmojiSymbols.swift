import Foundation
@testable import Pop

/// 表情和常用特殊符号：分类、按中文、拼音、英文搜、肤色。纯逻辑，方便测试
enum EmojiSymbols {
    enum Category: String, CaseIterable, Identifiable {
        case smileys, people, nature, food, travel, activities, objects, symbols, flags
        case math, arrows, numbers, punctuation, units, shapes, greek, scripts, keyboard

        var id: String { rawValue }

        static let emojiCategories: [Category] = [.smileys, .people, .nature, .food, .travel, .activities, .objects, .symbols, .flags]
        static let symbolCategories: [Category] = [.math, .arrows, .numbers, .punctuation, .units, .shapes, .greek, .scripts, .keyboard]

        var isEmoji: Bool {
            Self.emojiCategories.contains(self)
        }

        var title: String {
            switch self {
            case .smileys: return String(localized: "笑脸和情感")
            case .people: return String(localized: "人物和手势")
            case .nature: return String(localized: "动物和自然")
            case .food: return String(localized: "食物和饮料")
            case .travel: return String(localized: "旅行和地点")
            case .activities: return String(localized: "活动")
            case .objects: return String(localized: "物品")
            case .symbols: return String(localized: "符号")
            case .flags: return String(localized: "旗帜")
            case .math: return String(localized: "数学")
            case .arrows: return String(localized: "箭头")
            case .numbers: return String(localized: "数字序号")
            case .punctuation: return String(localized: "标点")
            case .units: return String(localized: "单位和货币")
            case .shapes: return String(localized: "形状")
            case .greek: return String(localized: "希腊字母")
            case .scripts: return String(localized: "上标和下标")
            case .keyboard: return String(localized: "键盘")
            }
        }

        /// 分类按钮上画的：表情的用一个表情，符号的用一个符号
        var icon: String {
            switch self {
            case .smileys: return "😀"
            case .people: return "👋"
            case .nature: return "🐱"
            case .food: return "🍎"
            case .travel: return "✈️"
            case .activities: return "⚽️"
            case .objects: return "💡"
            case .symbols: return "❤️"
            case .flags: return "🏁"
            case .math: return "±"
            case .arrows: return "→"
            case .numbers: return "①"
            case .punctuation: return "「」"
            case .units: return "℃"
            case .shapes: return "★"
            case .greek: return "α"
            case .scripts: return "x²"
            case .keyboard: return "⌘"
            }
        }

        /// 数据里表情的分组号（2 是肤色、发型这些零件，不列出来）
        init?(group: Int) {
            switch group {
            case 0: self = .smileys
            case 1: self = .people
            case 3: self = .nature
            case 4: self = .food
            case 5: self = .travel
            case 6: self = .activities
            case 7: self = .objects
            case 8: self = .symbols
            case 9: self = .flags
            default: return nil
            }
        }
    }

    struct Item: Identifiable, Hashable {
        /// 不带肤色的样子，也当 id
        let id: String
        let category: Category
        let chineseName: String
        let englishName: String
        /// 搜索用：中文、英文的别名和关键词，英文的都是小写
        let keywords: [String]
        /// 五种肤色，从浅到深；没有的为空
        let tones: [String]

        var isEmoji: Bool {
            category.isEmoji
        }

        /// 界面上显示的名字：中文界面用中文名
        var name: String {
            Localization.isChinese ? chineseName : englishName
        }

        /// 另一种语言的名字，写在名字后面
        var otherName: String {
            Localization.isChinese ? englishName : chineseName
        }

        /// 按选的肤色写出来：0 是默认的黄色，1～5 从浅到深
        func text(tone: Int) -> String {
            tone > 0 && tone <= tones.count ? tones[tone - 1] : id
        }

        /// 「U+1F604」「U+1F468 U+200D U+1F4BB」
        var codePoints: String {
            id.unicodeScalars.map { String(format: "U+%04X", $0.value) }.joined(separator: " ")
        }
    }

    /// Emoji 16.0 的表情 macOS 15.4 起才画得出来
    static let showsEmoji16 = ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 15, minorVersion: 4, patchVersion: 0))

    /// 所有的表情（按 Unicode 的顺序）和符号
    static let items: [Item] = parseEmoji(EmojiTable.emoji, includingEmoji16: showsEmoji16) + parseSymbols(EmojiTable.symbols)

    private static let byID: [String: Item] = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

    static func item(_ id: String) -> Item? {
        byID[id]
    }

    static func items(in category: Category) -> [Item] {
        items.filter { $0.category == category }
    }

    static func parseEmoji(_ table: String, includingEmoji16: Bool) -> [Item] {
        table.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 7, let group = Int(fields[1]), let category = Category(group: group) else { return nil }
            if fields[2] == "1", !includingEmoji16 {
                return nil
            }
            let keywords = fields[4].split(separator: "|").map(String.init) + fields[6].split(separator: "|").map { $0.lowercased() }
            let tones = fields.count > 7 ? fields[7].split(separator: " ").map(String.init) : []
            return Item(id: fields[0], category: category, chineseName: fields[3], englishName: fields[5],
                        keywords: keywords, tones: tones.count == 5 ? tones : [])
        }
    }

    static func parseSymbols(_ table: String) -> [Item] {
        table.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 4, let category = Category(rawValue: fields[0]) else { return nil }
            let chinese = fields[2].split(separator: "|").map(String.init)
            let english = fields[3].split(separator: "|").map(String.init)
            guard let chineseName = chinese.first, let englishName = english.first else { return nil }
            return Item(id: fields[1], category: category, chineseName: chineseName, englishName: englishName,
                        keywords: Array(chinese.dropFirst()) + english.dropFirst().map { $0.lowercased() }, tones: [])
        }
    }

    // MARK: - 搜索

    /// 中文名的拼音（「daxiao」）和首字母（「dx」），第一次用拼音搜时才算
    private static let pinyinIndex: [String: [String]] = {
        var index: [String: [String]] = [:]
        for item in items {
            let latin = item.chineseName.applyingTransform(.toLatin, reverse: false)?
                .applyingTransform(.stripDiacritics, reverse: false)?.lowercased() ?? ""
            let syllables = latin.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
            guard !syllables.isEmpty else { continue }
            index[item.id] = [syllables.joined(), String(syllables.compactMap(\.first))]
        }
        return index
    }()

    static func withoutVariationSelectors(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.filter { $0 != "\u{FE0F}" && $0 != "\u{FE0E}" }))
    }

    /// 按名字、关键词、拼音或首字母找；名字对上的在前，关键词对上的在后，同一档按 Unicode 的顺序
    static func search(_ query: String, limit: Int = 240) -> [Item] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return [] }
        // 粘进来的表情可能带着、也可能没带变体选择符（🐈 和 🐈️），比较时去掉
        let bareNeedle = withoutVariationSelectors(needle)
        let isLatin = needle.unicodeScalars.allSatisfy { $0.isASCII }
        // 英文、拼音太短的只认开头，免得一个字母对上一大堆
        let allowsContains = !isLatin || needle.count >= 3
        var ranked: [(rank: Int, index: Int, item: Item)] = []
        var seen = Set<String>()
        for (index, item) in items.enumerated() where !seen.contains(item.id) {
            let names = [item.chineseName, item.englishName.lowercased()]
            let rank: Int
            if item.id == needle || withoutVariationSelectors(item.id) == bareNeedle || names.contains(needle) {
                rank = 0
            } else if names.contains(where: { $0.hasPrefix(needle) }) {
                rank = 1
            } else if item.keywords.contains(needle) {
                rank = 2
            } else if allowsContains, names.contains(where: { $0.contains(needle) }) {
                rank = 3
            } else if item.keywords.contains(where: { $0.hasPrefix(needle) || (allowsContains && $0.contains(needle)) }) {
                rank = 4
            } else if isLatin, needle.count >= 2, (pinyinIndex[item.id] ?? []).contains(where: { $0.hasPrefix(needle) }) {
                rank = 5
            } else {
                continue
            }
            seen.insert(item.id)
            ranked.append((rank, index, item))
        }
        let sorted = ranked.sorted { $0.rank != $1.rank ? $0.rank < $1.rank : $0.index < $1.index }
        return sorted.prefix(limit).map { $0.item }
    }
}

/// 最近用过的表情和符号，最近的在前
struct EmojiRecents {
    static let key = "pop.emojiSymbols.recent"
    static let limit = 30

    let defaults: UserDefaults

    var ids: [String] {
        (defaults.stringArray(forKey: Self.key) ?? []).filter { EmojiSymbols.item($0) != nil }
    }

    func record(_ id: String) {
        var list = defaults.stringArray(forKey: Self.key) ?? []
        list.removeAll { $0 == id }
        list.insert(id, at: 0)
        defaults.set(Array(list.prefix(Self.limit)), forKey: Self.key)
    }
}
