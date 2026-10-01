import AppKit
import SwiftUI
@testable import Pop

/// 电池信息卡片：左边一圈电量，右边是在充电还是在用电、功率、还要多久；下面列出最大容量、循环次数、状况、温度、电压和充电器，
/// 再下面是连着的蓝牙设备（键盘、鼠标、触控板、耳机）的电量。台式 Mac 没有电池，只列设备。
/// 卡片开着时每 3 秒刷新一次；耳机这些要问 system_profiler，一分钟问一次。
@MainActor
final class BatteryInfoModel: ObservableObject {
    /// 从哪读。读不到时返回 nil，保留上一次的
    struct Sources {
        var battery: () -> BatteryReader.Report?
        var hid: () -> [DeviceBatteries.Device]?
        var bluetooth: () async -> [DeviceBatteries.Device]?

        /// 这台 Mac
        static var system: Sources {
            Sources(battery: { BatteryReader.read() }, hid: { DeviceBatteries.hidDevices() }, bluetooth: { await DeviceBatteries.bluetoothDevices() })
        }

        /// 演示和测试：什么都不读
        static var none: Sources {
            Sources(battery: { nil }, hid: { nil }, bluetooth: { nil })
        }
    }

    @Published private(set) var report: BatteryReader.Report?
    @Published private(set) var devices: [DeviceBatteries.Device]
    private var hidDevices: [DeviceBatteries.Device]
    private var bluetoothDevices: [DeviceBatteries.Device]
    private let sources: Sources
    private var timer: Timer?
    private var ticks = 0
    private var loadingBluetooth = false

    init(report: BatteryReader.Report?, hid: [DeviceBatteries.Device] = [], bluetooth: [DeviceBatteries.Device] = [], sources: Sources = .system) {
        self.report = report
        hidDevices = hid
        bluetoothDevices = bluetooth
        devices = DeviceBatteries.merge(hid: hid, bluetooth: bluetooth)
        self.sources = sources
    }

    func startRefreshing() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
            }
        }
        loadBluetooth()
    }

    func stopRefreshing() {
        timer?.invalidate()
        timer = nil
    }

    /// 电池和键盘鼠标每次都读；蓝牙信息慢，每 20 次（一分钟）读一次
    func refresh() {
        if let latest = sources.battery() {
            report = latest
        }
        if let latest = sources.hid() {
            hidDevices = latest
            devices = DeviceBatteries.merge(hid: latest, bluetooth: bluetoothDevices)
        }
        ticks += 1
        if ticks % 20 == 0 {
            loadBluetooth()
        }
    }

    /// 在后台问一次 system_profiler，读到了换上
    func loadBluetooth() {
        guard !loadingBluetooth else { return }
        loadingBluetooth = true
        let read = sources.bluetooth
        Task { [weak self] in
            let latest = await read()
            guard let self else { return }
            self.loadingBluetooth = false
            if let latest {
                self.bluetoothDevices = latest
                self.devices = DeviceBatteries.merge(hid: self.hidDevices, bluetooth: latest)
            }
        }
    }

    /// 「正在充电」「用电池」「已充满」「接着电源，暂停充电」；没有电池时是空的
    var state: String {
        guard let report else { return "" }
        if report.isCharging { return String(localized: "正在充电") }
        if report.externalConnected {
            return report.fullyCharged || report.percent >= 100 ? String(localized: "已充满") : String(localized: "接着电源，暂停充电")
        }
        return String(localized: "用电池")
    }

    /// 「45.2 W」；功率太小（不到 0.1 瓦）时不写
    var power: String? {
        guard let watts = report?.watts, abs(watts) >= 0.1 else { return nil }
        return String(format: "%.1f W", abs(watts))
    }

    /// 「充满还要 0:45」「还能用 5:12」
    var remaining: String? {
        guard let report else { return nil }
        if report.isCharging, let minutes = report.minutesToFull {
            return String(localized: "充满还要 \(BatteryReader.duration(minutes: minutes))")
        }
        if !report.externalConnected, let minutes = report.minutesToEmpty {
            return String(localized: "还能用 \(BatteryReader.duration(minutes: minutes))")
        }
        return nil
    }

    var rows: [(label: String, value: String, warning: Bool)] {
        guard let report else { return [] }
        var rows: [(label: String, value: String, warning: Bool)] = []
        if let health = report.health {
            var value = "\(String(health))%"
            if let full = report.fullCapacity, let design = report.designCapacity {
                value += String(localized: "（现在 \(String(full)) mAh，出厂 \(String(design)) mAh）")
            }
            rows.append((label: String(localized: "最大容量"), value: value, warning: health < 80))
        }
        if let cycles = report.cycleCount {
            let value = report.designCycles.map { String(localized: "\(String(cycles)) 次（设计寿命 \(String($0)) 次）") } ?? String(localized: "\(String(cycles)) 次")
            rows.append((label: String(localized: "循环次数"), value: value, warning: report.designCycles.map { cycles >= $0 } ?? false))
        }
        rows.append((label: String(localized: "状况"), value: report.needsService ? String(localized: "建议维修") : String(localized: "正常"),
                     warning: report.needsService))
        if let temperature = report.temperature {
            rows.append((label: String(localized: "温度"), value: String(format: "%.1f ℃", temperature), warning: temperature >= 40))
        }
        if let voltage = report.voltage {
            rows.append((label: String(localized: "电压"), value: String(format: "%.2f V", voltage), warning: false))
        }
        if report.externalConnected {
            let adapter = [report.adapterWatts.map { "\(String($0)) W" }, report.adapterName].compactMap { $0 }.joined(separator: " · ")
            rows.append((label: String(localized: "电源适配器"), value: adapter.isEmpty ? String(localized: "已接上") : adapter, warning: false))
        }
        return rows
    }

    /// 复制用的文字：电池一行一项，再是每个设备一行
    var text: String {
        var lines: [String] = []
        if let report {
            let percent = "\(report.percent)%"
            lines.append(String(localized: "电量 \(percent)，\(state)"))
            lines += rows.map { String(localized: "\($0.label)：\($0.value)") }
        }
        lines += devices.map { String(localized: "\($0.name)：\($0.levels)") }
        return lines.joined(separator: "\n")
    }
}

