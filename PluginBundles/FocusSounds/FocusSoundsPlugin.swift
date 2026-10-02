import AppKit
@testable import Pop

/// 插件包「白噪音」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopFocusSoundsEntry)
final class FocusSoundsEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [FocusSoundsPlugin()]
    }

    @MainActor static func didLoad(_ host: PluginHost.Registrar) {
        // CI 截图：正在放雨声，定时 30 分钟、还剩 24:12（不出声）
        host.addDemoScene(PluginHost.DemoScene(name: "focusSounds", after: "pdfPages", order: 19, delay: 1.4, hold: 0, show: { demo in
            demo.overlay.showCard(FocusSoundsView(player: FocusSoundsPlugin.demoPlayer(), onClose: {}), anchor: demo.center)
            return demo.cardRegion
        }))
    }

    @MainActor static func willUninstall() {
        FocusSoundPlayer.shared.stop()
    }
}

struct FocusSoundsPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.focusSounds, name: String(localized: "白噪音"), symbol: "headphones",
                          summary: String(localized: "放白噪音、粉红噪音、棕色噪音、雨声或者海浪，盖住周围的说话声，专心做事、午睡时用；可以调音量、定时停止。声音在本机实时生成，关掉卡片也接着放，菜单栏的耳机图标可以暂停、停止"),
                          accepts: [])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        let player = FocusSoundPlayer.shared
        return .present(PluginPresentation { session in
            session.showCard(FocusSoundsView(player: player, onClose: { session.end() }))
        })
    }

    /// 演示用：正在放雨声，定时 30 分钟、已经放了 5 分 48 秒；不出声，菜单栏里也不放图标
    @MainActor static func demoPlayer() -> FocusSoundPlayer {
        let suite = "PopFocusSoundsDemo"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        let start = Date(timeIntervalSince1970: 1_790_908_200)
        var current = start
        let player = FocusSoundPlayer(engine: SilentFocusSoundEngine(), defaults: defaults, now: { current },
                                      usesTimers: false, showsStatusItem: false)
        player.volume = 0.6
        player.setTimer(30)
        player.play(.rain)
        current = start.addingTimeInterval(348)
        player.tick()
        return player
    }
}

/// 不出声的引擎：演示时用
@MainActor
final class SilentFocusSoundEngine: FocusSoundEngine {
    var onFailure: (@MainActor (String) -> Void)?

    func start(sound: FocusSound, volume: Float) throws {}
    func setVolume(_ volume: Float) {}
    func pause() {}
    func stop() {}
}
