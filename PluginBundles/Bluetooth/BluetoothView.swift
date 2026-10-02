import AppKit
import CoreBluetooth
import IOBluetooth
import SwiftUI
@testable import Pop

/// 读设备、连接、断开的地方：这台 Mac，或者测试、演示时的假设备
@MainActor
protocol BluetoothBackend: AnyObject {
    /// 用户在系统设置里没给 Pop 蓝牙权限
    var isDenied: Bool { get }
    func devices() -> [BluetoothDevices.Device]
    /// 连上以后（或者连不上）回调，参数是连上没有
    func connect(_ id: String, completion: @escaping @MainActor (Bool) -> Void)
    func disconnect(_ id: String) -> Bool
}

/// 用 IOBluetooth 连、断已经配对的设备（不搜索、不配对新设备）。连接是异步的，连上或者超时后回调
@MainActor
final class SystemBluetooth: NSObject, BluetoothBackend {
    private var pending: [String: @MainActor (Bool) -> Void] = [:]

    var isDenied: Bool {
        let authorization = CBManager.authorization
        return authorization == .denied || authorization == .restricted
    }

    func devices() -> [BluetoothDevices.Device] {
        let batteries = BluetoothDevices.hidBatteries()
        return paired().compactMap { device in
            guard let address = device.addressString, !address.isEmpty else { return nil }
            let id = BluetoothDevices.normalizedAddress(address)
            let name = device.name ?? device.nameOrAddress ?? address
            return BluetoothDevices.Device(id: id, name: name,
                                           kind: BluetoothDevices.kind(major: device.deviceClassMajor, minor: device.deviceClassMinor, name: name),
                                           isConnected: device.isConnected(), battery: batteries[id])
        }
    }

    func connect(_ id: String, completion: @escaping @MainActor (Bool) -> Void) {
        guard let device = find(id) else {
            completion(false)
            return
        }
        pending[id] = completion
        if device.openConnection(self) != kIOReturnSuccess {
            pending[id] = nil
            completion(false)
        }
    }

    func disconnect(_ id: String) -> Bool {
        guard let device = find(id) else { return false }
        return device.closeConnection() == kIOReturnSuccess
    }

    /// IOBluetooth 在主线程上回调
    @objc func connectionComplete(_ device: IOBluetoothDevice?, status: IOReturn) {
        guard let address = device?.addressString else { return }
        let completion = pending.removeValue(forKey: BluetoothDevices.normalizedAddress(address))
        completion?(status == kIOReturnSuccess)
    }

    private func paired() -> [IOBluetoothDevice] {
        (IOBluetoothDevice.pairedDevices() ?? []).compactMap { $0 as? IOBluetoothDevice }
    }

    private func find(_ id: String) -> IOBluetoothDevice? {
        paired().first { $0.addressString.map(BluetoothDevices.normalizedAddress) == id }
    }
}

/// 蓝牙设备卡片的状态：配对过的设备、哪个正在连、出了什么问题。卡片开着时每 2 秒看一次有没有变
@MainActor
final class BluetoothModel: ObservableObject {
    @Published private(set) var devices: [BluetoothDevices.Device] = []
    /// 正在连的设备
    @Published private(set) var connecting: Set<String> = []
    /// 连不上、断不开时的说明
    @Published private(set) var message: String?
    @Published private(set) var isDenied = false

    private let backend: BluetoothBackend
    private var timer: Timer?

    init(backend: BluetoothBackend) {
        self.backend = backend
        refresh()
    }

    func refresh() {
        isDenied = backend.isDenied
        devices = isDenied ? [] : BluetoothDevices.sorted(backend.devices())
    }

    /// 连着的断开，没连的连上
    func toggle(_ device: BluetoothDevices.Device) {
        guard !connecting.contains(device.id) else { return }
        message = nil
        if device.isConnected {
            if !backend.disconnect(device.id) {
                message = String(localized: "断不开「\(device.name)」")
            }
            refresh()
            return
        }
        connecting.insert(device.id)
        backend.connect(device.id) { [weak self] connected in
            guard let self else { return }
            self.connecting.remove(device.id)
            if !connected {
                self.message = String(localized: "连不上「\(device.name)」：确认它开着、在附近，没有连着别的设备")
            }
            self.refresh()
        }
    }

    /// 「已连接 · 电量 72%」「未连接」
    func status(of device: BluetoothDevices.Device) -> String {
        if connecting.contains(device.id) {
            return String(localized: "正在连接…")
        }
        guard device.isConnected else {
            return String(localized: "未连接")
        }
        guard let battery = device.battery else {
            return String(localized: "已连接")
        }
        let percent = "\(battery)%"
        return String(localized: "已连接 · 电量 \(percent)")
    }

    func startRefreshing() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
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

struct BluetoothView: View {
    @ObservedObject var model: BluetoothModel
    var onOpenSettings: () -> Void
    var onOpenPrivacy: () -> Void
    var onClose: () -> Void

    var body: some View {
        CardContainer(title: String(localized: "蓝牙设备"), width: 360, onClose: onClose) {
            if model.isDenied {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Pop 还没有蓝牙权限。到「系统设置 → 隐私与安全性 → 蓝牙」里打开 Pop，就能在这里连接、断开配对过的设备。")
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("打开隐私设置", action: onOpenPrivacy)
                }
            } else if model.devices.isEmpty {
                Text("没有配对过的蓝牙设备。新设备先在「蓝牙设置」里配对。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 2) {
                    ForEach(model.devices) { device in
                        DeviceRow(device: device, status: model.status(of: device), isConnecting: model.connecting.contains(device.id)) {
                            model.toggle(device)
                        }
                    }
                }
            }
            if let message = model.message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Button("蓝牙设置", action: onOpenSettings)
                Spacer()
                Button("完成", action: onClose)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .controlSize(.small)
        .onAppear { model.startRefreshing() }
        .onDisappear { model.stopRefreshing() }
    }
}

/// 一个设备：图标、名字、连着没有，右边是「连接」「断开」或者转圈
private struct DeviceRow: View {
    let device: BluetoothDevices.Device
    let status: String
    let isConnecting: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: device.kind.symbol)
                .font(.system(size: 15))
                .frame(width: 24)
                .foregroundStyle(device.isConnected ? Color.accentColor : Color.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(device.name)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(status)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer(minLength: 8)
            if isConnecting {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 44)
            } else {
                Button(device.isConnected ? String(localized: "断开") : String(localized: "连接"), action: action)
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 6)
    }
}