struct BatteryInfoView: View {
    @ObservedObject var model: BatteryInfoModel
    var onCopy: () -> Void
    var onOpenSettings: () -> Void
    var onClose: () -> Void

    var body: some View {
        CardContainer(title: String(localized: "电池信息"), width: 380, onClose: onClose) {
            if let report = model.report {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .stroke(Color.primary.opacity(0.1), lineWidth: 6)
                        Circle()
                            .trim(from: 0, to: CGFloat(report.percent) / 100)
                            .stroke(color(report), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text(verbatim: "\(report.percent)%")
                            .font(.system(size: 15, weight: .semibold))
                            .monospacedDigit()
                    }
                    .frame(width: 58, height: 58)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 4) {
                            if report.isCharging {
                                Image(systemName: "bolt.fill")
                                    .foregroundStyle(.green)
                            }
                            Text(model.state)
                                .font(.system(size: 13, weight: .semibold))
                            if let power = model.power {
                                Text(power)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                        if let remaining = model.remaining {
                            Text(remaining)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    Spacer(minLength: 0)
                }
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 6) {
                    ForEach(Array(model.rows.enumerated()), id: \.offset) { _, row in
                        GridRow {
                            Text(row.label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .gridColumnAlignment(.trailing)
                            Text(row.value)
                                .font(.callout)
                                .foregroundStyle(row.warning ? Color.orange : Color.primary)
                                .monospacedDigit()
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            if !model.devices.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    if model.report != nil {
                        Divider()
                    }
                    Text("蓝牙设备")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(model.devices) { device in
                        HStack(spacing: 8) {
                            Image(systemName: device.symbol)
                                .frame(width: 20)
                                .foregroundStyle(.secondary)
                            Text(device.name)
                                .font(.callout)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 8)
                            Text(device.levels)
                                .font(.callout)
                                .foregroundStyle(device.isLow ? Color.orange : Color.primary)
                                .monospacedDigit()
                                .lineLimit(1)
                        }
                    }
                }
            }
            HStack(spacing: 8) {
                if model.report != nil {
                    Button("电池设置", action: onOpenSettings)
                }
                Spacer()
                Button("复制信息", action: onCopy)
                Button("完成", action: onClose)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .controlSize(.small)
        .onAppear { model.startRefreshing() }
        .onDisappear { model.stopRefreshing() }
    }

    /// 电量的颜色：低于 20% 红，充电时绿
    private func color(_ report: BatteryReader.Report) -> Color {
        if report.percent <= 20 && !report.isCharging { return .red }
        return report.isCharging ? .green : .accentColor
    }
}
