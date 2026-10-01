@testable import Pop

/// 测试用的完整功能列表：Pop 自带的功能，加上插件包提供的功能（PluginBundles/ 下的代码也编进了单元测试）
enum TestCatalog {
    /// 编进测试的插件包的入口
    static let bundles: [PopPluginBundle.Type] = [ScreenPenEntry.self, CameraBubbleEntry.self, PointerHighlightEntry.self, TeleprompterEntry.self]

    static func plugins() -> [any PopPlugin] {
        BuiltinPlugins.sorted(BuiltinPlugins.make() + bundles.flatMap { $0.makePlugins() })
    }

    static func infos() -> [PluginInfo] {
        plugins().map(\.info)
    }
}
