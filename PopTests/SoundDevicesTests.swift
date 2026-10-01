import CoreAudio
import XCTest
@testable import Pop

final class SoundDevicesTests: XCTestCase {
    private func device(_ id: AudioObjectID, _ name: String, _ transport: UInt32, outputs: Int = 2, inputs: Int = 0, uid: String? = nil) -> SoundDevices.Device {
        SoundDevices.Device(id: id, uid: uid ?? "device-\(id)", name: name, transport: transport, outputChannels: outputs, inputChannels: inputs)
    }

    func testKindsSymbolsAndFiltering() {
        XCTAssertEqual(SoundDevices.kind(of: kAudioDeviceTransportTypeBuiltIn), .builtIn)
        XCTAssertEqual(SoundDevices.kind(of: kAudioDeviceTransportTypeBluetooth), .bluetooth)
        XCTAssertEqual(SoundDevices.kind(of: kAudioDeviceTransportTypeBluetoothLE), .bluetooth)
        XCTAssertEqual(SoundDevices.kind(of: kAudioDeviceTransportTypeUSB), .usb)
        XCTAssertEqual(SoundDevices.kind(of: kAudioDeviceTransportTypeHDMI), .hdmi)
        XCTAssertEqual(SoundDevices.kind(of: kAudioDeviceTransportTypeDisplayPort), .displayPort)
        XCTAssertEqual(SoundDevices.kind(of: kAudioDeviceTransportTypeAirPlay), .airPlay)
        XCTAssertEqual(SoundDevices.kind(of: kAudioDeviceTransportTypeVirtual), .virtual)
        XCTAssertEqual(SoundDevices.kind(of: kAudioDeviceTransportTypeAggregate), .aggregate)
        XCTAssertEqual(SoundDevices.kind(of: 0), .other)

        let speakers = device(1, "MacBook Pro 扬声器", kAudioDeviceTransportTypeBuiltIn)
        let microphone = device(2, "MacBook Pro 麦克风", kAudioDeviceTransportTypeBuiltIn, outputs: 0, inputs: 1)
        let airPods = device(3, "张三的 AirPods Pro", kAudioDeviceTransportTypeBluetooth, inputs: 1)
        let headphones = device(4, "WH-1000XM5", kAudioDeviceTransportTypeBluetooth)
        let display = device(5, "LG HDR 4K", kAudioDeviceTransportTypeDisplayPort)
        let tv = device(6, "客厅电视", kAudioDeviceTransportTypeHDMI)
        let airPlay = device(7, "客厅 HomePod", kAudioDeviceTransportTypeAirPlay)
        XCTAssertEqual(SoundDevices.symbol(for: speakers, input: false), "speaker.wave.2")
        XCTAssertEqual(SoundDevices.symbol(for: microphone, input: true), "mic")
        XCTAssertEqual(SoundDevices.symbol(for: airPods, input: false), "airpodspro")
        XCTAssertEqual(SoundDevices.symbol(for: airPods, input: true), "airpodspro")
        XCTAssertEqual(SoundDevices.symbol(for: headphones, input: false), "headphones")
        XCTAssertEqual(SoundDevices.symbol(for: display, input: false), "display")
        XCTAssertEqual(SoundDevices.symbol(for: tv, input: false), "tv")
        XCTAssertEqual(SoundDevices.symbol(for: airPlay, input: false), "airplayaudio")
        XCTAssertNil(SoundDevices.transportTitle(.builtIn))
        XCTAssertEqual(SoundDevices.transportTitle(.bluetooth), "蓝牙")
        XCTAssertEqual(SoundDevices.transportTitle(.hdmi), "HDMI")

        // 系统给某个 App 临时建的聚合设备、没有声道的都不列
        let temporary = device(8, "CADefaultDeviceAggregate-1234-5", kAudioDeviceTransportTypeAggregate, uid: "CADefaultDeviceAggregate-1234-5")
        let silent = device(9, "空设备", kAudioDeviceTransportTypeVirtual, outputs: 0, inputs: 0)
        XCTAssertEqual(SoundDevices.listed([speakers, temporary, silent, microphone]).map(\.id), [1, 2])
    }

    /// 假的声音设备：记着默认设备、音量和静音
    private final class FakeSystem {
        var devices: [SoundDevices.Device]
        var output: AudioObjectID = 1
        var input: AudioObjectID = 2
        var volumes: [AudioObjectID: Float] = [1: 0.5, 2: 0.8, 3: 0.3]
        var muted: [AudioObjectID: Bool] = [1: false, 3: true]
        var refuses: Set<AudioObjectID> = []

