import AppKit
@testable import Pop

/// 插件包「表情和符号」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopEmojiSymbolsEntry)
final class EmojiSymbolsEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [EmojiSymbolsPlugin()]
    }

    @MainActor static func didLoad(_ host: PluginHost.Registrar) {
        // CI 截图：搜「笑」，选中第一个
        host.addDemoScene(PluginHost.DemoScene(name: "emojiSymbols", after: "pdfPages", order: 20, delay: 1.4, hold: 0, show: { demo in
            demo.overlay.showCard(EmojiSymbolsView(model: EmojiSymbolsPlugin.demoModel(), onClose: {}), anchor: demo.center)
            return demo.cardRegion
        }))
    }
}

struct EmojiSymbolsPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.emojiSymbols, name: String(localized: "表情和符号"), symbol: "face.smiling",
                          summary: String(localized: "用中文、拼音或者英文搜表情（「笑」「猫」「smile」），也有常用的特殊符号：对勾、箭头、带圈数字、数学符号、单位和货币、希腊字母、上下标；点一下插到正在打字的地方。选中一个词再用，能直接换成表情"),
                          accepts: [], optionalContent: true)

    /// 选中的文字太长就不拿来搜了
    static let maxQueryLength = 20

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        let model = EmojiSymbolsModel(query: Self.query(from: content.text))
        model.keepsSelection = Self.keepsSelection(content.text)
        return .present(PluginPresentation { session in
            model.onInsert = { session.perform(.replace($0)) }
            model.onCopy = { session.perform(.copy($0)) }
            session.showCard(EmojiSymbolsView(model: model, onClose: { session.end() }),
                             keyHandler: { model.handleKey($0) })
        })
    }

    /// 选中的一小段文字（一行、不长）拿来搜；别的不管
    static func query(from text: String?) -> String {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty,
              text.count <= maxQueryLength, !text.contains(where: \.isNewline) else { return "" }
        return text
    }

    /// 选中了一大段文字（没拿来搜）：插入会把它整个换掉，所以只复制
    static func keepsSelection(_ text: String?) -> Bool {
        let selected = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !selected.isEmpty && query(from: text).isEmpty
    }

    /// 演示用：搜「笑」
    @MainActor static func demoModel() -> EmojiSymbolsModel {
        let suite = "PopEmojiSymbolsDemo"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        // 演示的示例内容不翻译
        return EmojiSymbolsModel(query: "笑", defaults: defaults)
    }
}
