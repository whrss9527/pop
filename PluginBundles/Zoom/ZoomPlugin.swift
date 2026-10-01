import AppKit
@testable import Pop

/// 插件包「屏幕放大」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopZoomEntry)
final class ZoomEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [ZoomPlugin()]
    }

    @MainActor static func didLoad(_ host: PluginHost.Registrar) {
        // CI 截图：把示例截图当作屏幕上的内容放大 2 倍，指针停在邮箱和电话那一带；截指针周围的一块
        host.addDemoScene(PluginHost.DemoScene(name: "zoom", after: "scrollCapture", order: 6, show: { demo in
            let screen = demo.screen
            guard let sample = OverlayDemo.sampleScreenshot() else { return nil }
            let size = screen.frame.size
            let sampleRect = CGRect(x: ((size.width - 480) / 2).rounded(), y: (size.height - 410).rounded(), width: 480, height: 300)
            guard let snapshot = ScreenZoom.demoSnapshot(size: size, scale: screen.backingScaleFactor, sample: sample.image, in: sampleRect) else {
                return nil
            }
            // 示例图左上角往右 140、往下 130
            let pointer = CGPoint(x: sampleRect.minX + 140, y: sampleRect.maxY - 130)
            ScreenZoom.shared.showForDemo(snapshot, on: screen, pointer: pointer, scale: ScreenZoom.initialScale)
            return CGRect(x: screen.frame.minX + pointer.x - 320, y: screen.frame.minY + pointer.y - 200, width: 640, height: 400)
        }, hide: {
            ScreenZoom.shared.stop(animated: false)
        }))
    }

    @MainActor static func willUninstall() {
        ScreenZoom.shared.stop(animated: false)
    }
}

struct ZoomPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.zoom, name: String(localized: "屏幕放大"), symbol: "plus.magnifyingglass",
                          summary: String(localized: "演示、录教程时把指针附近放大，看清小字：放大的是那一刻的屏幕画面，挪动指针换地方看，滚轮或 ↑↓ 调倍数，点一下或按 Esc 回去"),
                          accepts: [], hidesOverlay: true)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        let zoom = ScreenZoom.shared
        if zoom.isActive {
            zoom.stop()
            return .done(toast: nil)
        }
        if let failure = await zoom.start(near: context.anchor ?? NSEvent.mouseLocation) {
            return .failure(failure)
        }
        return .done(toast: nil)
    }
}