        init(devices: [SoundDevices.Device]) {
            self.devices = devices
        }

        var backend: SoundDevicesModel.Backend {
            SoundDevicesModel.Backend(
                devices: { self.devices },
                defaultDevice: { $0 ? self.input : self.output },
                setDefault: { id, input in
                    guard !self.refuses.contains(id) else { return false }
                    if input { self.input = id } else { self.output = id }
                    return true
                },
                volume: { id, _ in self.volumes[id] },
                setVolume: { value, id, _ in self.volumes[id] = value },
                isMuted: { id, _ in self.muted[id] },
                setMuted: { value, id, _ in self.muted[id] = value })
        }
    }

    @MainActor
    func testCardSwitchesDevicesAndVolume() {
        let system = FakeSystem(devices: [
            device(1, "MacBook Pro 扬声器", kAudioDeviceTransportTypeBuiltIn),
            device(2, "MacBook Pro 麦克风", kAudioDeviceTransportTypeBuiltIn, outputs: 0, inputs: 1),
            device(3, "AirPods Pro", kAudioDeviceTransportTypeBluetooth, inputs: 1),
            device(4, "LG HDR 4K", kAudioDeviceTransportTypeDisplayPort),
        ])
        let model = SoundDevicesModel(backend: system.backend)
        XCTAssertFalse(model.isEmpty)
        // AirPods 既能出声也能收声，两边都有
        XCTAssertEqual(model.outputs.map(\.id), [1, 3, 4])
        XCTAssertEqual(model.inputs.map(\.id), [2, 3])
        XCTAssertEqual(model.output, 1)
        XCTAssertEqual(model.outputVolume, 0.5)
        XCTAssertEqual(model.inputVolume, 0.8)
        XCTAssertEqual(model.outputMuted, false)

        // 换成 AirPods：读它的音量和静音
        model.select(model.outputs[1], input: false)
        XCTAssertEqual(system.output, 3)
        XCTAssertEqual(model.output, 3)
        XCTAssertEqual(model.outputVolume, 0.3)
        XCTAssertEqual(model.outputMuted, true)
        XCTAssertNil(model.message)
        // 静音时把音量往上拖，顺便取消静音
        model.setOutputVolume(0.6)
        XCTAssertEqual(system.volumes[3], 0.6)
        XCTAssertEqual(system.muted[3], false)
        XCTAssertEqual(model.outputMuted, false)
        model.toggleMute()
        XCTAssertEqual(system.muted[3], true)
        // 输入
        model.select(model.inputs[1], input: true)
        XCTAssertEqual(system.input, 3)
        model.setInputVolume(0.4)
        XCTAssertEqual(system.volumes[3], 0.4)

        // 换不成时说一声，原来的不动
        system.refuses = [4]
        model.select(model.outputs[2], input: false)
        XCTAssertEqual(model.output, 3)
        XCTAssertEqual(model.message, "换不成「LG HDR 4K」")

        // 拔掉 AirPods：刷新以后列表跟着变
        system.devices.removeAll { $0.id == 3 }
        system.output = 1
        model.refresh()
        XCTAssertEqual(model.outputs.map(\.id), [1, 4])
        XCTAssertEqual(model.output, 1)

        // 没有设备
        XCTAssertTrue(SoundDevicesModel(backend: FakeSystem(devices: []).backend).isEmpty)
    }

    @MainActor
    func testReadsThisMacWithoutCrashing() {
        // CI 的机器上可能一个声音设备都没有；有的话名字和声道都读得出来
        for device in SoundDevices.all() {
            XCTAssertFalse(device.name.isEmpty)
            XCTAssertTrue(device.isOutput || device.isInput)
        }
        if let output = SoundDevices.defaultDevice(input: false), let volume = SoundDevices.volume(output, input: false) {
            XCTAssertTrue((0...1).contains(volume))
        }
        let demo = SoundDevicesModel(backend: SoundDevicesPlugin.demoBackend())
        XCTAssertEqual(demo.outputs.count, 3)
        XCTAssertEqual(demo.inputs.count, 2)
    }

    func testPluginNeedsNoSelection() {
        XCTAssertTrue(SoundDevicesPlugin().info.canHandle(.empty))
    }
}
