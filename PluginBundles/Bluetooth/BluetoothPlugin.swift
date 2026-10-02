import AppKit
@testable import Pop

/// 插件包「蓝牙设备」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopBluetoothEntry)
final class BluetoothEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [BluetoothPlugin()]
    }

    @MainActor static func didLoad(_ host: PluginHost.Registrar) {
        // CI 截图：示例的 AirPods、妙控键盘连着，触控板、头戴耳机没连（不碰 CI 机器的蓝牙）
        host.addDemoScene(PluginHost.DemoScene(name: "bluetooth", after: "pdfPages", order: 21, delay: 1.4, hold: 0, show: { demo in
            let model = BluetoothModel(backend: DemoBluetooth())
            demo.overlay.showCard(BluetoothView(model: model, onOpenSettings: {}, onOpenPrivacy: {}, onClose: {}), anchor: demo.center)
            return demo.cardRegion
        }))
    }
}

struct BluetoothPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.bluetooth, name: String(localized: "蓝牙设备"), symbol: "dot.radiowaves.left.and.right",
                          summary: String(localized: "一下子连接、断开配对过的蓝牙设备：AirPods 和别的耳机、键盘、鼠标、触控板、手柄，连着的键盘鼠标写着电量"),
                          accepts: [])

    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings")
    static let privacyURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth")

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        let model = BluetoothModel(backend: SystemBluetooth())
        return .present(PluginPresentation { session in
            session.showCard(BluetoothView(model: model,
                                           onOpenSettings: {
                                               if let url = Self.settingsURL {
                                                   session.perform(.open(url))
                                               }
                                           },
                                           onOpenPrivacy: {
                                               if let url = Self.privacyURL {
                                                   session.perform(.open(url))
                                               }
                                           },
                                           onClose: { session.end() }))
        })
    }
}

/// 演示用的假设备：AirPods Pro 和妙控键盘连着，触控板、头戴耳机没连；点「连接」一会儿就连上
@MainActor
final class DemoBluetooth: BluetoothBackend {
    // 演示的示例内容不翻译
    private(set) var list: [BluetoothDevices.Device] = [
        BluetoothDevices.Device(id: "a4-c6-f0-11-22-33", name: "AirPods Pro", kind: .airpods, isConnected: true, battery: nil),
        BluetoothDevices.Device(id: "f0-b3-ec-44-55-66", name: "Magic Keyboard", kind: .keyboard, isConnected: true, battery: 72),
        BluetoothDevices.Device(id: "f0-b3-ec-77-88-99", name: "Magic Trackpad", kind: .trackpad, isConnected: false, battery: nil),
        BluetoothDevices.Device(id: "ac-80-0a-12-34-56", name: "WH-1000XM5", kind: .headphones, isConnected: false, battery: nil),
    ]
    var isDenied = false

    func devices() -> [BluetoothDevices.Device] {
        list
    }

    func connect(_ id: String, completion: @escaping @MainActor (Bool) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            MainActor.assumeIsolated {
                self?.set(id, connected: true)
                completion(true)
            }
        }
    }

    func disconnect(_ id: String) -> Bool {
        set(id, connected: false)
        return true
    }

    private func set(_ id: String, connected: Bool) {
        guard let index = list.firstIndex(where: { $0.id == id }) else { return }
        list[index].isConnected = connected
    }
}
