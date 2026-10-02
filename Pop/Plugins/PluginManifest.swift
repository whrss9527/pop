import Foundation

/// 用户插件的描述文件。每个插件是插件文件夹里的一个 JSON 文件：
///
/// ```json
/// {
///   "id": "user-3f9a1c2b",
///   "name": "GitHub 搜索",
///   "symbol": "magnifyingglass",
///   "match": { "kinds": ["text"] },
///   "action": { "type": "url", "template": "https://github.com/search?q={text}" },
///   "output": "none"
/// }
/// ```
///
/// 所有字段都宽松解码：缺字段、未知的值都回退到默认值，新旧版本之间交换插件不会整体失败。
struct PluginManifest: Codable, Equatable, Identifiable {
    static let currentFormat = 1

    var format = PluginManifest.currentFormat
    var id: String
    var name: String
    var symbol = PluginManifest.defaultSymbol
    var summary = ""
    var match = Match()
    var action = Action()
    var output: Output = .card
    /// 最后修改时间（iCloud 同步用），精确到秒
    var modifiedAt: Date = .distantPast
    /// 其他语言的名称和说明，键是语言代码：{"en": {"name": "GitHub Search", "summary": "…"}}。
    /// 界面是这种语言时显示它，没写的语言用 name、summary。
    var localized: [String: LocalizedText]? = nil

    static let defaultSymbol = "puzzlepiece.extension"

    struct LocalizedText: Codable, Equatable {
        var name: String?
        var summary: String?
    }

    /// 按界面语言显示的名称
    var displayName: String {
        Self.localizedValue(localized, \.name) ?? name
    }

    /// 按界面语言显示的说明
    var displaySummary: String {
        Self.localizedValue(localized, \.summary) ?? summary
    }

