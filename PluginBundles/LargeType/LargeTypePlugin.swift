import AppKit
@testable import Pop

/// 插件包「大字显示」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopLargeTypeEntry)
final class LargeTypeEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [LargeTypePlugin()]
    }
}

struct LargeTypePlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.largeType, name: String(localized: "大字显示"), symbol: "textformat.size",
                          summary: String(localized: "把选中的文字铺满整个屏幕，给别人看电话号码、Wi-Fi 密码、取件码都方便；点一下或按任意键关闭"),
                          accepts: [.text], maxLength: LargeType.maxLength, hidesOverlay: true)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return .done(toast: nil) }
        LargeTypeWindow.show(text, near: context.anchor ?? NSEvent.mouseLocation)
        return .done(toast: nil)
    }
}
