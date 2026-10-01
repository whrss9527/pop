import AppKit
import SwiftUI
@testable import Pop

/// 系统信息卡片：上面是型号和 macOS 版本，下面一行一项；序列号先藏着，点「显示」才露出来，复制时也只在露出来以后带上
@MainActor
final class SystemInfoModel: ObservableObject {
    let report: SystemInfo.Report
    private let now: () -> Date
    @Published var showsSerial = false

    init(report: SystemInfo.Report, now: @escaping () -> Date = Date.init) {
        self.report = report
        self.now = now
    }

    var symbol: String {
        SystemInfo.symbol(for: report.modelName)
    }

    /// 「macOS Sequoia 15.6.1（24G90）」
    var osText: String {
        let name = SystemInfo.osName(report.osVersion)
        return report.osBuild.isEmpty ? name : String(localized: "\(name)（\(report.osBuild)）")
    }

    var rows: [(label: String, value: String, warning: Bool)] {
        var rows: [(label: String, value: String, warning: Bool)] = []
        rows.append((label: String(localized: "型号标识"), value: report.modelIdentifier, warning: false))
        if !report.chip.isEmpty {
            rows.append((label: String(localized: "芯片型号"), value: report.chip, warning: false))
        }
        var cores = SystemInfo.cpuText(cores: report.cores, performance: report.performanceCores, efficiency: report.efficiencyCores)
        if let gpu = report.gpuCores {
            let count = String(gpu)
            cores += " · " + String(localized: "\(count) 核 GPU")
        }
        rows.append((label: String(localized: "核心"), value: cores, warning: false))
        rows.append((label: String(localized: "内存"), value: SystemInfo.memoryText(report.memory), warning: false))
        rows.append((label: "macOS", value: osText, warning: false))
        if let boot = report.bootTime {
            rows.append((label: String(localized: "已开机"), value: SystemInfo.uptimeText(since: boot, now: now()), warning: false))
        }
        if let disk = report.disk {
            // 剩下不到一成标橙
            rows.append((label: String(localized: "启动磁盘"), value: SystemInfo.diskText(disk),
                         warning: disk.total > 0 && Double(disk.available) / Double(disk.total) < 0.1))
        }
        // 内建的只写尺寸；外接的写上名字
        for display in report.displays {
            if display.builtIn {
                rows.append((label: String(localized: "内建显示器"), value: SystemInfo.displayText(display), warning: false))
            } else {
                rows.append((label: String(localized: "显示器"), value: "\(display.name) · \(SystemInfo.displayText(display))", warning: false))
            }
        }
        return rows
    }

    /// 复制用的文字：型号一行，再一行一项；序列号露出来了才带上
    var text: String {
        var lines = [report.modelName, osText]
        lines += rows.filter { $0.label != "macOS" }.map { String(localized: "\($0.label)：\($0.value)") }
        if showsSerial, let serial = report.serial {
            let label = String(localized: "序列号")
            lines.append(String(localized: "\(label)：\(serial)"))
        }
        return lines.joined(separator: "\n")
    }
}

struct SystemInfoView: View {
    @ObservedObject var model: SystemInfoModel
    var onCopy: () -> Void
    var onClose: () -> Void

    var body: some View {
        CardContainer(title: String(localized: "系统信息"), width: 400, onClose: onClose) {
            HStack(spacing: 12) {
                Image(systemName: model.symbol)
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(.secondary)
                    .frame(width: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: model.report.modelName)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(verbatim: model.osText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 6) {
                ForEach(Array(model.rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        Text(row.label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .gridColumnAlignment(.trailing)
                        Text(row.value)
                            .font(.callout)
                            .foregroundStyle(row.warning ? Color.orange : Color.primary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let serial = model.report.serial {
                    GridRow {
                        Text("序列号")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .gridColumnAlignment(.trailing)
                        HStack(spacing: 6) {
                            Text(verbatim: model.showsSerial ? serial : String(repeating: "•", count: min(serial.count, 12)))
                                .font(.callout.monospaced())
                                .textSelection(.enabled)
                            Button(model.showsSerial ? String(localized: "隐藏") : String(localized: "显示")) {
                                model.showsSerial.toggle()
                            }
                            .buttonStyle(.link)
                            .font(.caption)
                        }
                    }
                }
            }
            HStack(spacing: 8) {
                Spacer()
                Button("复制信息", action: onCopy)
                Button("完成", action: onClose)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .controlSize(.small)
    }
}
