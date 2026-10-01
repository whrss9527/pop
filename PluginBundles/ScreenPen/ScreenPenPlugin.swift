import AppKit
@testable import Pop

/// 插件包「屏幕画笔」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopScreenPenEntry)
final class ScreenPenEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [ScreenPenPlugin()]
    }

    @MainActor static func didLoad(_ host: PluginHost.Registrar) {
        // CI 截图：贴一张示例截图当作屏幕上的内容，荧光笔划出邮箱、画笔在手机号下面画波浪线、椭圆圈出按钮、箭头指过去；
        // 截图区域包括屏幕上方的工具栏
        host.addDemoScene(PluginHost.DemoScene(name: "screenPen", after: "scrollCapture", order: 1, show: { demo in
            let screen = demo.screen
            guard let capture = OverlayDemo.sampleScreenshot() else { return nil }
            let visible = screen.visibleFrame
            let pinCenter = CGPoint(x: visible.midX.rounded(), y: (visible.maxY - 260).rounded())
            PinBoard.shared.pin(image: NSImage(cgImage: capture.image, size: CGSize(width: 480, height: 300)), around: pinCenter)
            let pinFrame = CGRect(x: pinCenter.x - 240, y: pinCenter.y - 150, width: 480, height: 300)
            // 示例图上的点（左上角为原点）换成画布上的点
            let originX = pinFrame.minX - screen.frame.minX
            let originY = screen.frame.maxY - pinFrame.maxY
            let onScreen = { (x: CGFloat, y: CGFloat) -> CGPoint in CGPoint(x: originX + x, y: originY + y) }
            let toolbar = ScreenPen.shared.showForDemo(on: screen, strokes: [
                (.highlighter, .yellow, [onScreen(62, 111), onScreen(224, 111)]),
                (.pen, .blue, [onScreen(64, 148), onScreen(88, 152), onScreen(112, 146), onScreen(136, 152),
                               onScreen(160, 146), onScreen(184, 151)]),
                (.ellipse, .red, [onScreen(286, 192), onScreen(430, 252)]),
                (.arrow, .red, [onScreen(150, 262), onScreen(280, 232)]),
            ])
            return pinFrame.union(toolbar ?? pinFrame)
        }, hide: {
            ScreenPen.shared.stop()
            PinBoard.shared.closeAll()
        }))
    }

    @MainActor static func willUninstall() {
        ScreenPen.shared.stop()
    }
}

struct ScreenPenPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.screenPen, name: String(localized: "屏幕画笔"), symbol: "scribble.variable",
                          summary: String(localized: "演示、录教程时直接在屏幕上画：画笔、荧光笔、箭头、方框、椭圆，笔迹可以几秒后自动消失，也可以留着去操作下面的窗口，录屏时一起录进去；Esc 或再用一次结束"),
                          accepts: [], hidesOverlay: true)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        let pen = ScreenPen.shared
        if pen.isActive {
            pen.stop()
        } else {
            pen.start(near: context.anchor ?? NSEvent.mouseLocation)
        }
        return .done(toast: nil)
    }
}
