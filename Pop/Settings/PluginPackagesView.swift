import AppKit
import SwiftUI

/// 「设置 → 功能」最上面的插件包：要用时装上，不用了卸载，看每个占了多大。按分类分组，可以只看装了的或者没装的
struct PluginPackagesSection: View {
    @EnvironmentObject var manager: PluginManager
    /// 设置页上方搜索框里的字
    let query: String
    @State private var filter = Filter.all

    enum Filter: CaseIterable, Identifiable {
        case all
        case installed
        case notInstalled

        var id: Self { self }

        var title: String {
            switch self {
            case .all: return String(localized: "全部")
            case .installed: return String(localized: "已安装")
            case .notInstalled: return String(localized: "未安装")
            }
        }
    }

    var body: some View {
        let packages = PluginCatalog.packages.filter { matchesQuery($0) && matchesFilter($0) }
        let categories = BuiltinCategory.allCases.filter { category in packages.contains { $0.category == category } }
        Group {
            Section {
                HStack(spacing: 12) {
                    Text(summary)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 12)
                    Picker("显示", selection: $filter) {
                        ForEach(Filter.allCases) { filter in
                            Text(filter.title).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                if packages.isEmpty {
                    Text(filter == .installed && query.trimmingCharacters(in: .whitespaces).isEmpty ? String(localized: "还没有装插件") : String(localized: "没有匹配的插件"))
                        .foregroundStyle(.secondary)
                }
            } header: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Distribution.isAppStore
                         ? String(localized: "这些功能是单独的插件包，要用时再装上；不用了可以卸载，连同它的设置一起删掉。")
                         : String(localized: "这些功能是单独的插件包，要用时再装：从 GitHub 发布页下载，几秒就好；不用了可以卸载，连同它的设置一起删掉，不占地方。"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("插件")
                }
            } footer: {
                if let error = manager.indexError {
                    Text("读不到插件包列表：\(error)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(categories) { category in
                Section("插件 · \(category.title)") {
                    ForEach(packages.filter { $0.category == category }) { package in
                        PluginPackageRow(package: package)
                    }
                }
            }
        }
        .onAppear {
            manager.refreshIndex()
        }
    }

    /// 装了几个、一共占多大
    private var summary: String {
        let installed = PluginCatalog.packages.filter { manager.status(of: $0) == .installed }
        guard !installed.isEmpty else { return String(localized: "还没有装插件") }
        // App Store 版的插件包都在 App 里，装不装都占着地方
        if Distribution.isAppStore { return String(localized: "已装 \(installed.count) 个插件") }
        let total = installed.compactMap { manager.sizes[$0.id] }.reduce(0, +)
        return String(localized: "已装 \(installed.count) 个插件，一共占用 \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))")
    }

    private func matchesFilter(_ package: PluginPackage) -> Bool {
        switch filter {
        case .all:
            return true
        case .installed:
            return manager.status(of: package) == .installed
        case .notInstalled:
            return manager.status(of: package) != .installed
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
            guard !Distribution.isAppStore, let size = manager.sizes[package.id] else { return String(localized: "已安装") }
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
        if Distribution.isAppStore {
            alert.informativeText = String(localized: "会删掉它的设置。圆盘上和快捷键里的这个功能也会拿掉，要用时可以再装。")
        } else if let size = manager.sizes[package.id] {
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
