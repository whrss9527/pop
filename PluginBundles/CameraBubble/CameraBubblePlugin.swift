import AppKit
@testable import Pop

/// 插件包「摄像头小窗」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopCameraBubbleEntry)
final class CameraBubbleEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [CameraBubblePlugin()]
    }

    @MainActor static func didLoad(_ host: PluginHost.Registrar) {
        // CI 截图：示例人像当作摄像头的画面，小窗在屏幕右下角
        host.addDemoScene(PluginHost.DemoScene(name: "cameraBubble", after: "scrollCapture", order: 2, show: { screen in
            guard let camera = OverlayDemo.sampleCameraFrame() else { return nil }
            return CameraBubble.shared.showForDemo(image: camera, on: screen)
        }, hide: {
            CameraBubble.shared.stop()
        }))
    }

    @MainActor static func willUninstall() {
        CameraBubble.shared.stop()
    }
}

struct CameraBubblePlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.cameraBubble, name: String(localized: "摄像头小窗"), symbol: "person.crop.circle",
                          summary: String(localized: "在屏幕角落用一个圆形小窗显示摄像头画面，录教程、演示时把自己也放进画面；拖动换位置，滚动或双击换大小，右键换形状和摄像头。再用一次关闭"),
                          accepts: [], hidesOverlay: true)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        let bubble = CameraBubble.shared
        if bubble.isActive {
            bubble.stop()
            return .done(toast: nil)
        }
        if let problem = await bubble.start(near: context.anchor ?? NSEvent.mouseLocation) {
            return .failure(problem)
        }
        return .done(toast: nil)
    }
}
