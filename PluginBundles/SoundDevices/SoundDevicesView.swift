import AppKit
import CoreAudio
import SwiftUI
@testable import Pop

/// 声音设备卡片：上面是输出（打勾的是现在用的，点一下换）和输出音量、静音，下面是输入和输入音量。
/// 卡片开着时每 1.5 秒看一次设备有没有变（插上耳机、连上 AirPods）。
@MainActor
final class SoundDevicesModel: ObservableObject {
    /// 读写声音设备的地方：这台 Mac，或者测试、演示时的假设备
    struct Backend {
        var devices: () -> [SoundDevices.Device]
        var defaultDevice: (_ input: Bool) -> AudioObjectID?
        var setDefault: (_ id: AudioObjectID, _ input: Bool) -> Bool
        var volume: (_ id: AudioObjectID, _ input: Bool) -> Float?
        var setVolume: (_ value: Float, _ id: AudioObjectID, _ input: Bool) -> Void
        var isMuted: (_ id: AudioObjectID, _ input: Bool) -> Bool?
        var setMuted: (_ muted: Bool, _ id: AudioObjectID, _ input: Bool) -> Void

        static var system: Backend {
            Backend(devices: { SoundDevices.all() },
                    defaultDevice: { SoundDevices.defaultDevice(input: $0) },
                    setDefault: { SoundDevices.setDefault($0, input: $1) },
                    volume: { SoundDevices.volume($0, input: $1) },
                    setVolume: { SoundDevices.setVolume($0, of: $1, input: $2) },
                    isMuted: { SoundDevices.isMuted($0, input: $1) },
                    setMuted: { SoundDevices.setMuted($0, of: $1, input: $2) })
        }
    }

    @Published private(set) var outputs: [SoundDevices.Device] = []
    @Published private(set) var inputs: [SoundDevices.Device] = []
    @Published private(set) var output: AudioObjectID?
    @Published private(set) var input: AudioObjectID?
    @Published private(set) var outputVolume: Float?
    @Published private(set) var inputVolume: Float?
    @Published private(set) var outputMuted: Bool?
    /// 换不成时的说明
    @Published private(set) var message: String?

    private let backend: Backend
    private var timer: Timer?

    init(backend: Backend = .system) {
        self.backend = backend
        refresh()
    }

    var isEmpty: Bool {
        outputs.isEmpty && inputs.isEmpty
    }

    func refresh() {
        let devices = backend.devices()
        outputs = devices.filter(\.isOutput)
        inputs = devices.filter(\.isInput)
        output = backend.defaultDevice(false)
        input = backend.defaultDevice(true)
        outputVolume = output.flatMap { backend.volume($0, false) }
        inputVolume = input.flatMap { backend.volume($0, true) }
        outputMuted = output.flatMap { backend.isMuted($0, false) }
    }

    /// 换成这个设备
    func select(_ device: SoundDevices.Device, input: Bool) {
        message = backend.setDefault(device.id, input) ? nil : String(localized: "换不成「\(device.name)」")
        refresh()
    }

    /// 调输出音量；静音时往上拖就取消静音
    func setOutputVolume(_ value: Float) {
        guard let output else { return }
        backend.setVolume(value, output, false)
        outputVolume = value
        if value > 0, outputMuted == true {
            backend.setMuted(false, output, false)
            outputMuted = false
        }
    }

    func setInputVolume(_ value: Float) {
        guard let input else { return }
        backend.setVolume(value, input, true)
        inputVolume = value
    }

    func toggleMute() {
        guard let output, let muted = outputMuted else { return }
        backend.setMuted(!muted, output, false)
        outputMuted = !muted
    }

    func startRefreshing() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
            }
        }
    }

    func stopRefreshing() {
        timer?.invalidate()
        timer = nil
    }
}

struct SoundDevicesView: View {
    @ObservedObject var model: SoundDevicesModel
    var onOpenSettings: () -> Void
    var onClose: () -> Void

    var body: some View {
        CardContainer(title: String(localized: "声音设备"), width: 360, onClose: onClose) {
            section(String(localized: "输出"), devices: model.outputs, selected: model.output, input: false)
            if let volume = model.outputVolume {
                HStack(spacing: 8) {
                    Button(action: model.toggleMute) {
                        Image(systemName: model.outputMuted == true ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .frame(width: 20)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .disabled(model.outputMuted == nil)
                    .help(model.outputMuted == true ? String(localized: "取消静音") : String(localized: "静音"))
                    Slider(value: Binding(get: { Double(volume) }, set: { model.setOutputVolume(Float($0)) }), in: 0...1)
                        .opacity(model.outputMuted == true ? 0.5 : 1)
                }
            }
            Divider()
            section(String(localized: "输入"), devices: model.inputs, selected: model.input, input: true)
            if let volume = model.inputVolume {
                HStack(spacing: 8) {
                    Image(systemName: "mic.fill")
                        .frame(width: 20)
                        .foregroundStyle(.secondary)
                    Slider(value: Binding(get: { Double(volume) }, set: { model.setInputVolume(Float($0)) }), in: 0...1)
                }
            }
            if let message = model.message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            HStack(spacing: 8) {
                Button("声音设置", action: onOpenSettings)
                Spacer()
                Button("完成", action: onClose)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .controlSize(.small)
        .onAppear { model.startRefreshing() }
        .onDisappear { model.stopRefreshing() }
    }

    @ViewBuilder
    private func section(_ title: String, devices: [SoundDevices.Device], selected: AudioObjectID?, input: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            if devices.isEmpty {
                Text(input ? String(localized: "没有能用的输入设备") : String(localized: "没有能用的输出设备"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            }
            ForEach(devices) { device in
                DeviceRow(device: device, input: input, isSelected: device.id == selected) {
                    model.select(device, input: input)
                }
            }
        }
    }
}

/// 一个设备：图标、名字和连接方式，现在用的打勾；点一下换成它
private struct DeviceRow: View {
    let device: SoundDevices.Device
    let input: Bool
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: SoundDevices.symbol(for: device, input: input))
                    .frame(width: 20)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: device.name)
                        .font(.callout)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let transport = SoundDevices.transportTitle(device.kind) {
                        Text(transport)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(hovering ? 0.08 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
