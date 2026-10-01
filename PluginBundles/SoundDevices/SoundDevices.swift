import AudioToolbox
import CoreAudio
import Foundation
@testable import Pop

/// 声音设备：列出能用的输出（扬声器、耳机、显示器、AirPlay）和输入（麦克风），换成默认的，调音量和静音。
/// 都用 CoreAudio 的公开接口；系统自己建的聚合设备、藏起来的设备不列。
enum SoundDevices {
    struct Device: Equatable, Identifiable {
        let id: AudioObjectID
        let uid: String
        let name: String
        let transport: UInt32
        let outputChannels: Int
        let inputChannels: Int

        var isOutput: Bool { outputChannels > 0 }
        var isInput: Bool { inputChannels > 0 }
        var kind: Kind { SoundDevices.kind(of: transport) }
    }

    enum Kind: Equatable {
        case builtIn, bluetooth, usb, hdmi, displayPort, airPlay, thunderbolt, virtual, aggregate, other
    }

    static func kind(of transport: UInt32) -> Kind {
        switch transport {
        case kAudioDeviceTransportTypeBuiltIn: return .builtIn
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return .bluetooth
        case kAudioDeviceTransportTypeUSB: return .usb
        case kAudioDeviceTransportTypeHDMI: return .hdmi
        case kAudioDeviceTransportTypeDisplayPort: return .displayPort
        case kAudioDeviceTransportTypeAirPlay: return .airPlay
        case kAudioDeviceTransportTypeThunderbolt: return .thunderbolt
        case kAudioDeviceTransportTypeVirtual: return .virtual
        case kAudioDeviceTransportTypeAggregate, kAudioDeviceTransportTypeAutoAggregate: return .aggregate
        default: return .other
        }
    }

    /// 设备的图标：AirPods 用 AirPods 的，蓝牙是耳机，显示器、AirPlay、虚拟设备各有各的；剩下的输出是扬声器、输入是麦克风
    static func symbol(for device: Device, input: Bool) -> String {
        if device.name.localizedCaseInsensitiveContains("AirPods Max") { return "airpodsmax" }
        if device.name.localizedCaseInsensitiveContains("AirPods Pro") { return "airpodspro" }
        if device.name.localizedCaseInsensitiveContains("AirPods") { return "airpods" }
        switch device.kind {
        case .bluetooth: return "headphones"
        case .hdmi: return "tv"
        case .displayPort, .thunderbolt: return input ? "mic" : "display"
        case .airPlay: return "airplayaudio"
        case .virtual, .aggregate: return "waveform"
        case .builtIn, .usb, .other: return input ? "mic" : "speaker.wave.2"
        }
    }

    /// 连接方式的说法：「蓝牙」「USB」「HDMI」……内建的不写
    static func transportTitle(_ kind: Kind) -> String? {
        switch kind {
        case .builtIn, .other: return nil
        case .bluetooth: return String(localized: "蓝牙")
        case .usb: return "USB"
        case .hdmi: return "HDMI"
        case .displayPort: return "DisplayPort"
        case .airPlay: return "AirPlay"
        case .thunderbolt: return "Thunderbolt"
        case .virtual: return String(localized: "虚拟设备")
        case .aggregate: return String(localized: "聚合设备")
        }
    }

    /// 要列出来的：有声道、不是系统为了某个 App 临时建的聚合设备
    static func listed(_ devices: [Device]) -> [Device] {
        devices.filter { ($0.isOutput || $0.isInput) && !$0.name.hasPrefix("CADefaultDeviceAggregate") && !$0.uid.hasPrefix("CADefaultDeviceAggregate") }
    }

    // MARK: - 读

    static var system: AudioObjectID {
        AudioObjectID(kAudioObjectSystemObject)
    }

    /// 这台 Mac 上的声音设备（藏起来的不要）
    static func all() -> [Device] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return listed(ids.compactMap(device))
    }

    static func device(_ id: AudioObjectID) -> Device? {
        guard let name = string(id, kAudioObjectPropertyName),
              uint32(id, kAudioDevicePropertyIsHidden) != 1 else { return nil }
        return Device(id: id, uid: string(id, kAudioDevicePropertyDeviceUID) ?? "\(id)", name: name,
                      transport: uint32(id, kAudioDevicePropertyTransportType) ?? 0,
                      outputChannels: channels(id, input: false), inputChannels: channels(id, input: true))
    }

    /// 现在默认的输出或者输入设备
    static func defaultDevice(input: Bool) -> AudioObjectID? {
        let selector = input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice
        guard let id = uint32(system, selector), id != kAudioObjectUnknown else { return nil }
        return id
    }

    /// 换默认的输出或者输入设备；成功时为 true
    @discardableResult
    static func setDefault(_ id: AudioObjectID, input: Bool) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value = id
        return AudioObjectSetPropertyData(system, &address, 0, nil, UInt32(MemoryLayout<AudioObjectID>.size), &value) == noErr
    }

    /// 音量（0～1）：系统音量条用的那个；设备不能调音量时为 nil
    static func volume(_ id: AudioObjectID, input: Bool) -> Float? {
        var address = volumeAddress(input: input)
        guard AudioObjectHasProperty(id, &address) else { return nil }
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    static func setVolume(_ value: Float, of id: AudioObjectID, input: Bool) {
        var address = volumeAddress(input: input)
        guard isSettable(id, &address) else { return }
        var volume = Float32(min(max(value, 0), 1))
        _ = AudioObjectSetPropertyData(id, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &volume)
    }

    /// 静音了没有；设备不能静音时为 nil
    static func isMuted(_ id: AudioObjectID, input: Bool) -> Bool? {
        uint32(id, kAudioDevicePropertyMute, scope: scope(input: input)).map { $0 != 0 }
    }

    static func setMuted(_ muted: Bool, of id: AudioObjectID, input: Bool) {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: scope(input: input), mElement: kAudioObjectPropertyElementMain)
        guard isSettable(id, &address) else { return }
        var value: UInt32 = muted ? 1 : 0
        _ = AudioObjectSetPropertyData(id, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
    }

    // MARK: - CoreAudio 的小工具

    private static func scope(input: Bool) -> AudioObjectPropertyScope {
        input ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput
    }

    private static func volumeAddress(input: Bool) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume, mScope: scope(input: input),
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private static func isSettable(_ id: AudioObjectID, _ address: inout AudioObjectPropertyAddress) -> Bool {
        guard AudioObjectHasProperty(id, &address) else { return false }
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(id, &address, &settable) == noErr && settable.boolValue
    }

    private static func uint32(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector,
                               scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> UInt32? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(id, &address) else { return nil }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private static func string(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(id, &address) else { return nil }
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr, let value else { return nil }
        let text = value.takeRetainedValue() as String
        return text.isEmpty ? nil : text
    }

    /// 输出或者输入有几个声道（流配置里每个缓冲区的声道加起来）
    private static func channels(_ id: AudioObjectID, input: Bool) -> Int {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration, mScope: scope(input: input),
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, raw) == noErr else { return 0 }
        let buffers = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
    }
}
