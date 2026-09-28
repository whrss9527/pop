import Foundation

/// 内置插件的 ID。设置、iCloud 同步和插件实现都用这些字符串互相引用，不要随意改名。
enum BuiltinPluginID {
    static let translate = "translate"
    static let search = "search"
    static let openURL = "openURL"
    static let calculate = "calculate"
    static let copyPlain = "copyPlain"
    static let formatJSON = "formatJSON"
    static let timestamp = "timestamp"
    static let copyPath = "copyPath"
    static let revealInFinder = "revealInFinder"
    static let settings = "settings"

    static let all = [translate, search, openURL, calculate, copyPlain, formatJSON, timestamp, copyPath, revealInFinder, settings]
}

enum TriggerMode: String, Codable, CaseIterable, Identifiable {
    case longPressRight
    case modifierRightClick
    case middleClick
    case disabled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .longPressRight: return "长按右键"
        case .modifierRightClick: return "修饰键 + 右键"
        case .middleClick: return "鼠标中键"
        case .disabled: return "不用鼠标唤起"
        }
    }
}

enum TriggerModifier: String, Codable, CaseIterable, Identifiable {
    case option
    case control
    case command
    case shift

    var id: String { rawValue }

    var title: String {
        switch self {
        case .option: return "⌥ Option"
        case .control: return "⌃ Control"
        case .command: return "⌘ Command"
        case .shift: return "⇧ Shift"
        }
    }
}

enum HotKeyPreset: String, Codable, CaseIterable, Identifiable {
    case none
    case optionSpace
    case commandShiftSpace
    case optionBacktick

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "不使用"
        case .optionSpace: return "⌥ Space"
        case .commandShiftSpace: return "⌘ ⇧ Space"
        case .optionBacktick: return "⌥ `"
        }
    }
}

struct TriggerSettings: Codable, Equatable {
    var mode: TriggerMode = .longPressRight
    /// 长按判定时长（秒）
    var holdDuration: Double = 0.25
    var modifier: TriggerModifier = .option
    var hotKey: HotKeyPreset = .none
    /// 不响应鼠标唤起的 App（Bundle ID），比如游戏、远程桌面
    var excludedBundleIDs: [String] = []

    static let holdDurationRange: ClosedRange<Double> = 0.15...0.8

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = TriggerSettings()
        mode = c.lenient(.mode, default: d.mode)
        holdDuration = min(max(c.lenient(.holdDuration, default: d.holdDuration), Self.holdDurationRange.lowerBound), Self.holdDurationRange.upperBound)
        modifier = c.lenient(.modifier, default: d.modifier)
        hotKey = c.lenient(.hotKey, default: d.hotKey)
        excludedBundleIDs = c.lenient(.excludedBundleIDs, default: d.excludedBundleIDs)
    }
}

/// 圆盘布局：每一格放哪个插件（nil 表示空格子）。
struct RingLayout: Codable, Equatable {
    static let allowedSlotCounts = [4, 6, 8, 10, 12]

    var slots: [String?]

    static let `default` = RingLayout(slots: [
        BuiltinPluginID.translate,
        BuiltinPluginID.search,
        BuiltinPluginID.openURL,
        BuiltinPluginID.calculate,
        BuiltinPluginID.copyPlain,
        BuiltinPluginID.formatJSON,
        BuiltinPluginID.timestamp,
        BuiltinPluginID.copyPath,
    ])

    init(slots: [String?]) {
        self.slots = slots
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let decoded: [String?] = c.lenient(.slots, default: RingLayout.default.slots)
        slots = decoded.isEmpty ? RingLayout.default.slots : Array(decoded.prefix(RingLayout.allowedSlotCounts.max() ?? 12))
    }

    var slotCount: Int { slots.count }

    func index(of pluginID: String) -> Int? {
        slots.firstIndex(of: pluginID)
    }

    mutating func setSlotCount(_ count: Int) {
        guard count > 0, count != slots.count else { return }
        if count < slots.count {
            slots = Array(slots.prefix(count))
        } else {
            slots += Array(repeating: nil, count: count - slots.count)
        }
    }

