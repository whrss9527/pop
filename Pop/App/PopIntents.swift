import AppIntents
import Foundation

// 快捷指令和 Spotlight 里的 Pop 操作：用 Pop 的功能处理一段文字，结果交给下一个操作。

/// 快捷指令里可以选的 Pop 功能（能处理文字的内置功能和自己的插件）
struct PopFunctionEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Pop 功能"
    static let defaultQuery = PopFunctionQuery()

    let id: String
    let name: String
    let summary: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(summary)")
    }

    init(_ info: PluginInfo) {
        id = info.id
        name = info.name
        summary = info.summary
    }
}

struct PopFunctionQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [PopFunctionEntity] {
        let functions = await PopIntentSupport.functions()
        return identifiers.compactMap { id in functions.first { $0.id == id } }.map(PopFunctionEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [PopFunctionEntity] {
        (await PopIntentSupport.functions()).map(PopFunctionEntity.init)
    }

    @MainActor
    func entities(matching string: String) async throws -> [PopFunctionEntity] {
        (await PopIntentSupport.functions())
            .filter { SearchText.matches(string, keys: SearchText.keys(for: $0.name) + [$0.summary.lowercased()]) }
            .map(PopFunctionEntity.init)
    }
}

/// 快捷指令在 Pop 没打开设置窗口、甚至刚被叫起来时也要能用：设置和插件每次从磁盘读
@MainActor
enum PopIntentSupport {
    static func registry() async -> PluginRegistry {
        await PluginBundles.shared.loadInstalled()
        let registry = PluginRegistry()
        registry.setUserManifests(PluginStore.readAll(in: PluginStore.defaultDirectory).manifests)
        return registry
    }

    static var settings: AppSettings {
        SettingsStore().settings
    }

    static func functions() async -> [PluginInfo] {
        HeadlessRunner.textFunctions(in: await registry().catalog)
    }
}

struct ProcessTextIntent: AppIntent {
    static let title: LocalizedStringResource = "用 Pop 处理文字"
    static let description = IntentDescription("用 Pop 的一个功能处理一段文字，把结果交给下一个操作：计算、格式化 JSON、转换大小写、AI 润色……")

    @Parameter(title: "功能")
    var function: PopFunctionEntity

    @Parameter(title: "文字")
    var text: String

    static var parameterSummary: some ParameterSummary {
        Summary("用 \(\.$function) 处理 \(\.$text)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let settings = PopIntentSupport.settings
        let result = await HeadlessRunner.run(pluginID: function.id, text: text, registry: await PopIntentSupport.registry(),
                                              settings: settings, services: .live(ai: settings.ai))
        return .result(value: try result.get())
    }
}

/// 翻译成哪种语言（和设置里能选的一样）
enum TranslationLanguageOption: String, AppEnum, CaseIterable {
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case english = "en"
    case japanese = "ja"
    case korean = "ko"
    case french = "fr"
    case german = "de"
    case spanish = "es"
    case italian = "it"
    case portuguese = "pt"
    case russian = "ru"

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "语言"
    static let caseDisplayRepresentations: [TranslationLanguageOption: DisplayRepresentation] = [
        .simplifiedChinese: "简体中文",
        .traditionalChinese: "繁體中文",
        .english: "English",
        .japanese: "日本語",
        .korean: "한국어",
        .french: "Français",
        .german: "Deutsch",
        .spanish: "Español",
        .italian: "Italiano",
        .portuguese: "Português",
        .russian: "Русский",
    ]
}

/// 快捷指令里能用的翻译引擎（系统的离线翻译只能在翻译卡片上进行）
enum TranslationEngineOption: String, AppEnum, CaseIterable {
    case ai
    case deepL

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "翻译引擎"
    static let caseDisplayRepresentations: [TranslationEngineOption: DisplayRepresentation] = [
        .ai: "AI 翻译",
        .deepL: "DeepL",
    ]

    var engine: TranslationEngine {
        switch self {
        case .ai: return .ai
        case .deepL: return .deepL
        }
    }
}

struct TranslateTextIntent: AppIntent {
    static let title: LocalizedStringResource = "用 Pop 翻译"
    static let description = IntentDescription("用 AI 或 DeepL 翻译一段文字，把译文交给下一个操作。没选引擎时用「设置 → 翻译」里的默认引擎。")

    @Parameter(title: "文字")
    var text: String

    @Parameter(title: "译成")
    var target: TranslationLanguageOption?

    @Parameter(title: "引擎")
    var engine: TranslationEngineOption?

    static var parameterSummary: some ParameterSummary {
        Summary("用 Pop 翻译 \(\.$text)") {
            \.$target
            \.$engine
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let settings = PopIntentSupport.settings
        let result = await HeadlessRunner.translate(text, language: nil, settings: settings, services: .live(ai: settings.ai),
                                                    engine: engine?.engine, target: target?.rawValue)
        return .result(value: try result.get())
    }
}

struct PopShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: TranslateTextIntent(), phrases: ["用 \(.applicationName) 翻译"],
                    shortTitle: "翻译", systemImageName: "character.bubble")
        AppShortcut(intent: ProcessTextIntent(), phrases: ["用 \(.applicationName) 处理文字"],
                    shortTitle: "处理文字", systemImageName: "circle.circle")
    }
}
