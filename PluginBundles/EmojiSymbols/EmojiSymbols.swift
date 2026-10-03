import CoreGraphics
import CoreText
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
            case .arrows: return String(localized: "箭头符号")
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
        /// 不带肤色的样子
        let id: String
        /// 列表、最近用过的里分得开的写法：一般就是 id；同一个字符在两类里都有（π、Ω、↖、↘）时，后一个带上分类
        let key: String
        let category: Category
        let chineseName: String
        let englishName: String
        /// 搜索用：中文、英文的别名和关键词，英文的都是小写
        let keywords: [String]
        /// 五种肤色，从浅到深；没有的为空
        let tones: [String]
        /// 搜索用，事先算好：中文名和小写的英文名、去掉变体选择符的 id
        let searchNames: [String]
        let bareID: String

        init(id: String, key: String? = nil, category: Category, chineseName: String, englishName: String,
             keywords: [String], tones: [String]) {
            self.id = id
            self.key = key ?? id
            self.category = category
            self.chineseName = chineseName
            self.englishName = englishName
            self.keywords = keywords
            self.tones = tones
            searchNames = [chineseName, englishName.lowercased()]
            bareID = EmojiSymbols.withoutVariationSelectors(id)
        }

        /// 换一个 key（别的都不变）
        func with(key: String) -> Item {
            Item(id: id, key: key, category: category, chineseName: chineseName, englishName: englishName,
                 keywords: keywords, tones: tones)
        }

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
    static let items: [Item] = uniqueKeys(parseEmoji(EmojiTable.emoji, includingEmoji16: showsEmoji16) + parseSymbols(EmojiTable.symbols))

    private static let byKey: [String: Item] = Dictionary(items.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })

    /// 按 key 找（最近用过的存的是 key）
    static func item(_ key: String) -> Item? {
        byKey[key]
    }

    /// 同一个字符第二次出现时，key 带上分类（「greek:π」），免得最近用过的、列表里认错
    static func uniqueKeys(_ items: [Item]) -> [Item] {
        var seen = Set<String>()
        return items.map { item in
            seen.insert(item.key).inserted ? item : item.with(key: item.category.rawValue + ":" + item.id)
        }
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

    /// 每一项中文名的拼音（「daxiao」）和首字母（「dx」），和 items 一一对应。第一次用拼音搜时才算，
    /// 卡片打开时会先在后台算好（`prepareSearch`）
    private static let pinyinIndex: [[String]] = items.map { item in
        let latin = item.chineseName.applyingTransform(.toLatin, reverse: false)?
            .applyingTransform(.stripDiacritics, reverse: false)?.lowercased() ?? ""
        let syllables = latin.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        guard !syllables.isEmpty else { return [] }
        return [syllables.joined(), String(syllables.compactMap(\.first))]
    }

    /// 打开卡片前在后台先把数据拆开（两千多个表情），再把卡片一打开就看得见的表情、符号画一遍：
    /// 放在主线程上，第一次打开卡片要顿好一会儿。query 是卡片打开时搜的（没有就是「笑脸和情感」那一类），
    /// scales 是屏幕的倍数（`EmojiSymbolsPlugin.screenScales()`，在主线程上先读好）
    static func prepare(query: String = "", scales: [CGFloat] = [2]) async {
        await runInBackground {
            _ = items.count
            warmUpGlyphs(query: query, scales: scales)
        }
    }

    /// 表情、符号不在系统字体里，要沿着后备字体一个个找过去；表情字体很大，每个表情每一档大小的图在文件里各在一处，
    /// 第一次画时才从磁盘上读。卡片一打开就看得见的（列出来的前 50 个、底下放大的那个、分类按钮）先在后台
    /// 用界面上的系统字体、按卡片上的大小和屏幕的倍数画一遍，主线程画的时候就不用等了
    private static func warmUpGlyphs(query: String, scales: [CGFloat]) {
        let listed = Array((query.isEmpty ? items(in: .smileys) : search(query)).prefix(50))
        let runs: [(texts: [String], size: CGFloat)] = [
            (listed.filter(\.isEmoji).map(\.id), 24),
            (listed.filter { !$0.isEmoji }.map(\.id), 19),
            (listed.prefix(1).map(\.id), 26),
            (Category.emojiCategories.map(\.icon), 16),
            (Category.symbolCategories.map(\.icon), 14),
        ]
        for scale in scales where scale > 0 {
            guard let context = CGContext(data: nil, width: Int(320 * scale), height: Int(64 * scale), bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }
            context.scaleBy(x: scale, y: scale)
            for run in runs where !run.texts.isEmpty {
                let font = CTFontCreateUIFontForLanguage(.system, run.size, nil) ?? CTFontCreateWithName("AppleColorEmoji" as CFString, run.size, nil)
                // 一行 8 个，都落在画布里（画布外面的不会真的画）
                for start in stride(from: 0, to: run.texts.count, by: 8) {
                    let line = run.texts[start..<min(start + 8, run.texts.count)].joined(separator: " ")
                    let text = NSAttributedString(string: line, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
                    context.textPosition = CGPoint(x: 4, y: 8)
                    CTLineDraw(CTLineCreateWithAttributedString(text as CFAttributedString), context)
                }
            }
        }
    }

    /// 在后台先把数据拆开、把拼音算好，打字时不用等
    static func prepareSearch() {
        Task.detached(priority: .utility) {
            _ = pinyinIndex.count
        }
    }

    static func withoutVariationSelectors(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.filter { $0 != "\u{FE0F}" && $0 != "\u{FE0E}" }))
    }

    /// 按名字、关键词、拼音或首字母找；名字对上的在前，关键词对上的在后，同一档按 Unicode 的顺序
    static func search(_ query: String, limit: Int = 240) -> [Item] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let needle = trimmed.lowercased()
        guard !needle.isEmpty else { return [] }
        // 粘进来的表情、符号按原样比（Ω 不能变成 ω）；可能带着、也可能没带变体选择符（🐈 和 🐈️），比较时去掉
        let bareQuery = withoutVariationSelectors(trimmed)
        let isLatin = needle.unicodeScalars.allSatisfy { $0.isASCII }
        // 英文、拼音太短的只认开头，免得一个字母对上一大堆
        let allowsContains = !isLatin || needle.count >= 3
        let usesPinyin = isLatin && needle.count >= 2
        let pinyin = usesPinyin ? pinyinIndex : []
        var ranked: [(rank: Int, index: Int, item: Item)] = []
        for (index, item) in items.enumerated() {
            let names = item.searchNames
            let rank: Int
            if item.id == trimmed || item.bareID == bareQuery || names.contains(needle) {
                rank = 0
            } else if names.contains(where: { $0.hasPrefix(needle) }) {
                rank = 1
            } else if item.keywords.contains(needle) {
                rank = 2
            } else if allowsContains, names.contains(where: { $0.contains(needle) }) {
                rank = 3
            } else if item.keywords.contains(where: { $0.hasPrefix(needle) || (allowsContains && $0.contains(needle)) }) {
                rank = 4
            } else if usesPinyin, pinyin[index].contains(where: { $0.hasPrefix(needle) }) {
                rank = 5
            } else {
                continue
            }
            ranked.append((rank, index, item))
        }
        // 同一个字符在两类里都有时只列一次，留对得最好的那个（搜「欧姆」是单位里的 Ω，搜「欧米伽」是希腊字母的）
        var seen = Set<String>()
        return ranked
            .sorted { $0.rank != $1.rank ? $0.rank < $1.rank : $0.index < $1.index }
            .filter { seen.insert($0.item.id).inserted }
            .prefix(limit)
            .map { $0.item }
    }
}

/// 最近用过的表情和符号（存的是 `Item.key`），最近的在前
struct EmojiRecents {
    static let key = "pop.emojiSymbols.recent"
    static let limit = 30

    let defaults: UserDefaults

    var ids: [String] {
        (defaults.stringArray(forKey: Self.key) ?? []).filter { EmojiSymbols.item($0) != nil }
    }

    func record(_ key: String) {
        var list = defaults.stringArray(forKey: Self.key) ?? []
        list.removeAll { $0 == key }
        list.insert(key, at: 0)
        defaults.set(Array(list.prefix(Self.limit)), forKey: Self.key)
    }
}
