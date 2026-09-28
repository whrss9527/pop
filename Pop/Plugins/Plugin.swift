import Foundation

/// 插件的静态描述，设置界面、圆盘和分发规则都只依赖它。
struct PluginInfo: Identifiable, Hashable {
    let id: String
    let name: String
    /// SF Symbol 名称
    let symbol: String
    let summary: String
    /// 能处理的内容类型；为空表示不需要选中内容（比如「打开设置」）。
    let accepts: Set<ContentKind>

    func canHandle(_ content: ClassifiedContent) -> Bool {
        accepts.isEmpty || !accepts.isDisjoint(with: content.kinds)
    }
}

/// 结果卡片的内容。
struct ResultCard: Equatable {
    var title: String
    var body: String
    var detail: String?
    var monospaced = false
    /// 「复制」按钮复制的内容，为空时不显示按钮
    var copyText: String?
}

enum PluginOutcome: Equatable {
    /// 已经完成（比如打开了网页），可以带一句轻提示
    case done(toast: String?)
    /// 展示结果卡片
    case card(ResultCard)
    /// 交给翻译卡片处理
    case translate(text: String, language: String?)
    case failure(String)
}

struct PluginContext {
    var settings: AppSettings
    var openSettings: @MainActor () -> Void
}

/// 所有功能都实现这个协议。以后的脚本插件、网页插件只是换一种方式提供 PopPlugin。
protocol PopPlugin {
    var info: PluginInfo { get }
    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome
}

@MainActor
final class PluginRegistry {
    let plugins: [any PopPlugin]

    init(plugins: [any PopPlugin]? = nil) {
        self.plugins = plugins ?? BuiltinPlugins.make()
    }

    var catalog: [PluginInfo] { plugins.map(\.info) }

    func plugin(id: String) -> (any PopPlugin)? {
        plugins.first { $0.info.id == id }
    }

    func info(id: String) -> PluginInfo? {
        plugin(id: id)?.info
    }
}

/// 决定一次唤起是直接执行某个插件，还是弹出圆盘。
enum Router {
    enum Decision: Equatable {
        case direct(pluginID: String)
        case ring
    }

    static func decide(_ content: ClassifiedContent, settings: AppSettings, catalog: [PluginInfo]) -> Decision {
        guard !content.isEmpty else { return .ring }
        for rule in settings.rules where rule.enabled {
            guard let pluginID = rule.pluginID,
                  content.kinds.contains(rule.condition.kind),
                  settings.isInstalled(pluginID),
                  let info = catalog.first(where: { $0.id == pluginID }),
                  info.canHandle(content) else { continue }
            return .direct(pluginID: pluginID)
        }
        return .ring
    }
}