    /// 先找界面语言（比如 en、zh-Hans），再找去掉地区的写法（zh-Hant-HK → zh-Hant → zh）
    static func localizedValue(_ localized: [String: LocalizedText]?, _ field: KeyPath<LocalizedText, String?>,
                               languages: [String] = Bundle.main.preferredLocalizations) -> String? {
        guard let localized, !localized.isEmpty else { return nil }
        for language in languages {
            var code = language
            while true {
                if let value = localized[code]?[keyPath: field]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                    return value
                }
                guard let dash = code.lastIndex(of: "-") else { break }
                code = String(code[..<dash])
            }
        }
        return nil
    }

    struct Match: Codable, Equatable {
        /// 能处理的内容类型；为空表示随时可用（不需要选中内容）
        var kinds: [ContentKind] = [.text]
        /// 选中的文字还要匹配这个正则
        var pattern: String? = nil
        var minLength: Int? = nil
        var maxLength: Int? = nil

        init(kinds: [ContentKind] = [.text], pattern: String? = nil, minLength: Int? = nil, maxLength: Int? = nil) {
            self.kinds = kinds
            self.pattern = pattern
            self.minLength = minLength
            self.maxLength = maxLength
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            // 逐个解析，忽略新版本才有的类型
            let rawKinds: [String] = c.lenient(.kinds, default: ["text"])
            var kinds: [ContentKind] = []
            for raw in rawKinds {
                if let kind = ContentKind(rawValue: raw), !kinds.contains(kind) {
                    kinds.append(kind)
                }
            }
            self.kinds = kinds
            pattern = c.lenient(.pattern, default: String?.none)
            minLength = c.lenient(.minLength, default: Int?.none)
            maxLength = c.lenient(.maxLength, default: Int?.none)
        }
    }

    struct Action: Codable, Equatable {
        enum Kind: String, Codable, CaseIterable, Identifiable {
            /// 打开网址模板
            case url
            /// 运行 Shell 脚本（zsh）
            case shell
            /// 运行 JavaScript
            case javascript
            /// 运行快捷指令
            case shortcut
            /// 把选中的文字和指令发给 AI
            case ai

            var id: String { rawValue }

            var title: String {
                switch self {
                case .url: return String(localized: "打开网址")
                case .shell: return String(localized: "Shell 脚本")
                case .javascript: return "JavaScript"
                case .shortcut: return String(localized: "快捷指令")
                case .ai: return String(localized: "AI 指令")
                }
            }

            /// 新建、编辑插件时能选的类型。App Store 版开了沙盒，不运行 Shell 脚本；正在编辑的插件已经是这种类型的话也留着
            static func available(keeping current: Kind) -> [Kind] {
                allCases.filter { !Distribution.isAppStore || $0 != .shell || $0 == current }
            }
        }

        var type: Kind = .url
        /// url：网址模板，{text} 替换成编码后的选中文字，{raw} 替换成原文
        var template = ""
        /// shell / javascript：脚本内容
        var script = ""
        /// shortcut：快捷指令名称
        var shortcut = ""
        /// ai：给 AI 的指令，{text} 换成选中的文字
        var prompt = ""
        /// 最长运行时间（秒）
        var timeout: Double = Action.defaultTimeout

        static let defaultTimeout: Double = 15
        static let timeoutRange: ClosedRange<Double> = 1...300

        init(type: Kind = .url, template: String = "", script: String = "", shortcut: String = "", prompt: String = "",
             timeout: Double = Action.defaultTimeout) {
            self.type = type
            self.template = template
            self.script = script
            self.shortcut = shortcut
            self.prompt = prompt
            self.timeout = timeout
        }

        private enum CodingKeys: String, CodingKey {
            case type, template, script, shortcut, prompt, timeout
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            type = c.lenient(.type, default: .url)
            template = c.lenient(.template, default: "")
            script = c.lenient(.script, default: "")
            shortcut = c.lenient(.shortcut, default: "")
            prompt = c.lenient(.prompt, default: "")
            timeout = Self.clampTimeout(c.lenient(.timeout, default: Self.defaultTimeout))
        }

        /// 只写出当前类型用得到的字段，文件更干净。
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(type, forKey: .type)
            switch type {
            case .url:
                try c.encode(template, forKey: .template)
            case .shell, .javascript:
                try c.encode(script, forKey: .script)
                try c.encode(timeout, forKey: .timeout)
            case .shortcut:
                try c.encode(shortcut, forKey: .shortcut)
                try c.encode(timeout, forKey: .timeout)
            case .ai:
                try c.encode(prompt, forKey: .prompt)
            }
        }

        static func clampTimeout(_ value: Double) -> Double {
            guard value.isFinite else { return defaultTimeout }
            return min(max(value, timeoutRange.lowerBound), timeoutRange.upperBound)
        }
    }

    /// 脚本输出的去向。打开网址的插件没有输出。
    enum Output: String, Codable, CaseIterable, Identifiable {
        /// 显示在结果卡片里
        case card
        /// 复制到剪贴板
        case copy
        /// 替换选中的文字
        case replace
        /// 轻提示
        case toast
        /// 什么都不显示
        case none

        var id: String { rawValue }

        var title: String {
            switch self {
            case .card: return String(localized: "显示结果卡片")
            case .copy: return String(localized: "复制到剪贴板")
            case .replace: return String(localized: "替换选中的文字")
            case .toast: return String(localized: "轻提示")
            case .none: return String(localized: "不显示")
            }
        }
    }

    init(id: String = PluginManifest.makeID(), name: String, symbol: String = PluginManifest.defaultSymbol, summary: String = "",
         match: Match = Match(), action: Action = Action(), output: Output = .card, modifiedAt: Date = .distantPast) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.summary = summary
        self.match = match
        self.action = action
        self.output = output
        self.modifiedAt = modifiedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        format = c.lenient(.format, default: Self.currentFormat)
        id = c.lenient(.id, default: "")
        name = c.lenient(.name, default: "")
        symbol = c.lenient(.symbol, default: Self.defaultSymbol)
        summary = c.lenient(.summary, default: "")
        match = c.lenient(.match, default: Match())
        action = c.lenient(.action, default: Action())
        output = c.lenient(.output, default: .card)
        modifiedAt = c.lenient(.modifiedAt, default: .distantPast)
        localized = c.lenient(.localized, default: [String: LocalizedText]?.none)
    }

    // MARK: - ID

    static func makeID() -> String {
        "user-" + String(UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "").prefix(10))
    }

    /// ID 同时是文件名，只允许字母、数字、点、横线和下划线。
    static func isValidID(_ id: String) -> Bool {
        guard (1...64).contains(id.count), !id.hasPrefix(".") else { return false }
        return id.unicodeScalars.allSatisfy { scalar in
            scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || "._-".unicodeScalars.contains(scalar))
        }
    }

    // MARK: - 校验与整理

    /// 保存前整理：去掉首尾空白、清掉当前类型用不到的字段、空字符串变成 nil。
    func normalized() -> PluginManifest {
        var copy = self
        copy.format = Self.currentFormat
        copy.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.symbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        if copy.symbol.isEmpty {
            copy.symbol = Self.defaultSymbol
        }
        copy.summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let texts = (localized ?? [:]).compactMapValues { text -> LocalizedText? in
            let name = text.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            let summary = text.summary?.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmed = LocalizedText(name: name?.isEmpty == false ? name : nil, summary: summary?.isEmpty == false ? summary : nil)
            return trimmed.name == nil && trimmed.summary == nil ? nil : trimmed
        }
        copy.localized = texts.isEmpty ? nil : texts
        let pattern = (match.pattern ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        copy.match.pattern = pattern.isEmpty ? nil : pattern
        if let min = copy.match.minLength, min <= 0 {
            copy.match.minLength = nil
        }
        if let max = copy.match.maxLength, max <= 0 {
            copy.match.maxLength = nil
        }
        copy.action.timeout = Action.clampTimeout(action.timeout)
        switch action.type {
        case .url:
            copy.action = Action(type: .url, template: action.template.trimmingCharacters(in: .whitespacesAndNewlines))
            // 打开网址没有输出
            copy.output = .none
        case .shell, .javascript:
            copy.action = Action(type: action.type, script: action.script, timeout: copy.action.timeout)
        case .shortcut:
            copy.action = Action(type: .shortcut, shortcut: action.shortcut.trimmingCharacters(in: .whitespacesAndNewlines), timeout: copy.action.timeout)
        case .ai:
            copy.action = Action(type: .ai, prompt: action.prompt.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return copy
    }

    /// 返回需要用户修正的问题；nil 表示可以保存。
    func validationError() -> String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return String(localized: "请填写名称")
        }
        if let pattern = match.pattern, !pattern.isEmpty, (try? NSRegularExpression(pattern: pattern)) == nil {
            return String(localized: "正则表达式有误")
        }
        switch action.type {
        case .url:
            let template = action.template.trimmingCharacters(in: .whitespacesAndNewlines)
            if template.isEmpty { return String(localized: "请填写网址") }
            let sample = template.replacingOccurrences(of: "{text}", with: "test").replacingOccurrences(of: "{raw}", with: "test")
            if URL(string: sample)?.scheme == nil { return String(localized: "网址需要以 https:// 之类的协议开头") }
        case .shell, .javascript:
            if action.script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return String(localized: "请填写脚本") }
        case .shortcut:
            if action.shortcut.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return String(localized: "请填写快捷指令名称") }
        case .ai:
            if action.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return String(localized: "请填写给 AI 的指令") }
        }
        return nil
    }

    // MARK: - 编解码

    /// 插件文件使用的编码器：格式化输出，日期写成 ISO 8601 方便手动编辑。
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// 当前时间，精确到秒（ISO 8601 只保存到秒，这样写进文件再读出来仍然相等）。
    static func timestamp(_ date: Date = Date()) -> Date {
        Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down))
    }
}

