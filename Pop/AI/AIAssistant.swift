import Foundation
import Security

/// AI 卡片上的常用指令
enum AIAction: String, CaseIterable, Identifiable {
    case polish
    case summarize
    case explain
    case translate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .polish: return "润色"
        case .summarize: return "总结"
        case .explain: return "解释"
        case .translate: return "翻译"
        }
    }

    /// 发给模型的指令。answerLanguage 是回答用的语言，translationTarget 是翻译的目标语言（都是语言名，比如「简体中文」）
    func instruction(answerLanguage: String, translationTarget: String) -> String {
        switch self {
        case .polish:
            return "润色下面的文字：改正错别字、语法错误和不通顺的地方，保持原意、语气和原来的语言。只输出润色后的文字。"
        case .summarize:
            return "用几条简洁的要点总结下面的内容，用\(answerLanguage)回答。"
        case .explain:
            return "解释下面这段内容是什么意思，需要时补充背景、术语和例子，用\(answerLanguage)回答。"
        case .translate:
            return "把下面的文字翻译成\(translationTarget)，只输出译文。"
        }
    }
}

enum AIPrompt {
    static let system = "你是 Pop 里的文字助手，帮用户处理他在屏幕上选中的文字。直接给出结果，不寒暄，不复述要求，不解释你做了什么。需要格式时只用粗体和列表。"

    /// 指令加上选中的文字
    static func messages(instruction: String, text: String) -> [AIClient.Message] {
        [.system(system), .user("\(instruction)\n\n\(text)")]
    }

    /// 自定义指令模板：{text}（或 {raw}）换成选中的文字；模板里没写的话把文字接在指令后面。
    static func expand(_ template: String, text: String) -> String {
        let trimmed = template.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("{text}") || trimmed.contains("{raw}") {
            return trimmed.replacingOccurrences(of: "{text}", with: text).replacingOccurrences(of: "{raw}", with: text)
        }
        return trimmed.isEmpty ? text : "\(trimmed)\n\n\(text)"
    }
}

/// 交给 AI 卡片处理的一次请求
struct AIRequestSpec: Equatable {
    /// 选中的文字
    var text: String
    /// 打开卡片就执行的指令；nil 表示等用户选指令或者提问
    var action: AIAction? = nil
    /// 自定义插件的指令（已经填好选中的文字）
    var prompt: String? = nil
    /// 卡片上显示的名字（自定义插件的名称）
    var label: String? = nil
}

/// AI 功能的 API Key 存在这台 Mac 的钥匙串里，不跟设置一起同步。
enum AIKeyStore {
    private static let service = (Bundle.main.bundleIdentifier ?? "Pop") + ".ai"
    private static let account = "api-key"

    private static var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func read() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// 保存（空字符串表示删除）。成功返回 true。
    @discardableResult
    static func save(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        SecItemDelete(baseQuery as CFDictionary)
        guard !trimmed.isEmpty else { return true }
        var attributes = baseQuery
        attributes[kSecValueData as String] = Data(trimmed.utf8)
        attributes[kSecAttrLabel as String] = "Pop AI API Key"
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }
}

/// AI 助手和几个直接执行某条指令的快捷功能
struct AIPlugin: PopPlugin {
    let info: PluginInfo
    let action: AIAction?

    static let all = [
        AIPlugin(id: BuiltinPluginID.aiAssistant, name: "AI 助手", symbol: "sparkles",
                 summary: "就选中的文字提问，或者让 AI 润色、总结、解释、翻译（先在「设置 → AI」里填写接口）", action: nil),
        AIPlugin(id: BuiltinPluginID.aiPolish, name: "AI 润色", symbol: "wand.and.rays",
                 summary: "让 AI 改正错别字和不通顺的地方，可以直接替换原文", action: .polish),
        AIPlugin(id: BuiltinPluginID.aiSummarize, name: "AI 总结", symbol: "list.bullet.rectangle",
                 summary: "让 AI 用几条要点总结选中的内容", action: .summarize),
        AIPlugin(id: BuiltinPluginID.aiExplain, name: "AI 解释", symbol: "questionmark.bubble",
                 summary: "让 AI 解释选中的内容，补充背景和术语", action: .explain),
    ]

    init(id: String, name: String, symbol: String, summary: String, action: AIAction?) {
        info = PluginInfo(id: id, name: name, symbol: symbol, summary: summary, accepts: [.text], maxLength: 30_000)
        self.action = action
    }

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text else { return .failure("没有文字") }
        return .ai(AIRequestSpec(text: text, action: action))
    }
}
