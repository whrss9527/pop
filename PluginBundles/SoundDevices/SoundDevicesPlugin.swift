import AppKit
import CoreAudio
@testable import Pop

/// 插件包「声音设备」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopSoundDevicesEntry)
final class SoundDevicesEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [SoundDevicesPlugin()]
    }

    @MainActor static func didLoad(_ host: PluginHost.Registrar) {
        // CI 截图：AirPods Pro 在放声音，旁边还有扬声器和显示器（CI 的机器没有这些设备，用示例数据）
        host.addDemoScene(PluginHost.DemoScene(name: "soundDevices", after: "pdfPages", order: 14, delay: 1.4, hold: 0, show: { demo in
            let model = SoundDevicesModel(backend: SoundDevicesPlugin.demoBackend())
            demo.overlay.showCard(SoundDevicesView(model: model, onOpenSettings: {}, onClose: {}), anchor: demo.center)
            return demo.cardRegion
        }))
    }
}

struct SoundDevicesPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.soundDevices, name: String(localized: "声音设备"), symbol: "hifispeaker",
                          summary: String(localized: "一下子换声音从哪出、用哪个麦克风：扬声器、耳机、AirPods、显示器、AirPlay，还能调音量、静音"),
                          accepts: [])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        let model = SoundDevicesModel()
        guard !model.isEmpty else { return .failure(String(localized: "没有找到声音设备")) }
        return .present(PluginPresentation { session in
            session.showCard(SoundDevicesView(model: model,
                                              onOpenSettings: {
                                                  if let url = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension") {
                                                      NSWorkspace.shared.open(url)
                                                  }
                                                  session.end()
                                              },
                                              onClose: { session.end() }))
        })
    }

    /// 演示用：扬声器、AirPods Pro（正在用）、外接显示器，麦克风两个
    @MainActor static func demoBackend() -> SoundDevicesModel.Backend {
        let devices = [
            SoundDevices.Device(id: 1, uid: "BuiltInSpeakerDevice", name: String(localized: "MacBook Pro 扬声器"), transport: kAudioDeviceTransportTypeBuiltIn,
                                outputChannels: 2, inputChannels: 0),
            SoundDevices.Device(id: 2, uid: "AA-BB-CC-DD-EE-01:output", name: "AirPods Pro", transport: kAudioDeviceTransportTypeBluetooth,
                                outputChannels: 2, inputChannels: 1),
            SoundDevices.Device(id: 3, uid: "LG-HDR-4K", name: "LG HDR 4K", transport: kAudioDeviceTransportTypeDisplayPort,
                                outputChannels: 2, inputChannels: 0),
            SoundDevices.Device(id: 4, uid: "BuiltInMicrophoneDevice", name: String(localized: "MacBook Pro 麦克风"), transport: kAudioDeviceTransportTypeBuiltIn,
                                outputChannels: 0, inputChannels: 1),
        ]
        return SoundDevicesModel.Backend(devices: { devices }, defaultDevice: { $0 ? 4 : 2 }, setDefault: { _, _ in true },
                                         volume: { _, input in input ? 0.75 : 0.62 }, setVolume: { _, _, _ in },
                                         isMuted: { _, _ in false }, setMuted: { _, _, _ in })
    }
}
