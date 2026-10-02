import AppKit
import SwiftUI

struct ClipboardSettingsView: View {
    @EnvironmentObject private var store: SettingsStore
    @EnvironmentObject private var clipboard: ClipboardService

    var body: some View {
        Form {
            Section {
                Toggle("记录剪贴板历史", isOn: store.binding(\.clipboard.enabled))
                Picker("打开历史的快捷键", selection: store.binding(\.clipboard.hotKey)) {
                    ForEach(HotKeyPreset.available(keeping: store.settings.clipboard.hotKey)) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                .disabled(!store.settings.clipboard.enabled)
            } footer: {
                Text("在历史面板里输入文字搜索，↑↓ 选择，回车粘贴到当前 App，⌘1–9 直接粘贴前 9 条，⌘P 固定常用的内容。圆盘里的「剪贴板」格子和菜单栏图标也能打开它。⌘⇧V 在部分 App 里是「粘贴并匹配样式」，介意的话可以换一个快捷键。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("保存时间", selection: store.binding(\.clipboard.retentionDays)) {
                    ForEach(ClipboardSettings.retentionChoices, id: \.self) { days in
                        Text(ClipboardSettings.retentionTitle(days)).tag(days)
                    }
                }
                Picker("最多保存", selection: store.binding(\.clipboard.maxItems)) {
                    ForEach(ClipboardSettings.maxItemChoices, id: \.self) { count in
                        Text("\(count) 条").tag(count)
                    }
                }
                Toggle("记录图片", isOn: store.binding(\.clipboard.recordImages))
                Toggle("搜索图片里的文字", isOn: store.binding(\.clipboard.searchImageText))
                    .disabled(!store.settings.clipboard.recordImages)
                    .help("在本机识别历史里图片上的文字（不联网），搜索时一起找")
                LabeledContent("已保存") {
                    Text("\(clipboard.itemCount) 条，共 \(ByteCountFormatter.string(fromByteCount: Int64(clipboard.totalBytes), countStyle: .file))")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Button("立即清理过期记录") {
                        clipboard.cleanup()
                    }
                    Button("清空历史…", role: .destructive, action: confirmClear)
                    Spacer()
                    Button("在访达中显示") {
                        NSWorkspace.shared.activateFileViewerSelecting([clipboard.store.directory])
                    }
                }
            } header: {
                Text("保存")
            } footer: {
                Text("历史只保存在这台 Mac 上（~/Library/Application Support/Pop/Clipboard），不会上传到 iCloud。超过保存时间或条数上限的记录每小时自动清理一次，固定的记录不会被清理。图片里的文字也是在这台 Mac 上识别的，不联网。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("复制链接时去掉跟踪参数", isOn: store.binding(\.clipboard.cleanLinks))
            } footer: {
                Text("复制的内容只是一个网址、而且带着 utm_source、fbclid、spm 这类跟踪参数时，自动换成去掉这些参数的网址，打开的还是同一个页面。不开剪贴板历史也能用。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                BundleIDListView(keyPath: \.clipboard.ignoredBundleIDs)
            } header: {
                Text("不记录这些 App 里复制的内容")
            } footer: {
                Text("密码管理器把内容标记为「敏感」时，本来就不会被记录；这里可以再加上其他不想记录的 App。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            SnippetsSection()
        }
        .formStyle(.grouped)
        .onAppear {
            clipboard.refreshStatistics()
        }
    }

    private func confirmClear() {
        let alert = NSAlert()
        alert.messageText = String(localized: "清空剪贴板历史？")
        alert.informativeText = String(localized: "删除后无法恢复。")
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "清空（保留固定的）"))
        alert.addButton(withTitle: String(localized: "全部清空"))
        alert.addButton(withTitle: String(localized: "取消"))
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            clipboard.clear(keepPinned: true)
        case .alertSecondButtonReturn:
            clipboard.clear(keepPinned: false)
        default:
            break
        }
    }
}
