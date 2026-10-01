import AppKit
@testable import Pop

/// 插件包「随机生成」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopRandomEntry)
final class RandomEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [RandomPlugin()]
    }
}

struct RandomPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.random, name: String(localized: "随机生成"), symbol: "dice",
                          summary: String(localized: "生成 UUID、密码和随机数字，可以直接粘贴到当前输入框"), accepts: [])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        .card(ResultCard(title: String(localized: "随机生成"), rows: RandomGenerator.rows(), rowsReplaceable: true))
    }
}
