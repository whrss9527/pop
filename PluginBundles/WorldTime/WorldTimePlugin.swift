import AppKit
@testable import Pop

/// 插件包「时区换算」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopWorldTimeEntry)
final class WorldTimeEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [WorldTimePlugin()]
    }

    @MainActor static func didLoad(_ host: PluginHost.Registrar) {
        // CI 截图：在北京选中「3pm PST」，看各地那时是几点
        host.addDemoScene(PluginHost.DemoScene(name: "worldTime", after: "pdfPages", order: 17, delay: 1.4, hold: 0, show: { demo in
            demo.overlay.showCard(WorldTimeView(model: WorldTimePlugin.demoModel(), onCopy: {}, onClose: {}), anchor: demo.center)
            return demo.cardRegion
        }))
    }
}

struct WorldTimePlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.worldTime, name: String(localized: "时区换算"), symbol: "globe.asia.australia",
                          summary: String(localized: "选中「3pm PST」「北京时间晚上 9 点」这样的时间，换算成常用的几个城市的时间；拖动滑块看别的时刻，找大家都在上班的时间开会。什么都不选时看各地现在几点"),
                          accepts: [], optionalContent: true)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        let model = WorldTimeModel(text: content.text)
        return .present(PluginPresentation { session in
            session.showCard(WorldTimeView(model: model,
                                           onCopy: { session.perform(.copy(model.copyText)) },
                                           onClose: { session.end() }))
        })
    }

    /// 演示用：北京时间 10 月 2 日上午 10:30
    static let demoNow = Date(timeIntervalSince1970: 1_790_908_200)

    /// 演示用：在北京选中「3pm PST」，列着伦敦、纽约、东京
    @MainActor static func demoModel() -> WorldTimeModel {
        WorldTimeModel(text: "3pm PST", now: { demoNow }, local: TimeZone(identifier: "Asia/Shanghai") ?? .current,
                       cityIDs: ["london", "newYork", "tokyo"], usesTimers: false)
    }
}
