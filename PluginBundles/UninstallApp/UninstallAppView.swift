import AppKit
import SwiftUI
@testable import Pop

/// 卸载 App 的卡片：列出 App 本身和找到的留下的文件、各占多大，勾上的一起移到废纸篓。
@MainActor
final class UninstallAppModel: ObservableObject {
    enum Phase: Equatable {
        case choosing
        case working
        /// 移走了几项、腾出多少空间、哪些没能移走
        case done(trashed: Int, freed: UInt64, failed: [String])
        case failed(String)
    }

    let app: AppUninstaller.App
    let icon: NSImage?
    let items: [AppUninstaller.Item]
    @Published var checked: Set<URL>
    @Published private(set) var sizes: [URL: UInt64]
    /// 还在算大小
    @Published private(set) var measuring: Bool
    @Published private(set) var phase = Phase.choosing
    @Published private(set) var running: Bool

    private let isRunning: () -> Bool
    private let quit: () -> Void
    private let recycle: ([URL]) async -> [URL]
    /// 请 App 退出以后最多等多久（秒）
    private let patience: Double

    init(app: AppUninstaller.App, icon: NSImage?, items: [AppUninstaller.Item], sizes: [URL: UInt64]? = nil,
         isRunning: @escaping () -> Bool, quit: @escaping () -> Void, recycle: @escaping ([URL]) async -> [URL], patience: Double = 5) {
        self.app = app
        self.icon = icon
        self.items = items
        self.sizes = sizes ?? [:]
        measuring = sizes == nil
        // 有疑问的默认不勾
        checked = Set(items.filter { $0.doubt == nil }.map(\.url))
        self.isRunning = isRunning
        self.quit = quit
        self.recycle = recycle
        self.patience = patience
        running = isRunning()
    }

    /// 在后台一项项算大小，算好一项填一项
    func measure() {
        guard measuring else { return }
        let urls = items.map(\.url)
        Task {
            for url in urls {
                let size = await runInBackground { AppUninstaller.size(of: url) }
                if let size { sizes[url] = size }
            }
            measuring = false
        }
    }

    func isChecked(_ item: AppUninstaller.Item) -> Bool {
        checked.contains(item.url)
    }

    func toggle(_ item: AppUninstaller.Item) {
        if checked.contains(item.url) {
            checked.remove(item.url)
        } else {
            checked.insert(item.url)
        }
    }

    /// 勾上的一共多大
    var total: UInt64 {
        items.filter { checked.contains($0.url) }.reduce(0) { $0 + (sizes[$1.url] ?? 0) }
    }

    var leftovers: Int {
        items.count - 1
    }

    var summary: String {
        if checked.isEmpty { return String(localized: "勾上要移到废纸篓的项目") }
        if measuring { return String(localized: "正在算大小…") }
        let keepsApp = !checked.contains(app.url)
        let count = checked.count
        let size = AppUninstaller.format(total)
        return keepsApp
            ? String(localized: "把勾上的 \(count) 项（\(size)）移到废纸篓，App 留着，下次打开就像刚装好一样")
            : String(localized: "把勾上的 \(count) 项（\(size)）移到废纸篓；需要时可以从废纸篓放回原处")
    }

    var actionTitle: String {
        if !checked.contains(app.url) { return String(localized: "清掉这些文件") }
        return running ? String(localized: "退出并卸载") : String(localized: "移到废纸篓")
    }

    func uninstall() {
        guard phase == .choosing, !checked.isEmpty else { return }
        phase = .working
        let chosen = items.filter { checked.contains($0.url) }
        Task {
            if isRunning() {
                quit()
                let deadline = Date().addingTimeInterval(patience)
                while isRunning(), Date() < deadline {
                    try? await Task.sleep(for: .milliseconds(250))
                }
                running = isRunning()
                if running {
                    phase = .failed(String(localized: "「\(app.name)」还没有退出（可能在问要不要存文稿），退出以后再卸载"))
                    return
                }
            }
            let trashed = Set(await recycle(chosen.map(\.url)).map(Self.key))
            let moved = chosen.filter { trashed.contains(Self.key($0.url)) }
            let failed = chosen.filter { !trashed.contains(Self.key($0.url)) }.map { AppUninstaller.displayPath($0.url) }
            phase = .done(trashed: moved.count, freed: moved.reduce(0) { $0 + (sizes[$1.url] ?? 0) }, failed: failed)
        }
    }

    /// 比较路径时去掉末尾的斜杠
    nonisolated static func key(_ url: URL) -> String {
        var path = url.standardizedFileURL.path(percentEncoded: false)
        while path.count > 1, path.hasSuffix("/") {
            path.removeLast()
        }
        return path
    }
}

struct UninstallAppView: View {
    @ObservedObject var model: UninstallAppModel
    var onReveal: (URL) -> Void
    var onOpenTrash: () -> Void
    var onClose: () -> Void

    var body: some View {
        CardContainer(title: String(localized: "卸载 App"), subtitle: model.app.name, width: 460, onClose: onClose) {
            header
            switch model.phase {
            case .choosing, .working:
                chooser
            case .done(let trashed, let freed, let failed):
                Text(String(localized: "已把 \(trashed) 项移到废纸篓，腾出 \(AppUninstaller.format(freed))"))
                    .font(.callout)
                if !failed.isEmpty {
                    Text(String(localized: "有 \(failed.count) 项没能移到废纸篓：\(failed.joined(separator: String(localized: "、")))"))
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 8) {
                    Spacer()
                    Button("打开废纸篓", action: onOpenTrash)
                    Button("完成", action: onClose)
                        .keyboardShortcut(.defaultAction)
                }
            case .failed(let message):
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button("完成", action: onClose)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .controlSize(.small)
    }

    private var header: some View {
        HStack(spacing: 10) {
            if let icon = model.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 40, height: 40)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(model.app.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text([model.app.version.map { String(localized: "版本 \($0)") }, model.app.bundleID].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(AppUninstaller.format(model.total))
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                Text(String(localized: "留下的文件 \(model.leftovers) 处"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var chooser: some View {
        ScrollView {
            VStack(spacing: 2) {
                ForEach(model.items) { item in
                    row(item)
                }
            }
        }
        .frame(height: min(CGFloat(model.items.count) * 36, 252))
        if model.running {
            Label(String(localized: "「\(model.app.name)」正在运行，卸载前会先退出它"), systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
        }
        Text(model.summary)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        HStack(spacing: 8) {
            Spacer()
            if model.phase == .working {
                ProgressView()
                    .controlSize(.small)
            }
            Button(model.actionTitle) { model.uninstall() }
                .disabled(model.checked.isEmpty || model.phase == .working)
        }
    }

    private func row(_ item: AppUninstaller.Item) -> some View {
        HStack(spacing: 8) {
            Toggle(item.place.title, isOn: Binding(get: { model.isChecked(item) }, set: { _ in model.toggle(item) }))
                .toggleStyle(.checkbox)
                .labelsHidden()
            Image(systemName: item.place.symbol)
                .frame(width: 16)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(item.place.title)
                    if item.doubt != nil {
                        Image(systemName: "questionmark.circle")
                            .foregroundStyle(.secondary)
                    }
                }
                Text(AppUninstaller.displayPath(item.url))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Text(model.sizes[item.url].map(AppUninstaller.format) ?? (model.measuring ? "…" : "—"))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 8)
        .frame(height: 34)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04)))
        .contentShape(Rectangle())
        .help(item.doubt?.note ?? AppUninstaller.displayPath(item.url))
        .contextMenu {
            Button("在访达中显示") { onReveal(item.url) }
        }
    }
}