// MARK: - 模板

extension PluginManifest {
    struct Template: Identifiable {
        let id: String
        let title: String
        let manifest: PluginManifest
    }

    /// 「新建插件」菜单里的示例，照着改就能用。
    /// 新建插件的模板。App Store 版不运行 Shell 脚本，没有 Shell 的模板
    static var templates: [Template] {
        allTemplates.filter { !Distribution.isAppStore || $0.manifest.action.type != .shell }
    }

    private static var allTemplates: [Template] {
        [
            Template(id: "blank-url", title: String(localized: "网址（空白）"),
                     manifest: PluginManifest(name: String(localized: "新的网页插件"), symbol: "globe",
                                              action: Action(type: .url, template: "https://www.google.com/search?q={text}"), output: .none)),
            Template(id: "github", title: String(localized: "网址：GitHub 搜索"),
                     manifest: PluginManifest(name: String(localized: "GitHub 搜索"), symbol: "chevron.left.forwardslash.chevron.right",
                                              summary: String(localized: "在 GitHub 上搜索选中的文字"),
                                              action: Action(type: .url, template: "https://github.com/search?q={text}&type=code"), output: .none)),
            Template(id: "wikipedia", title: String(localized: "网址：维基百科"),
                     manifest: PluginManifest(name: String(localized: "维基百科"), symbol: "book",
                                              summary: String(localized: "在维基百科中查找选中的词条"),
                                              action: Action(type: .url, template: "https://zh.wikipedia.org/wiki/Special:Search?search={text}"), output: .none)),
            Template(id: "maps", title: String(localized: "网址：在地图中查找"),
                     manifest: PluginManifest(name: String(localized: "地图"), symbol: "map",
                                              summary: String(localized: "在「地图」App 中查找选中的地址"),
                                              action: Action(type: .url, template: "maps://?q={text}"), output: .none)),
            Template(id: "shell-sort", title: String(localized: "Shell：按行排序去重"),
                     manifest: PluginManifest(name: String(localized: "排序去重"), symbol: "arrow.up.arrow.down",
                                              summary: String(localized: "把选中的多行文字排序并去掉重复行"),
                                              action: Action(type: .shell, script: "sort -u"), output: .replace)),
            Template(id: "shell-say", title: String(localized: "Shell：环境变量示例"),
                     manifest: PluginManifest(name: String(localized: "字数（Shell）"), symbol: "terminal",
                                              summary: String(localized: "演示如何读取选中的内容"),
                                              action: Action(type: .shell, script: "# 选中的文字从标准输入传入，也可以用 $POP_TEXT\n# 选中文件时 $POP_FILES 是每行一个路径\nprintf '%s' \"$POP_TEXT\" | wc -m | tr -d ' '"),
                                              output: .toast)),
            Template(id: "js-reverse", title: String(localized: "JavaScript：反转文字"),
                     manifest: PluginManifest(name: String(localized: "反转文字"), symbol: "arrow.left.arrow.right",
                                              summary: String(localized: "把选中的文字倒过来"),
                                              action: Action(type: .javascript, script: String(localized: "// input 是选中的文字，返回值会作为结果\nfunction run(input) {\n  return Array.from(input).reverse().join('')\n}")),
                                              output: .card)),
            Template(id: "js-json-keys", title: String(localized: "JavaScript：列出 JSON 的键"),
                     manifest: PluginManifest(name: String(localized: "JSON 键名"), symbol: "list.bullet",
                                              summary: String(localized: "列出选中 JSON 对象的所有键"),
                                              match: Match(kinds: [.json]),
                                              action: Action(type: .javascript, script: "function run(input) {\n  return Object.keys(JSON.parse(input)).join('\\n')\n}"),
                                              output: .card)),
            Template(id: "ai-formal", title: String(localized: "AI：改写成正式的语气"),
                     manifest: PluginManifest(name: String(localized: "正式一点"), symbol: "text.quote",
                                              summary: String(localized: "让 AI 把选中的文字改写得正式、礼貌"),
                                              action: Action(type: .ai, prompt: String(localized: "把下面的文字改写得更正式、礼貌，保持原来的语言和意思，只输出改写后的文字：\n\n{text}")),
                                              output: .card)),
            Template(id: "ai-reply", title: String(localized: "AI：帮我回复"),
                     manifest: PluginManifest(name: String(localized: "帮我回复"), symbol: "arrowshape.turn.up.left",
                                              summary: String(localized: "让 AI 替选中的消息拟一段回复"),
                                              action: Action(type: .ai, prompt: String(localized: "下面是别人发给我的消息，帮我拟一段得体、简洁的回复，用消息原来的语言：\n\n{text}")),
                                              output: .card)),
            Template(id: "shortcut", title: String(localized: "快捷指令"),
                     manifest: PluginManifest(name: String(localized: "运行快捷指令"), symbol: "square.stack.3d.up",
                                              summary: String(localized: "把选中的文字交给快捷指令处理"),
                                              action: Action(type: .shortcut, shortcut: String(localized: "我的快捷指令"), timeout: 60), output: .card)),
        ]
    }
}
