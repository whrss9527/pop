import AppKit
@testable import Pop

/// 插件包「电池信息」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopBatteryInfoEntry)
final class BatteryInfoEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [BatteryInfoPlugin()]
    }

    @MainActor static func didLoad(_ host: PluginHost.Registrar) {
        // CI 截图：一块用了一年多的电池在充电（CI 的机器没有电池，用示例数据）
        host.addDemoScene(PluginHost.DemoScene(name: "batteryInfo", after: "pdfPages", order: 11, delay: 1.4, hold: 0, show: { demo in
            let model = BatteryInfoModel(report: BatteryInfoPlugin.demoReport(), read: { nil })
            demo.overlay.showCard(BatteryInfoView(model: model, onCopy: {}, onOpenSettings: {}, onClose: {}), anchor: demo.center)
            return demo.cardRegion
        }))
    }
}

struct BatteryInfoPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.batteryInfo, name: String(localized: "电池信息"), symbol: "battery.100",
                          summary: String(localized: "看笔记本电池的电量、最大容量（健康度）、循环次数、状况、温度，正在充电或者耗电的功率、充电器多少瓦，还要多久充满或者用完"),
                          accepts: [])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let report = await runInBackground({ BatteryReader.read() }) else {
            return .failure(String(localized: "这台 Mac 没有电池"))
        }
        return .present(PluginPresentation { session in
            let model = BatteryInfoModel(report: report)
            session.showCard(BatteryInfoView(model: model,
                                             onCopy: { session.perform(.copy(model.text)) },
                                             onOpenSettings: {
                                                 if let url = URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension") {
                                                     NSWorkspace.shared.open(url)
                                                 }
                                                 session.end()
                                             },
                                             onClose: { session.end() }))
        })
    }

    /// 演示用：用了一年多的电池，接着 96 瓦的充电器在充
    static func demoReport() -> BatteryReader.Report {
        BatteryReader.Report(percent: 76, isCharging: true, externalConnected: true, fullyCharged: false, cycleCount: 286, designCycles: 1000,
                             designCapacity: 6075, fullCapacity: 5530, temperature: 31.2, voltage: 12.61, amperage: 3.42,
                             minutesToFull: 38, minutesToEmpty: nil, adapterWatts: 96, adapterName: "96W USB-C Power Adapter", condition: nil)
    }
}
