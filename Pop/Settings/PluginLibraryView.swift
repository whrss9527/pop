import AppKit
import SwiftUI

/// 插件库：列出 GitHub 上 plugins 文件夹里的插件，可以搜索，点一下就装上。
struct PluginLibraryView: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var pluginStore: PluginStore
    let onClose: () -> Void
    @StateObject private var model = PluginLibraryModel()
    @State private var query = ""
    @State private var notice: String? = nil
    @State private var errorMessage: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("插件库")
                        .font(.headline)
                    Text("别人做好的插件，点「安装」就能用")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                TextField("搜索，支持拼音首字母", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            HStack(spacing: 12) {
                Text(notice ?? String(localized: "下载后先核对 sha256，对得上才装。装好的插件在「我的插件」里，可以编辑、停用或者删除。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Link("在 GitHub 上看", destination: PluginLibrary.browseURL)
                    .font(.caption)
                Button("完成", action: onClose)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 600, height: 540)
        .task {
            await model.load()
        }
        .alert("没有装上", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("好") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            ProgressView("正在读取插件库…")
                .controlSize(.small)
        case .failed(let message):
            VStack(spacing: 10) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text(message)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button("重试") {
                    Task { await model.load() }
                }
            }
            .padding(24)
        case .loaded(let catalog):
            let entries = catalog.index.entries(matching: query)
            if entries.isEmpty {
                Text(catalog.index.plugins.isEmpty ? String(localized: "插件库里还没有插件") : String(localized: "没有匹配的插件"))
                    .foregroundStyle(.secondary)
            } else {
                let installedIDs = Set(pluginStore.manifests.map(\.id))
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(entries) { entry in
                            let state = model.state(of: entry, installedIDs: installedIDs)
                            PluginLibraryRow(entry: entry, state: state, isInstalling: model.installing.contains(entry.id)) {
                                install(entry, isUpdate: state == .updateAvailable)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            if entry.id != entries.last?.id {
                                Divider().padding(.horizontal, 12)
                            }
                        }
                    }
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                    .padding(20)
                }
            }
        }
    }

    private func install(_ entry: PluginIndex.Entry, isUpdate: Bool) {
        Task {
            do {
                guard let saved = try await model.install(entry, into: pluginStore, confirm: confirmScript) else { return }
                // 更新时不动开关：用户停用了的还是停用
                if !isUpdate {
                    store.update { $0.setInstalled(saved.id, true) }
                }
                notice = isUpdate
                    ? String(localized: "「\(saved.displayName)」已经更新")
                    : String(localized: "装好了「\(saved.displayName)」：在圆盘的「全部功能」里能找到，也可以到「圆盘」里拖到想要的位置")
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    /// 运行 Shell 脚本的插件，装之前先给用户看一眼脚本
    private func confirmScript(_ manifest: PluginManifest) -> Bool {
        let alert = NSAlert()
        alert.messageText = String(localized: "「\(manifest.displayName)」会在这台 Mac 上运行 Shell 脚本")
        alert.informativeText = String(localized: "每次用它都会运行下面这段脚本，脚本能读写你的文件。只装信得过的插件。")
        alert.alertStyle = .warning
        let scroll = NSTextView.scrollableTextView()
        scroll.frame = NSRect(x: 0, y: 0, width: 420, height: 160)
        scroll.borderType = .bezelBorder
        if let textView = scroll.documentView as? NSTextView {
            textView.string = manifest.action.script
            textView.isEditable = false
            textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        }
        alert.accessoryView = scroll
        alert.addButton(withTitle: String(localized: "安装"))
        alert.addButton(withTitle: String(localized: "取消"))
        return alert.runModal() == .alertFirstButtonReturn
    }
}

struct PluginLibraryRow: View {
    let entry: PluginIndex.Entry
    let state: PluginLibraryModel.EntryState
    let isInstalling: Bool
    let onInstall: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayName)
                if !entry.displaySummary.isEmpty {
                    Text(entry.displaySummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 4) {
                    if entry.kind == .shell {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color.orange)
                    }
                    Text(meta)
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
            Spacer()
            trailing
        }
        .padding(.vertical, 2)
    }

    private var symbol: String {
        NSImage(systemSymbolName: entry.symbol, accessibilityDescription: nil) == nil ? PluginManifest.defaultSymbol : entry.symbol
    }

    /// 类型和作者；运行 Shell 脚本的写明
    private var meta: String {
        var parts: [String] = []
        switch entry.kind {
        case .shell?:
            parts.append(String(localized: "Shell 脚本，会在这台 Mac 上运行命令"))
        case let kind?:
            parts.append(kind.title)
        case nil:
            parts.append(String(localized: "新类型的插件"))
        }
        if !entry.author.isEmpty {
            parts.append(String(localized: "作者：\(entry.author)"))
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var trailing: some View {
        if isInstalling {
            ProgressView()
                .controlSize(.small)
        } else {
            switch state {
            case .notInstalled:
                Button("安装", action: onInstall)
            case .updateAvailable:
                Button("更新", action: onInstall)
            case .installed:
                Label("已安装", systemImage: "checkmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .unsupported:
                Text("要更新 Pop 才能装")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
