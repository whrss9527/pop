import AppKit
@testable import Pop

/// 插件包「屏幕标尺」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopScreenRulerEntry)
final class ScreenRulerEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [RulerPlugin()]
    }
}

struct RulerPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.ruler, name: String(localized: "屏幕标尺"), symbol: "ruler",
                          summary: String(localized: "定格屏幕，量出指针处到上下左右边缘的距离，拖动量一块区域的宽高；单击复制尺寸"),
                          accepts: [], hidesOverlay: true)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        if let problem = await ScreenRuler.start() {
            return .failure(problem)
        }
        return .done(toast: nil)
    }
}
