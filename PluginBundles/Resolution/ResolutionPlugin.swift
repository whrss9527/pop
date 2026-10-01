import AppKit
@testable import Pop

/// 插件包「分辨率」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopResolutionEntry)
final class ResolutionEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [ResolutionPlugin()]
    }

    @MainActor static func didLoad(_ host: PluginHost.Registrar) {
        // CI 截图：MacBook Pro 接着一台 Studio Display，外接的刚换成 2560 × 1440，等着确认（CI 的机器只有一台虚拟显示器，用示例数据）
        host.addDemoScene(PluginHost.DemoScene(name: "resolution", after: "pdfPages", order: 15, delay: 1.4, hold: 0, show: { demo in
            let model = ResolutionModel(backend: ResolutionPlugin.demoBackend(), selecting: ResolutionPlugin.demoStudioDisplay, usesTimers: false)
            if let mode = model.choices.first(where: { $0.mode.width == 2560 })?.mode {
                model.choose(mode)
            }
            demo.overlay.showCard(ResolutionView(model: model, onOpenSettings: {}, onDone: {}, onClose: {}), anchor: demo.center)
            return demo.cardRegion
        }))
    }
}

struct ResolutionPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.resolution, name: String(localized: "分辨率"), symbol: "display",
                          summary: String(localized: "换显示器的分辨率（看起来像多大）和刷新率，把哪台设成主显示器；外接显示器换了以后 15 秒内不点「保留」就换回原来的"),
                          accepts: [])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        let model = ResolutionModel(selecting: DisplayModes.displayUnderPointer())
        guard !model.displays.isEmpty else { return .failure(String(localized: "没有找到显示器")) }
        return .present(PluginPresentation { session in
            session.showCard(ResolutionView(model: model,
                                            onOpenSettings: {
                                                model.keep()
                                                if let url = URL(string: "x-apple.systempreferences:com.apple.Displays-Settings.extension") {
                                                    NSWorkspace.shared.open(url)
                                                }
                                                session.end()
                                            },
                                            onDone: {
                                                model.keep()
                                                session.end()
                                            },
                                            onClose: { session.end() }))
        })
    }

    // MARK: - 演示

    static let demoBuiltIn: CGDirectDisplayID = 1
    static let demoStudioDisplay: CGDirectDisplayID = 2

    /// 演示用：14 英寸 MacBook Pro（ProMotion）是主显示器，右边一台 Studio Display；换模式、设主显示器都只改这份示例数据
    @MainActor static func demoBackend() -> ResolutionModel.Backend {
        var displays = demoDisplays()
        return ResolutionModel.Backend(displays: { displays }, apply: { mode, id in
            guard let index = displays.firstIndex(where: { $0.id == id }) else { return false }
            displays[index].current = mode
            return true
        }, makeMain: { id, _ in
            guard let origin = displays.first(where: { $0.id == id })?.bounds.origin else { return false }
            for index in displays.indices {
                displays[index].isMain = displays[index].id == id
                displays[index].bounds = displays[index].bounds.offsetBy(dx: -origin.x, dy: -origin.y)
            }
            return true
        })
    }

    static func demoDisplays() -> [DisplayModes.Display] {
        func mode(_ id: Int32, _ width: Int, _ height: Int, scale: Int = 2, rate: Double, isDefault: Bool = false) -> DisplayModes.Mode {
            DisplayModes.Mode(ioID: id, width: width, height: height, pixelWidth: width * scale, pixelHeight: height * scale, refreshRate: rate,
                              isDefault: isDefault)
        }
        var builtInModes: [DisplayModes.Mode] = []
        for (index, size) in [(1147, 745), (1352, 878), (1512, 982), (1728, 1117), (1800, 1169)].enumerated() {
            for (offset, rate) in [120.0, 60, 50, 48].enumerated() {
                builtInModes.append(mode(Int32(100 + index * 10 + offset), size.0, size.1, rate: rate, isDefault: size.0 == 1512))
            }
        }
        builtInModes.append(mode(200, 1512, 982, scale: 1, rate: 120))
        let studioModes = [
            mode(300, 1280, 720, scale: 1, rate: 60),
            mode(301, 1600, 900, rate: 60),
            mode(302, 2048, 1152, rate: 60),
            mode(303, 2560, 1440, rate: 60, isDefault: true),
            mode(304, 2880, 1620, rate: 60),
            mode(305, 5120, 2880, scale: 1, rate: 60),
        ]
        return [
            DisplayModes.Display(id: demoBuiltIn, name: String(localized: "内建显示器"), isBuiltIn: true, isMain: true,
                                 bounds: CGRect(x: 0, y: 0, width: 1512, height: 982),
                                 current: builtInModes.first(where: { $0.width == 1512 && $0.isHiDPI && $0.refreshRate == 120 }), modes: builtInModes),
            DisplayModes.Display(id: demoStudioDisplay, name: "Studio Display", isBuiltIn: false, isMain: false,
                                 bounds: CGRect(x: 1512, y: -300, width: 2048, height: 1152),
                                 current: studioModes[2], modes: studioModes),
        ]
    }
}
