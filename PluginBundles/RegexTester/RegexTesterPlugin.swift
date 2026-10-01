import AppKit
@testable import Pop

/// 插件包「正则测试」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopRegexTesterEntry)
final class RegexTesterEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [RegexTestPlugin()]
    }

    @MainActor static func didLoad(_ host: PluginHost.Registrar) {
        // CI 截图：用「日期」表达式找出日期，替换成日/月/年
        host.addDemoScene(PluginHost.DemoScene(name: "regex", after: "toMarkdown", delay: 1.4, hold: 0, show: { demo in
            let notes = "0.10.0 发布于 2026-09-29，0.9.0 发布于 2026-09-28。\n下一版计划在 2026-10-08 之前发布。"
            let regex = RegexTesterModel(text: notes, pattern: RegexTester.presets.first { $0.title == String(localized: "日期") }?.pattern ?? "")
            regex.replacement = "$3/$2/$1"
            demo.overlay.showCard(RegexTesterView(model: regex, canReplace: true, onAction: { _ in }, onClose: {}), anchor: demo.center)
            return demo.cardRegion
        }))
    }
}

struct RegexTestPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.regexTest, name: String(localized: "正则测试"), symbol: "asterisk.circle",
                          summary: String(localized: "在选中的文字里试正则表达式：实时标出每处匹配、列出分组，也可以试替换"),
                          accepts: [.text], maxLength: 200_000)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text else { return .failure(String(localized: "没有文字")) }
        return .present(PluginPresentation { session in Self.present(text, in: session) })
    }

    /// 正则测试卡片：输入表达式，实时看匹配和替换结果
    @MainActor static func present(_ text: String, in session: PluginSession) {
        let model = RegexTesterModel(text: text)
        session.showCard(RegexTesterView(model: model, canReplace: session.canReplace,
                                         onAction: { action in session.perform(action) },
                                         onClose: { session.end() }))
    }
}
