import AppKit
import SwiftUI

// MARK: - 更新

struct UpdateSettingsView: View {
    @EnvironmentObject private var updater: Updater

    var body: some View {
        Form {
            Section("版本") {
                LabeledContent("当前版本") {
                    Text(updater.currentVersion)
                        .textSelection(.enabled)
                }
                LabeledContent("签名") {
                    Text(signatureDescription)
                        .foregroundStyle(.secondary)
                }
                statusRow
            }

            // 更新记录只有中文，中文界面才列出来
            let recent = Localization.isChinese ? Changelog.recent(current: UpdateChecker.currentVersion, releases: Changelog.bundled) : []
            if !recent.isEmpty {
                Section(recent.count > 1 ? String(localized: "这几版更新了什么") : String(localized: "这一版更新了什么")) {
                    ChangelogNotes(releases: recent)
                }
            }

            if let release = updater.release {
                Section(release.isPrerelease ? String(localized: "新版本（测试版）") : String(localized: "新版本")) {
                    ReleaseDetails(release: release, changes: updater.changes)
                    actions(for: release)
                    if let note = updater.relocationNote {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Toggle("自动检查更新", isOn: $updater.automaticChecks)
                Toggle("也接收测试版（预发布版本）", isOn: $updater.includePrereleases)
                if let date = updater.lastChecked {
                    LabeledContent("上次检查") {
                        Text(date.formatted(date: .abbreviated, time: .shortened))
                    }
                }
                HStack {
                    Button("检查更新", action: updater.checkNow)
                        .disabled(updater.isInstalling || updater.phase == .checking)
                    if updater.phase == .checking {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Spacer()
                    Button("所有版本…") {
                        NSWorkspace.shared.open(UpdateChecker.releasesPageURL)
                    }
                }
                if let error = updater.checkError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(Color.red)
                }
            } footer: {
                Text("新版本从 GitHub Releases 下载：先比对 SHA-256 校验和，再检查代码签名，确认无误后替换 Pop.app 并自动重新启动，设置、插件和剪贴板历史都会保留。打开自动检查时，启动后检查一次、之后每 6 小时一次，发现新版本会发通知，菜单栏图标也会变成下载箭头。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if CodeSignature.isAdHoc {
                Section {
                    Text("当前是本地签名（ad-hoc）的测试包：每个版本的签名都不一样，更新后 macOS 会把它当成另一个程序，需要重新授权辅助功能。更新完 Pop 会自动打开设置，在「通用」里点「清除旧的授权记录」再授权一次即可。用固定的签名证书发布后就不用这一步了（见 README）。")
                        .font(.caption)
                        .foregroundStyle(Color.orange)
                }
            }

            if let image = DonateCard.image {
                Section {
                    DonateCard(image: image)
                } header: {
                    Text("请我喝杯咖啡")
                } footer: {
                    Text("Pop 免费开源。觉得好用的话，可以用微信扫一扫请我喝杯咖啡 ☕")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var signatureDescription: String {
        if CodeSignature.isAdHoc { return String(localized: "本地签名（ad-hoc）") }
        return CodeSignature.signerName ?? String(localized: "证书签名")
    }

    @ViewBuilder
    private var statusRow: some View {
        switch updater.phase {
        case .idle:
            LabeledContent("状态") { Text(updater.lastChecked == nil ? String(localized: "还没有检查过") : "—").foregroundStyle(.secondary) }
        case .checking:
            LabeledContent("状态") { Text("正在检查…").foregroundStyle(.secondary) }
        case .upToDate:
            LabeledContent("状态") { Text("已是最新版本").foregroundStyle(.secondary) }
        case .skipped(let release):
            LabeledContent("状态") {
                HStack {
                    Text("有新版本 \(release.version)（已跳过）")
                        .foregroundStyle(.secondary)
                    Button("查看", action: updater.showSkippedVersion)
                        .controlSize(.small)
                }
            }
        case .available(let release):
            LabeledContent("状态") { Text("有新版本 \(release.version)").foregroundStyle(Color.accentColor) }
        case .downloading(_, let fraction):
            LabeledContent("状态") {
                HStack {
                    ProgressView(value: fraction)
                        .frame(width: 160)
                    Text(fraction.map { String(localized: "正在下载 \(Int($0 * 100))%") } ?? String(localized: "正在下载…"))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        case .verifying:
            LabeledContent("状态") { Text("正在校验…").foregroundStyle(.secondary) }
        case .installing:
            LabeledContent("状态") { Text("正在安装，请不要退出 Pop…").foregroundStyle(.secondary) }
        case .relaunching(let release):
            LabeledContent("状态") { Text("已更新到 \(release.version)，正在重新启动…").foregroundStyle(Color.green) }
        case .failed(_, let message):
            LabeledContent("状态") {
                Text(message)
                    .foregroundStyle(Color.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func actions(for release: ReleaseInfo) -> some View {
        HStack {
            switch updater.phase {
            case .available:
                Button("立即更新", action: updater.install)
                    .buttonStyle(.borderedProminent)
                    .disabled(!release.canInstall)
                Button("跳过这个版本", action: updater.skipAvailableVersion)
            case .failed:
                Button("重试", action: updater.install)
                    .buttonStyle(.borderedProminent)
                    .disabled(!release.canInstall)
            case .downloading:
                Button("取消", action: updater.cancel)
            default:
                EmptyView()
            }
            Spacer()
            Button("在网页上查看") {
                NSWorkspace.shared.open(release.pageURL)
            }
        }
        if !release.canInstall {
            Text("这个版本没有附带校验文件，不能在 Pop 里直接安装，请到网页上下载。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// 新版本的标题、发布时间和更新说明（GitHub 上的 Markdown 简单转成富文本）。
struct ReleaseDetails: View {
    let release: ReleaseInfo
    /// 从当前版本到这一版之间每一版的更新记录；空的时候显示这一版的发布说明
    var changes: [Changelog.Release] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(release.title)
                    .font(.headline)
                if let date = release.publishedAt {
                    Text(date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let size = release.archiveSize {
                    Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if !changes.isEmpty {
                if changes.count > 1 {
                    Text("这次更新包含 \(changes.count) 个版本的改动")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ChangelogNotes(releases: changes)
            } else if !release.notes.isEmpty {
                ScrollView {
                    Text(Self.render(release.notes))
                        .font(.callout)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 180)
            }
        }
    }

    /// 标题行变成粗体、列表项变成「•」，其余保留行内格式（粗体、链接、代码）。
    static func render(_ notes: String) -> AttributedString {
        let lines = notes.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") {
                let title = trimmed.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                return title.isEmpty ? "" : "**\(title)**"
            }
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                return "• " + trimmed.dropFirst(2)
            }
            return String(line)
        }
        let markdown = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: markdown, options: options)) ?? AttributedString(markdown)
    }
}

/// App 里带着的更新记录中的几版：版本号、日期和内容
struct ChangelogNotes: View {
    let releases: [Changelog.Release]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(releases, id: \.version) { release in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(verbatim: release.version)
                                .font(.headline)
                            if let date = release.date {
                                Text(verbatim: date)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text(ReleaseDetails.render(release.notes))
                            .font(.callout)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .frame(maxHeight: 220)
    }
}

/// 微信赞赏码：点一下放大，方便手机扫。图片不在（开发时单独运行）就不显示。
struct DonateCard: View {
    @MainActor static let image: NSImage? = Bundle.main.url(forResource: "donate-wechat", withExtension: "png")
        .flatMap { NSImage(contentsOf: $0) }

    let image: NSImage
    @State private var enlarged = false

    var body: some View {
        HStack {
            Spacer()
            Button {
                enlarged = true
            } label: {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 150)
            }
            .buttonStyle(.plain)
            .help("点一下放大")
            .accessibilityLabel("微信赞赏码：请我喝杯咖啡")
            .popover(isPresented: $enlarged) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 330)
                    .padding(12)
            }
            Spacer()
        }
    }
}
