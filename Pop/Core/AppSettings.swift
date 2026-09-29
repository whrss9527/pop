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

    static let dictionary = "dictionary"
    static let speak = "speak"
    static let changeCase = "changeCase"
    static let encodeDecode = "encodeDecode"
    static let textStats = "textStats"
    static let hash = "hash"
    static let numberConvert = "numberConvert"
    static let colorConvert = "colorConvert"
    static let random = "random"
    static let qrCode = "qrCode"
    static let ocr = "ocr"
    static let screenshotOCR = "screenshotOCR"
    static let colorPicker = "colorPicker"
    static let openInTerminal = "openInTerminal"
    static let quickNote = "quickNote"
    static let clipboardHistory = "clipboardHistory"
    static let allPlugins = "allPlugins"

    /// 0.1 版就有的功能。旧版本的设置里没有记录「见过哪些内置功能」，按这个列表补齐。
    static let legacy = [translate, search, openURL, calculate, copyPlain, formatJSON, timestamp, copyPath, revealInFinder, settings]

    static let all = legacy + [
        dictionary, speak, changeCase, encodeDecode, textStats, hash, numberConvert, colorConvert, random, qrCode,
        ocr, screenshotOCR, colorPicker, openInTerminal, quickNote, clipboardHistory, allPlugins,
    ]
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
    case commandShiftV
    case commandOptionV
    case controlCommandV
    case optionV

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "不使用"
        case .optionSpace: return "⌥ Space"
        case .commandShiftSpace: return "⌘ ⇧ Space"
        case .optionBacktick: return "⌥ `"
        case .commandShiftV: return "⌘ ⇧ V"
        case .commandOptionV: return "⌘ ⌥ V"
        case .controlCommandV: return "⌃ ⌘ V"
        case .optionV: return "⌥ V"
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
    /// 长按右键唤起的圆盘，在圆心松开后保持打开、改用点击选择；默认松开右键就关闭圆盘
    var keepsRingOpen: Bool = false

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
        keepsRingOpen = c.lenient(.keepsRingOpen, default: d.keepsRingOpen)
    }

    /// 这次唤起松开鼠标键时是否关闭圆盘：只有长按右键、并且没打开「保持圆盘打开」时。
    /// 修饰键 + 右键、中键是点一下就唤起的，松开后圆盘保持打开。
    var closesRingOnRelease: Bool {
        mode == .longPressRight && !keepsRingOpen
    }
}

/// 圆盘布局：每一格放哪个插件（nil 表示空格子）。
struct RingLayout: Codable, Equatable {
    static let allowedSlotCounts = [4, 6, 8, 10, 12]

    var slots: [String?]

    /// 上半圈放处理选中文字的功能，下半圈放不需要选中内容的功能，什么都没选中时也有得用。
    static let `default` = RingLayout(slots: [
        BuiltinPluginID.translate,
        BuiltinPluginID.search,
        BuiltinPluginID.dictionary,
        BuiltinPluginID.openURL,
        BuiltinPluginID.allPlugins,
        BuiltinPluginID.clipboardHistory,
        BuiltinPluginID.screenshotOCR,
        BuiltinPluginID.colorPicker,
    ])

