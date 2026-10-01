import AppKit
import SwiftUI

/// 「设置 → 功能」最上面的插件包：要用时装上，不用了卸载，看每个占了多大。按分类分组
struct PluginPackagesSection: View {
    @EnvironmentObject var manager: PluginManager
    /// 设置页上方搜索框里的字
    let query: String

    var body: some View {
        let packages = PluginCatalog.packages.filter(matchesQuery)
        let categories = BuiltinCategory.allCases.filter { category in packages.contains { $0.category == category } }
        Group {
            if packages.isEmpty {
                Section {
                    Text("没有匹配的插件")
                        .foregroundStyle(.secondary)
                } header: {
                    header(Text("插件"))
                }
            }
            ForEach(categories) { category in
                Section {
                    ForEach(packages.filter { $0.category == category }) { package in
                        PluginPackageRow(package: package)
                    }
                } header: {
                    if category == categories.first {
                        header(Text("插件 · \(category.title)"))
                    } else {
                        Text("插件 · \(category.title)")
                    }
                } footer: {
                    if category == categories.last, let error = manager.indexError {
                        Text("读不到插件包列表：\(error)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .onAppear {
            manager.refreshIndex()
        }
    }

    /// 第一组上面的说明
    private func header(_ title: Text) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("这些功能是单独的插件包，要用时再装：从 GitHub 发布页下载，几秒就好；不用了可以卸载，连同它的设置一起删掉，不占地方。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            title
        }
    }

    private func matchesQuery(_ package: PluginPackage) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return true }
        return SearchText.matches(trimmed, keys: SearchText.keys(for: package.name) + [package.summary.lowercased()])
    }
}

struct PluginPackageRow: View {
    @EnvironmentObject var manager: PluginManager
    let package: PluginPackage

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: package.symbol)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(package.name)
                Text(package.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(isFailed ? Color.orange : Color.secondary)
            }
            Spacer(minLength: 12)
            action
        }
    }

    private var status: PluginManager.Status {
        manager.status(of: package)
    }

    private var isFailed: Bool {
        if case .failed = status { return true }
        return false
    }

    private var detail: String {
        switch status {
        case .installed:
            guard let size = manager.sizes[package.id] else { return String(localized: "已安装") }
            return String(localized: "已安装 · 占用 \(Self.format(size))")
        case .installing:
            return String(localized: "正在下载…")
        case .failed(let message):
            return message
        case .notInstalled:
            guard let entry = manager.index?.entry(id: package.id) else { return String(localized: "未安装") }
            return String(localized: "未安装 · 下载 \(Self.format(entry.size))，装好后占用 \(Self.format(entry.installedSize))")
        }
    }

    @ViewBuilder
    private var action: some View {
        switch status {
        case .installed:
            Button("卸载", action: confirmUninstall)
        case .installing:
            ProgressView()
                .controlSize(.small)
        case .failed:
            HStack(spacing: 6) {
                Button("重试") { manager.install(package) }
                // 不装了：从设置里拿掉，Pop 下次启动也不会再去下载
                Button("取消") { manager.uninstall(package) }
            }
        case .notInstalled:
            Button("安装") { manager.install(package) }
        }
    }

    private func confirmUninstall() {
        let alert = NSAlert()
        alert.messageText = String(localized: "卸载「\(package.name)」？")
        if let size = manager.sizes[package.id] {
            alert.informativeText = String(localized: "会删掉插件包和它的设置，腾出 \(Self.format(size))。圆盘上和快捷键里的这个功能也会拿掉，要用时可以再装。")
        } else {
            alert.informativeText = String(localized: "会删掉插件包和它的设置。圆盘上和快捷键里的这个功能也会拿掉，要用时可以再装。")
        }
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "卸载"))
        alert.addButton(withTitle: String(localized: "取消"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        manager.uninstall(package)
    }

    private static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