    /// 把插件放到某一格。插件原本在别的格子时两格互换，这样拖动就能调整顺序。
    mutating func place(_ pluginID: String?, at index: Int) {
        guard slots.indices.contains(index) else { return }
        guard let pluginID else {
            slots[index] = nil
            return
        }
        if let from = slots.firstIndex(of: pluginID) {
            slots[from] = slots[index]
        }
        slots[index] = pluginID
    }

    mutating func remove(_ pluginID: String) {
        for i in slots.indices where slots[i] == pluginID {
            slots[i] = nil
        }
    }
}

/// 直达规则的触发条件。
enum RuleCondition: String, Codable, CaseIterable, Identifiable {
    case foreignText
    case chineseText
    case url
    case email
    case math
    case timestamp
    case json
    case files
    case image
    case anyText

    var id: String { rawValue }

    var kind: ContentKind {
        switch self {
        case .foreignText: return .foreignText
        case .chineseText: return .chineseText
        case .url: return .url
        case .email: return .email
        case .math: return .math
        case .timestamp: return .timestamp
        case .json: return .json
        case .files: return .files
        case .image: return .image
        case .anyText: return .text
        }
    }

    var title: String {
        switch self {
        case .foreignText: return "选中外文"
        case .chineseText: return "选中中文"
        case .url: return "选中链接"
        case .email: return "选中邮箱"
        case .math: return "选中算式"
        case .timestamp: return "选中时间戳"
        case .json: return "选中 JSON"
        case .files: return "选中文件"
        case .image: return "选中图片"
        case .anyText: return "其他任意文本"
        }
    }
}

/// 直达规则：选中内容满足条件时直接执行某个插件，不弹圆盘。
struct DirectRule: Codable, Equatable, Identifiable {
    var condition: RuleCondition
    var pluginID: String?
    var enabled: Bool

    var id: String { condition.rawValue }

    static let defaults: [DirectRule] = [
        DirectRule(condition: .foreignText, pluginID: BuiltinPluginID.translate, enabled: true),
        DirectRule(condition: .chineseText, pluginID: BuiltinPluginID.translate, enabled: false),
        DirectRule(condition: .url, pluginID: BuiltinPluginID.openURL, enabled: false),
        DirectRule(condition: .email, pluginID: BuiltinPluginID.openURL, enabled: false),
        DirectRule(condition: .math, pluginID: BuiltinPluginID.calculate, enabled: true),
        DirectRule(condition: .timestamp, pluginID: BuiltinPluginID.timestamp, enabled: false),
        DirectRule(condition: .json, pluginID: BuiltinPluginID.formatJSON, enabled: false),
        DirectRule(condition: .files, pluginID: BuiltinPluginID.copyPath, enabled: false),
        DirectRule(condition: .image, pluginID: nil, enabled: false),
        DirectRule(condition: .anyText, pluginID: BuiltinPluginID.translate, enabled: false),
    ]

    /// 保证每种条件恰好出现一次：保留已有顺序，去重，并补上新版本新增的条件。
    static func normalized(_ rules: [DirectRule]) -> [DirectRule] {
        var seen = Set<RuleCondition>()
        var result: [DirectRule] = []
        for rule in rules where !seen.contains(rule.condition) {
            seen.insert(rule.condition)
            result.append(rule)
        }
        for rule in defaults where !seen.contains(rule.condition) {
            result.append(rule)
        }
        return result
    }
}

struct TranslationSettings: Codable, Equatable {
    /// 外文译为
    var foreignTarget = "zh-Hans"
    /// 中文译为
    var chineseTarget = "en"

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = TranslationSettings()
        foreignTarget = c.lenient(.foreignTarget, default: d.foreignTarget)
        chineseTarget = c.lenient(.chineseTarget, default: d.chineseTarget)
    }
}

struct LanguageOption: Identifiable, Hashable {
    let id: String
    let name: String

