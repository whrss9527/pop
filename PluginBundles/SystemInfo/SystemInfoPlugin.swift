import AppKit
@testable import Pop

/// 插件包「系统信息」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopSystemInfoEntry)
final class SystemInfoEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [SystemInfoPlugin()]
    }

    @MainActor static func didLoad(_ host: PluginHost.Registrar) {
        // CI 截图：一台 14 英寸的 MacBook Pro（CI 的机器是虚拟机，用示例数据）
        host.addDemoScene(PluginHost.DemoScene(name: "systemInfo", after: "pdfPages", order: 13, delay: 1.4, hold: 0, show: { demo in
            let model = SystemInfoModel(report: SystemInfoPlugin.demoReport(), now: { SystemInfoPlugin.demoNow })
            demo.overlay.showCard(SystemInfoView(model: model, onCopy: {}, onClose: {}), anchor: demo.center)
            return demo.cardRegion
        }))
    }
}

struct SystemInfoPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.systemInfo, name: String(localized: "系统信息"), symbol: "info.circle",
                          summary: String(localized: "看这台 Mac 的型号、芯片和核心数、内存、macOS 版本、开机多久、启动磁盘还剩多少、每台显示器的分辨率和刷新率，可以一键复制，报问题、问人时用"),
                          accepts: [])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        let report = SystemInfo.read()
        return .present(PluginPresentation { session in
            let model = SystemInfoModel(report: report)
            session.showCard(SystemInfoView(model: model,
                                            onCopy: { session.perform(.copy(model.text)) },
                                            onClose: { session.end() }))
        })
    }

    /// 演示用：开机三天多的 14 英寸 MacBook Pro，接着一台外接显示器
    static let demoNow = Date(timeIntervalSince1970: 1_790_000_000)

    static func demoReport() -> SystemInfo.Report {
        // 拆成几个有类型的常量：整个写在一个表达式里，新的编译器类型检查会超时
        let memory: UInt64 = 16 * 1_073_741_824
        let uptime: TimeInterval = 3 * 86_400 + 4 * 3_600 + 12 * 60
        let disk = SystemInfo.Disk(name: "Macintosh HD", total: 494_384_795_648, available: 233_876_123_648)
        let builtIn = SystemInfo.Display(name: "Built-in Liquid Retina XDR Display", builtIn: true, points: CGSize(width: 1512, height: 982),
                                         pixels: CGSize(width: 3024, height: 1964), refreshRate: 120)
        let studio = SystemInfo.Display(name: "Studio Display", builtIn: false, points: CGSize(width: 2560, height: 1440),
                                        pixels: CGSize(width: 5120, height: 2880), refreshRate: 60)
        return SystemInfo.Report(modelName: "MacBook Pro (14-inch, 2023)", modelIdentifier: "Mac14,9", chip: "Apple M2 Pro",
                                 cores: 10, performanceCores: 6, efficiencyCores: 4, gpuCores: 16, memory: memory,
                                 osVersion: "15.6.1", osBuild: "24G90", bootTime: demoNow.addingTimeInterval(-uptime),
                                 disk: disk, displays: [builtIn, studio], serial: "C02XK1ABCD12")
    }
}