    /// 0.1 版的默认布局。老用户没改过布局的话，升级后换成新的默认布局，新功能才会出现在圆盘上。
    static let legacyDefault = RingLayout(slots: [
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
    case color
    case word
    case foreignText
    case chineseText
    case url
    case email
    case math
    case timestamp
    case dateTime
    case number
    case json
    case files
    case image
    case anyText

    var id: String { rawValue }

    var kind: ContentKind {
        switch self {
        case .color: return .color
        case .word: return .word
        case .foreignText: return .foreignText
        case .chineseText: return .chineseText
        case .url: return .url
        case .email: return .email
        case .math: return .math
        case .timestamp: return .timestamp
        case .dateTime: return .dateTime
        case .number: return .number
        case .json: return .json
        case .files: return .files
        case .image: return .image
        case .anyText: return .text
        }
    }

    var title: String {
        switch self {
        case .color: return "选中颜色值"
        case .word: return "选中单个词"
        case .foreignText: return "选中外文"
        case .chineseText: return "选中中文"
        case .url: return "选中链接"
        case .email: return "选中邮箱"
        case .math: return "选中算式"
        case .timestamp: return "选中时间戳"
        case .dateTime: return "选中日期时间"
        case .number: return "选中数字"
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

    /// 从上到下匹配，所以更具体的条件（单个词）要排在更宽泛的条件（外文）前面。
    static let defaults: [DirectRule] = [
        DirectRule(condition: .color, pluginID: BuiltinPluginID.colorConvert, enabled: true),
        DirectRule(condition: .word, pluginID: BuiltinPluginID.dictionary, enabled: false),
        DirectRule(condition: .foreignText, pluginID: BuiltinPluginID.translate, enabled: true),
        DirectRule(condition: .chineseText, pluginID: BuiltinPluginID.translate, enabled: false),
        DirectRule(condition: .url, pluginID: BuiltinPluginID.openURL, enabled: false),
        DirectRule(condition: .email, pluginID: BuiltinPluginID.openURL, enabled: false),
        DirectRule(condition: .math, pluginID: BuiltinPluginID.calculate, enabled: true),
        DirectRule(condition: .timestamp, pluginID: BuiltinPluginID.timestamp, enabled: false),
        DirectRule(condition: .dateTime, pluginID: BuiltinPluginID.timestamp, enabled: false),
        DirectRule(condition: .number, pluginID: BuiltinPluginID.numberConvert, enabled: false),
        DirectRule(condition: .json, pluginID: BuiltinPluginID.formatJSON, enabled: false),
        DirectRule(condition: .files, pluginID: BuiltinPluginID.copyPath, enabled: false),
        DirectRule(condition: .image, pluginID: BuiltinPluginID.ocr, enabled: true),
        DirectRule(condition: .anyText, pluginID: BuiltinPluginID.translate, enabled: false),
    ]

    /// 保证每种条件恰好出现一次：保留已有的规则和顺序，去重；
    /// 新版本新增的条件按默认顺序插进去（插在默认排在它后面的第一条规则前面），这样匹配顺序依然合理。
    static func normalized(_ rules: [DirectRule]) -> [DirectRule] {
        var seen = Set<RuleCondition>()
        var result: [DirectRule] = []
        for rule in rules where !seen.contains(rule.condition) {
            seen.insert(rule.condition)
            result.append(rule)
        }
        for (index, rule) in defaults.enumerated() where !seen.contains(rule.condition) {
            let followers = Set(defaults[(index + 1)...].map(\.condition))
            if let position = result.firstIndex(where: { followers.contains($0.condition) }) {
                result.insert(rule, at: position)
            } else {
                result.append(rule)
            }
            seen.insert(rule.condition)
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
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .popURLValueAllowed) else { return nil }
        return URL(string: "\(endpoint.base)?\(endpoint.queryKey)=\(encoded)")
    }
}

extension CharacterSet {
    /// URL 里的参数值只保留这些字符不编码（RFC 3986 的 unreserved）。
    static let popURLValueAllowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
}

/// 剪贴板历史的设置。历史记录本身只存在本机，这些偏好会随设置一起同步。
struct ClipboardSettings: Codable, Equatable {
    var enabled = true
    var hotKey: HotKeyPreset = .commandShiftV
    /// 保存天数，0 表示一直保存
    var retentionDays = 7
    var maxItems = 500
    var recordImages = true
    /// 不记录这些 App 里复制的内容（Bundle ID），比如密码管理器
    var ignoredBundleIDs: [String] = ClipboardSettings.defaultIgnoredBundleIDs

    static let retentionChoices = [1, 3, 7, 30, 90, 0]
    static let maxItemChoices = [100, 200, 500, 1000, 5000]
    static let defaultIgnoredBundleIDs = [
        "com.apple.keychainaccess",
        "com.apple.Passwords",
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.bitwarden.desktop",
        "org.keepassxc.keepassxc",
    ]

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ClipboardSettings()
        enabled = c.lenient(.enabled, default: d.enabled)
        hotKey = c.lenient(.hotKey, default: d.hotKey)
        retentionDays = max(c.lenient(.retentionDays, default: d.retentionDays), 0)
        maxItems = min(max(c.lenient(.maxItems, default: d.maxItems), 10), 100_000)
        recordImages = c.lenient(.recordImages, default: d.recordImages)
        ignoredBundleIDs = c.lenient(.ignoredBundleIDs, default: d.ignoredBundleIDs)
    }

    static func retentionTitle(_ days: Int) -> String {
        days == 0 ? "一直保存" : "\(days) 天"
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
    var clipboard = ClipboardSettings()
    /// 已经「见过」的内置功能。新版本新增的内置功能不在这里面，读取旧设置时会自动装上。
    var knownBuiltinPlugins: [String] = BuiltinPluginID.all
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
        clipboard = c.lenient(.clipboard, default: d.clipboard)
        knownBuiltinPlugins = c.lenient(.knownBuiltinPlugins, default: BuiltinPluginID.legacy)
        modifiedAt = c.lenient(.modifiedAt, default: d.modifiedAt)
        if !knownBuiltinPlugins.contains(BuiltinPluginID.allPlugins), ring == .legacyDefault {
            ring = .default
        }
        adoptNewBuiltinPlugins()
    }

    /// 新版本新增的内置功能默认装上（用户之后卸载了就不会再自动装回来）。
    mutating func adoptNewBuiltinPlugins() {
        for id in BuiltinPluginID.all where !knownBuiltinPlugins.contains(id) {
            if !installedPlugins.contains(id) {
                installedPlugins.append(id)
            }
            knownBuiltinPlugins.append(id)
        }
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
