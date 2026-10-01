import AppKit
@testable import Pop

/// 插件包「磁盘测速」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopDiskSpeedEntry)
final class DiskSpeedEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [DiskSpeedPlugin()]
    }

    @MainActor static func didLoad(_ host: PluginHost.Registrar) {
        // CI 截图：测完的外接固态硬盘（示例数据，不真的写 CI 机器的磁盘）
        host.addDemoScene(PluginHost.DemoScene(name: "diskSpeed", after: "pdfPages", order: 16, delay: 1.4, hold: 0, show: { demo in
            let model = DiskSpeedModel(volumes: DiskSpeedPlugin.demoVolumes(), selecting: DiskSpeedPlugin.demoVolumes().last?.url)
            model.showResult(write: 921_400_000, read: 1_012_800_000)
            demo.overlay.showCard(DiskSpeedView(model: model, onCopy: { _ in }, onClose: {}), anchor: demo.center)
            return demo.cardRegion
        }))
    }
}

struct DiskSpeedPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.diskSpeed, name: String(localized: "磁盘测速"), symbol: "speedometer",
                          summary: String(localized: "测硬盘、U 盘、移动固态硬盘连续写入和读取有多快：选中磁盘里的文件或文件夹就测那块盘，什么都不选时测启动磁盘"),
                          accepts: [], optionalContent: true)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        // 读各块盘的大小要问一遍每块盘，网络盘可能很慢：放到后台
        let file = content.files.first
        let (volumes, selected) = await runInBackground { () -> ([DiskSpeed.Volume], URL?) in
            // 选中了文件或文件夹：先选它所在的那块盘
            (DiskSpeed.volumes(), file.flatMap(DiskSpeed.volume(containing:))?.url)
        }
        guard !volumes.isEmpty else { return .failure(String(localized: "没有找到能测的磁盘")) }
        let model = DiskSpeedModel(volumes: volumes, selecting: selected)
        return .present(PluginPresentation { session in
            session.showCard(DiskSpeedView(model: model,
                                           onCopy: { session.perform(.copy($0)) },
                                           onClose: { session.end() }))
        })
    }

    /// 演示用：启动磁盘和一块外接的移动固态硬盘
    static func demoVolumes() -> [DiskSpeed.Volume] {
        [
            DiskSpeed.Volume(url: URL(fileURLWithPath: "/"), name: "Macintosh HD", format: "APFS", isInternal: true, isRemovable: false, isLocal: true,
                             total: 994_662_584_320, available: 312_456_789_012),
            DiskSpeed.Volume(url: URL(fileURLWithPath: "/Volumes/T7 Shield"), name: "T7 Shield", format: "ExFAT", isInternal: false, isRemovable: true,
                             isLocal: true, total: 2_000_381_014_016, available: 1_204_934_567_890),
        ]
    }
}