    static let translationTargets: [LanguageOption] = [
        LanguageOption(id: "zh-Hans", name: "简体中文"),
        LanguageOption(id: "zh-Hant", name: "繁體中文"),
        LanguageOption(id: "en", name: "English"),
        LanguageOption(id: "ja", name: "日本語"),
        LanguageOption(id: "ko", name: "한국어"),
        LanguageOption(id: "fr", name: "Français"),
        LanguageOption(id: "de", name: "Deutsch"),
        LanguageOption(id: "es", name: "Español"),
        LanguageOption(id: "it", name: "Italiano"),
        LanguageOption(id: "pt", name: "Português"),
        LanguageOption(id: "ru", name: "Русский"),
    ]

    static func name(for id: String?) -> String {
        guard let id else { return "自动识别" }
        if let option = translationTargets.first(where: { $0.id == id }) {
            return option.name
        }
        return Locale.current.localizedString(forIdentifier: id) ?? id
    }
}

enum SearchEngine: String, Codable, CaseIterable, Identifiable {
    case google
    case bing
    case baidu
    case duckDuckGo

    var id: String { rawValue }

    var title: String {
        switch self {
        case .google: return "Google"
        case .bing: return "Bing"
        case .baidu: return "百度"
        case .duckDuckGo: return "DuckDuckGo"
        }
    }

    private var endpoint: (base: String, queryKey: String) {
        switch self {
        case .google: return ("https://www.google.com/search", "q")
        case .bing: return ("https://www.bing.com/search", "q")
        case .baidu: return ("https://www.baidu.com/s", "wd")
        case .duckDuckGo: return ("https://duckduckgo.com/", "q")
        }
    }

    /// 手动编码查询词：URLComponents 不会编码 `+`、`&`，搜「C++」会变成搜「C」。
    func searchURL(for query: String) -> URL? {
        let unreserved = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: unreserved) else { return nil }
        return URL(string: "\(endpoint.base)?\(endpoint.queryKey)=\(encoded)")
    }
}

/// 所有需要持久化（并通过 iCloud 同步）的设置。
struct AppSettings: Codable, Equatable {
    var trigger = TriggerSettings()
    var ring = RingLayout.default
    /// 已安装（启用）的插件
    var installedPlugins: [String] = BuiltinPluginID.all
    var rules: [DirectRule] = DirectRule.defaults
    var translation = TranslationSettings()
    var searchEngine: SearchEngine = .google
    /// 用户最后一次修改的时间，iCloud 同步时用它判断哪边更新。
    /// 全新安装是 distantPast，这样新设备第一次同步会直接采用云端的配置。
    var modifiedAt: Date = .distantPast

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        trigger = c.lenient(.trigger, default: d.trigger)
        ring = c.lenient(.ring, default: d.ring)
        installedPlugins = c.lenient(.installedPlugins, default: d.installedPlugins)
        rules = DirectRule.normalized(c.lenient(.rules, default: d.rules))
        translation = c.lenient(.translation, default: d.translation)
        searchEngine = c.lenient(.searchEngine, default: d.searchEngine)
        modifiedAt = c.lenient(.modifiedAt, default: d.modifiedAt)
    }

    /// 忽略 modifiedAt，只比较内容。
    func hasSameContent(as other: AppSettings) -> Bool {
        var copy = self
        copy.modifiedAt = other.modifiedAt
        return copy == other
    }

    func isInstalled(_ pluginID: String) -> Bool {
        installedPlugins.contains(pluginID)
    }

    mutating func setInstalled(_ pluginID: String, _ installed: Bool) {
        if installed {
            if !installedPlugins.contains(pluginID) {
                installedPlugins.append(pluginID)
            }
        } else {
            installedPlugins.removeAll { $0 == pluginID }
            ring.remove(pluginID)
        }
    }
}

extension KeyedDecodingContainer {
    /// 解码失败（字段缺失、类型不对、未知枚举值）时回退到默认值，
    /// 保证新旧版本之间通过 iCloud 交换设置时不会整体解码失败。
    func lenient<T: Decodable>(_ key: Key, default defaultValue: T) -> T {
        (try? decodeIfPresent(T.self, forKey: key)) ?? defaultValue
    }
}
