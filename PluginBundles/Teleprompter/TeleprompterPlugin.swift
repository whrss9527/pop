import AppKit
@testable import Pop

/// 插件包「提词器」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopTeleprompterEntry)
final class TeleprompterEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [TeleprompterPlugin()]
    }

    @MainActor static func didLoad(_ host: PluginHost.Registrar) {
        // 对着摄像头读稿时提词器在屏幕上方：Pop 录屏时不把它录进去
        host.excludeFromRecording {
            Teleprompter.shared.windowNumber.map { [$0] } ?? []
        }
        // CI 截图：屏幕上方一段示例稿子，停在开头
        host.addDemoScene(PluginHost.DemoScene(name: "teleprompter", after: "scrollCapture", order: 4, show: { screen in
            let script = "大家好，今天花三分钟介绍一下 Pop 的录屏。\n长按右键弹出圆盘，选「录屏」，拖出要录的区域。\n勾上「显示按下的键」，按的快捷键会出现在画面下方。\n录完可以直接转成 GIF，发给同事看。"
            return Teleprompter.shared.showForDemo(script, on: screen)
        }, hide: {
            Teleprompter.shared.close()
        }))
    }

    @MainActor static func willUninstall() {
        Teleprompter.shared.close()
    }
}

struct TeleprompterPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.teleprompter, name: String(localized: "提词器"), symbol: "text.aligncenter",
                          summary: String(localized: "把选中的稿子放进屏幕上方的提词器，按设好的速度慢慢往上滚，对着摄像头读；空格暂停，↑↓ 调速度，录屏时不会录进去"),
                          accepts: [.text], minLength: 10, maxLength: 100_000)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return .failure(String(localized: "没有文字"))
        }
        Teleprompter.shared.show(text, near: context.anchor ?? NSEvent.mouseLocation)
        return .done(toast: nil)
    }
}
