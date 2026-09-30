import Foundation

/// 不弹卡片地执行一个功能，把结果换成文字：快捷指令和 Spotlight 里用（见 PopIntents）。
@MainActor
enum HeadlessRunner {
    struct Failure: LocalizedError, Equatable {
        let message: String

        init(_ message: String) {
            self.message = message
        }

        var errorDescription: String? { message }
    }

    /// 能处理文字的功能（快捷指令里可以选的）；只处理文件、图片的，和「全部功能」这种打开列表的不算
    static func textFunctions(in catalog: [PluginInfo]) -> [PluginInfo] {
        let textKinds = Set(ContentKind.allCases).subtracting([.files, .image, .imageFile])
        return catalog.filter { info in
            info.id != BuiltinPluginID.allPlugins && !info.accepts.isDisjoint(with: textKinds)
        }
    }

    /// 用某个功能处理这段文字
    static func run(pluginID: String, text: String, registry: PluginRegistry, settings: AppSettings,
                    services: TranslationServices) async -> Result<String, Failure> {
        guard let plugin = registry.plugin(id: pluginID) else {
            return .failure(Failure("没有「\(pluginID)」这个功能"))
        }
        let content = ContentClassifier.classify(.text(text))
        guard plugin.info.canHandle(content) else {
            return .failure(Failure("「\(plugin.info.name)」处理不了这段文字"))
        }
        let outcome = await plugin.run(content, context: PluginContext(settings: settings, openSettings: {}))
        switch outcome {
        case .done(let toast):
            return .success(toast ?? "")
        case .card(let card):
            return .success(Self.text(of: card))
        case .replace(let replacement):
            return .success(replacement)
        case .translate(let original, let language):
            return await translate(original, language: language, settings: settings, services: services)
        case .ai(let spec):
            return await ai(spec, name: plugin.info.name, settings: settings)
        case .failure(let message):
            return .failure(Failure(message))
        default:
            return .failure(Failure("「\(plugin.info.name)」要在 Pop 的界面里用，快捷指令里拿不到它的结果"))
        }
    }

    /// 结果卡片上最可能要的那段文字：「复制」复制的内容，没有的话依次是正文、Markdown、第一页、每一行
    static func text(of card: ResultCard) -> String {
        if let copy = card.copyText, !copy.isEmpty {
            return copy
        }
        if !card.body.isEmpty {
            return card.body
        }
        if let markdown = card.markdown, !markdown.isEmpty {
            return markdown
        }
        if let tab = card.tabs.first {
            return tab.text
        }
        if !card.rows.isEmpty {
            return card.rows.map { "\($0.label)：\($0.value)" }.joined(separator: "\n")
        }
        return card.detail ?? card.title
    }

    /// 翻译：用快捷指令里选的引擎，没选就用「设置 → 翻译」里的。系统的离线翻译只能在翻译卡片上进行
    static func translate(_ text: String, language: String?, settings: AppSettings, services: TranslationServices,
                          engine: TranslationEngine? = nil, target: String? = nil) async -> Result<String, Failure> {
        let chosen = engine ?? settings.translation.engine
        guard chosen != .system else {
            return .failure(Failure("快捷指令里用不了系统的离线翻译：把「引擎」选成 AI 或 DeepL，或者用快捷指令自带的「翻译文本」"))
        }
        if let reason = services.unavailableReason(chosen) {
            return .failure(Failure(reason))
        }
        let targetCode = target ?? translationTarget(for: text, language: language, settings: settings.translation)
        do {
            var output = ""
            let stream = try await services.translate(chosen, text, targetCode)
            for try await piece in stream {
                output += piece
            }
            let translated = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return translated.isEmpty ? .failure(Failure("\(chosen.title) 没有返回译文")) : .success(translated)
        } catch {
            return .failure(Failure(AIClient.describe(error)))
        }
    }

    /// 原文是中文就译成「中文译为」的语言，否则译成「外文译为」的
    static func translationTarget(for text: String, language: String?, settings: TranslationSettings) -> String {
        let isChinese = language.map { $0.hasPrefix("zh") } ?? ScriptProfile(text).isChinese
        return isChinese ? settings.chineseTarget : settings.foreignTarget
    }

    /// AI 润色、总结这类直接执行的指令，还有「AI 指令」插件：等 AI 答完，返回整段回答
    static func ai(_ spec: AIRequestSpec, name: String, settings: AppSettings) async -> Result<String, Failure> {
        let messages: [AIClient.Message]
        if let prompt = spec.prompt {
            messages = [.system(AIPrompt.system), .user(prompt)]
        } else if let action = spec.action {
            messages = AIPrompt.messages(for: action, text: spec.text, translation: settings.translation)
        } else {
            return .failure(Failure("「\(name)」要在 AI 卡片里提问；快捷指令里可以用「AI 润色」「AI 总结」这类直接执行的功能"))
        }
        do {
            let answer = try await AIService.complete(messages, settings: settings.ai)
            let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? .failure(Failure("AI 没有返回内容")) : .success(trimmed)
        } catch {
            return .failure(Failure(AIClient.describe(error)))
        }
    }
}
