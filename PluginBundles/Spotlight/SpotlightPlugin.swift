import AppKit
@testable import Pop

/// 插件包「聚光灯」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopSpotlightEntry)
final class SpotlightEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [SpotlightPlugin()]
    }

    @MainActor static func didLoad(_ host: PluginHost.Registrar) {
        // CI 截图：贴一张示例截图当作屏幕上的内容，聚光灯照着里面的邮箱和电话
        host.addDemoScene(PluginHost.DemoScene(name: "spotlight", after: "scrollCapture", order: 5, show: { demo in
            let screen = demo.screen
            guard let capture = OverlayDemo.sampleScreenshot() else { return nil }
            let visible = screen.visibleFrame
            let pinCenter = CGPoint(x: visible.midX.rounded(), y: (visible.maxY - 260).rounded())
            PinBoard.shared.pin(image: NSImage(cgImage: capture.image, size: CGSize(width: 480, height: 300)), around: pinCenter)
            let pinFrame = CGRect(x: pinCenter.x - 240, y: pinCenter.y - 150, width: 480, height: 300)
            // 示例图左上角往右 140、往下 130 那一带是邮箱和电话
            Spotlight.shared.showForDemo(at: CGPoint(x: pinFrame.minX + 140, y: pinFrame.maxY - 130))
            return pinFrame.insetBy(dx: -80, dy: -60)
        }, hide: {
            Spotlight.shared.stop()
            PinBoard.shared.closeAll()
        }))
    }

    @MainActor static func willUninstall() {
        Spotlight.shared.stop()
    }
}

struct SpotlightPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.spotlight, name: String(localized: "聚光灯"), symbol: "flashlight.on.fill",
                          summary: String(localized: "演示、录教程时把屏幕压暗，只亮着指针周围一圈，跟着指针走，让大家看你指的地方；录屏时一起录进去，再用一次关闭"),
                          accepts: [])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        let spotlight = Spotlight.shared
        if spotlight.isActive {
            spotlight.stop()
            return .done(toast: String(localized: "关掉了聚光灯"))
        }
        spotlight.start()
        return .done(toast: String(localized: "打开了聚光灯，再用一次就关闭"))
    }
}
