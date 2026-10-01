import AppKit
import SwiftUI
@testable import Pop

/// App 信息卡片：图标、名字、版本，下面一项项列出芯片、签名、公证、沙盒、用什么做的、来源、大小和会要的权限。
@MainActor
final class AppInfoModel: ObservableObject {
    let report: AppInspector.Report
    let icon: NSImage?
    /// 占多大；在后台算
    @Published private(set) var size: UInt64?

    init(report: AppInspector.Report, icon: NSImage?, size: UInt64? = nil) {
        self.report = report
        self.icon = icon
        self.size = size
    }

    func measure() {
        guard size == nil else { return }
        let url = report.url
        Task {
            size = await runInBackground { AppInspector.size(of: url) }
        }
    }

    /// 卡片上的一行行：名字和值；值为空的不列
    var rows: [(label: String, value: String, warning: Bool)] {
        var rows: [(label: String, value: String, warning: Bool)] = []
        func add(_ label: String, _ value: String?, warning: Bool = false) {
            if let value, !value.isEmpty { rows.append((label: label, value: value, warning: warning)) }
        }
        add(String(localized: "芯片"), report.architecture.title, warning: report.architecture == .intel)
        add(String(localized: "最低系统"), report.minimumSystem)
        let signature = report.signature.title + (report.teamID.map { "（\($0)）" } ?? "")
        add(String(localized: "签名"), signature, warning: [.unsigned, .adHoc].contains(report.signature))
        add(String(localized: "公证"), report.notarized.map { $0 ? String(localized: "已公证") : String(localized: "没有公证") }, warning: report.notarized == false)
        add(String(localized: "沙盒"), report.sandboxed ? String(localized: "在沙盒里") : String(localized: "不在沙盒里"))
        add(String(localized: "加固运行时"), report.hardenedRuntime ? String(localized: "开着") : String(localized: "没开"))
        add(String(localized: "用什么做的"), report.technologies.joined(separator: " · "))
        add(String(localized: "来源"), AppInspector.source(report))
        add(String(localized: "大小"), size.map { ByteCountFormatter.string(fromByteCount: Int64(clamping: $0), countStyle: .file) } ?? "…")
        add(String(localized: "打开它的链接"), report.urlSchemes.joined(separator: " "))
        return rows
    }

    var text: String {
        AppInspector.text(report, size: size)
    }
}

struct AppInfoView: View {
    @ObservedObject var model: AppInfoModel
    var onCopy: () -> Void
    var onReveal: () -> Void
    var onClose: () -> Void

    var body: some View {
        CardContainer(title: String(localized: "App 信息"), subtitle: model.report.name, width: 420, onClose: onClose) {
            HStack(spacing: 10) {
                if let icon = model.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 44, height: 44)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.report.name + (model.report.version.map { " \($0)" } ?? ""))
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    if let bundleID = model.report.bundleID {
                        Text(bundleID)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
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
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }
            }
            if !model.report.permissions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("会要的权限")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    FlowLayout(spacing: 6) {
                        ForEach(model.report.permissions) { permission in
                            Text(permission.name)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.primary.opacity(0.07)))
                                // App 自己写的用途说明
                                .help(permission.reason)
                        }
                    }
                }
            }
            HStack(spacing: 8) {
                Spacer()
                Button("在访达中显示", action: onReveal)
                Button("复制信息", action: onCopy)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .controlSize(.small)
    }
}
