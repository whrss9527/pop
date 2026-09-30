import Foundation

struct VocabularyPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.vocabulary, name: String(localized: "生词本"), symbol: "book.closed",
                          summary: String(localized: "翻译卡片上加进来的单词和释义：搜索、朗读、一个个复习，也能导出成表格或者 Anki 能导入的文件"),
                          accepts: [])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        .showVocabulary
    }
}
