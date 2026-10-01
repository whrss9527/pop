import AppKit
import SwiftUI
@testable import Pop

/// 电池信息卡片：左边一圈电量，右边是在充电还是在用电、功率、还要多久；下面列出最大容量、循环次数、状况、温度、电压和充电器。
/// 卡片开着时每 3 秒刷新一次。
@MainActor
final class BatteryInfoModel: ObservableObject {
    @Published private(set) var report: BatteryReader.Report
    private let read: () -> BatteryReader.Report?
    private var timer: Timer?

    init(report: BatteryReader.Report, read: @escaping () -> BatteryReader.Report? = BatteryReader.read) {
        self.report = report
        self.read = read
    }

    func startRefreshing() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
            }
        }
    }

    func stopRefreshing() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        if let latest = read() {
            report = latest
        }
    }

    /// 「正在充电」「用电池」「已充满」「接着电源，暂停充电」
    var state: String {
        if report.isCharging { return String(localized: "正在充电") }
        if report.externalConnected {
            return report.fullyCharged || report.percent >= 100 ? String(localized: "已充满") : String(localized: "接着电源，暂停充电")
        }
        return String(localized: "用电池")
    }

    /// 「45.2 W」；功率太小（不到 0.1 瓦）时不写
    var power: String? {
        guard let watts = report.watts, abs(watts) >= 0.1 else { return nil }
        return String(format: "%.1f W", abs(watts))
    }

    /// 「充满还要 0:45」「还能用 5:12」
    var remaining: String? {
        if report.isCharging, let minutes = report.minutesToFull {
            return String(localized: "充满还要 \(BatteryReader.duration(minutes: minutes))")
        }
        if !report.externalConnected, let minutes = report.minutesToEmpty {
            return String(localized: "还能用 \(BatteryReader.duration(minutes: minutes))")
        }
        return nil
    }

    var rows: [(label: String, value: String, warning: Bool)] {
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

    /// 复制用的文字
    var text: String {
        let percent = "\(report.percent)%"
        return ([String(localized: "电量 \(percent)，\(state)")] + rows.map { "\($0.label)：\($0.value)" }).joined(separator: "\n")
    }
}

struct BatteryInfoView: View {
    @ObservedObject var model: BatteryInfoModel
    var onCopy: () -> Void
    var onOpenSettings: () -> Void
    var onClose: () -> Void

    var body: some View {
        CardContainer(title: String(localized: "电池信息"), width: 380, onClose: onClose) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .stroke(Color.primary.opacity(0.1), lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: CGFloat(model.report.percent) / 100)
                        .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text(verbatim: "\(model.report.percent)%")
                        .font(.system(size: 15, weight: .semibold))
                        .monospacedDigit()
                }
                .frame(width: 58, height: 58)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        if model.report.isCharging {
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
            HStack(spacing: 8) {
                Button("电池设置", action: onOpenSettings)
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
    private var color: Color {
        if model.report.percent <= 20 && !model.report.isCharging { return .red }
        return model.report.isCharging ? .green : .accentColor
    }
}
