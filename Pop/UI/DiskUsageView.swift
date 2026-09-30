import SwiftUI

/// 占用空间卡片的状态：先在后台扫描（显示进度），扫完按层级列出每一项占了多少，可以点进文件夹、退回上一层，
/// 也可以看整个文件夹里最大的文件；不要的可以移到废纸篓。
@MainActor
final class DiskUsageModel: ObservableObject {
    enum Phase: Equatable {
        case scanning(DiskUsage.Progress)
        case done(DiskUsage.Result)
    }

    enum Mode: String, CaseIterable, Identifiable {
        case folders
        case largest

        var id: String { rawValue }

        var title: String {
            switch self {
            case .folders: return String(localized: "按层级看")
            case .largest: return String(localized: "最大的文件")
            }
        }
    }

    let root: URL
    @Published private(set) var phase: Phase = .scanning(DiskUsage.Progress())
    @Published var mode: Mode = .folders
    /// 正在看的文件夹，从 root 开始一层层点进去
    @Published private(set) var path: [URL] = []
    @Published private(set) var items: [DiskUsage.Item] = []
    /// 移到废纸篓之后的一句话
    @Published private(set) var message: String?
    private var started = false
    private let cancelFlag = CancelFlag()

    init(root: URL) {
        self.root = root
    }

    deinit {
        // 卡片关掉了就不用再扫
        cancelFlag.set()
    }

    /// 扫描时标准化过的位置（和扫描结果里的路径一致）
    var base: URL { result?.root ?? root }

    var current: URL { path.last ?? base }

    var result: DiskUsage.Result? {
        guard case .done(let result) = phase else { return nil }
        return result
    }

    func start() {
        guard !started else { return }
        started = true
        let root = self.root
        let flag = cancelFlag
        Task { [weak self] in
            let result = await runInBackground {
                DiskUsage.scan(root, isCancelled: { flag.isSet }, progress: { progress in
                    Task { @MainActor [weak self] in
                        guard let self, case .scanning = self.phase else { return }
                        self.phase = .scanning(progress)
                    }
                })
            }
            guard let self, !flag.isSet else { return }
            self.phase = .done(result)
            await self.reload()
        }
    }

    func cancel() {
        cancelFlag.set()
    }

    func open(_ item: DiskUsage.Item) {
        guard item.isFolder else { return }
        path.append(item.url)
        mode = .folders
        Task { await reload() }
    }

    func goUp() {
        guard !path.isEmpty else { return }
        path.removeLast()
        Task { await reload() }
    }

    /// 回到某一层（点路径上的名字）
    func go(to index: Int) {
        guard index < path.count else { return }
        path = Array(path.prefix(index))
        Task { await reload() }
    }

    func trash(_ item: DiskUsage.Item) {
        guard let result else { return }
        let outcome = DuplicateFinder.trash([item.url])
        if let failure = outcome.failures.first {
            message = String(localized: "没能移到废纸篓：\(failure)")
            return
        }
        phase = .done(DiskUsage.removing(item, from: result))
        items.removeAll { $0.url == item.url }
        message = String(localized: "已把「\(item.url.lastPathComponent)」移到废纸篓，腾出 \(FileInfo.shortSize(item.size))，可以从废纸篓放回")
    }

    private func reload() async {
        guard let result else { return }
        let folder = current
        let children = await runInBackground { DiskUsage.children(of: folder, in: result) }
        // 这期间又点到别的文件夹了，就不用这次的
        guard folder == current else { return }
        items = children
    }
}

struct DiskUsageView: View {
    @ObservedObject var model: DiskUsageModel
    var onReveal: ([URL]) -> Void
    var onClose: () -> Void

    /// 一次最多列多少项
    private let shown = 200

    var body: some View {
        CardContainer(title: String(localized: "占用空间"), subtitle: model.current.lastPathComponent, width: 480, onClose: {
            model.cancel()
            onClose()
        }) {
            switch model.phase {
            case .scanning(let progress):
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text(progress.files == 0 ? String(localized: "正在看里面有什么…")
                        : String(localized: "已经看了 \(progress.files) 个文件，一共 \(FileInfo.shortSize(progress.size))…"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            case .done(let result):
                content(result)
            }
        }
        .task {
            model.start()
        }
    }

    @ViewBuilder
    private func content(_ result: DiskUsage.Result) -> some View {
        let totals = result.totals(of: model.current)
        HStack(spacing: 8) {
            Picker("", selection: $model.mode) {
                ForEach(DiskUsageModel.Mode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Spacer()
            Text("\(FileInfo.shortSize(totals.size))，\(totals.files) 个文件")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .controlSize(.small)

        switch model.mode {
        case .folders:
            if !model.path.isEmpty {
                breadcrumb
            }
            list(model.items, total: totals.size, relativeTo: nil)
        case .largest:
            list(result.largest, total: result.total.size, relativeTo: result.root)
        }

        if result.truncated || model.message != nil {
            Text(model.message ?? String(localized: "文件太多，只看了前 \(DiskUsage.fileLimit) 个"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    /// 「‹ 资料 › 下载 › 旧照片」，点名字回到那一层
    private var breadcrumb: some View {
        HStack(spacing: 4) {
            Button {
                model.goUp()
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)
            .help("上一层")
            let names = [model.base] + model.path
            ForEach(Array(names.enumerated()), id: \.offset) { index, url in
                if index > 0 {
                    Image(systemName: "chevron.compact.right")
                        .foregroundStyle(.tertiary)
                }
                Button(url.lastPathComponent) { model.go(to: index) }
                    .buttonStyle(.link)
                    .disabled(index == names.count - 1)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .font(.caption)
    }

    @ViewBuilder
    private func list(_ items: [DiskUsage.Item], total: Int64, relativeTo root: URL?) -> some View {
        if items.isEmpty {
            Text("这里是空的")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(items.prefix(shown)) { item in
                        row(item, total: total, relativeTo: root)
                    }
                    if items.count > shown {
                        Text("……还有 \(items.count - shown) 项")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.trailing, 6)
            }
            .frame(height: min(CGFloat(min(items.count, shown)) * 34 + 8, 320))
        }
    }

    private func row(_ item: DiskUsage.Item, total: Int64, relativeTo root: URL?) -> some View {
        let share = total > 0 ? Double(item.size) / Double(total) : 0
        let fraction = min(max(share, 0), 1)
        let tip: String = item.isFolder ? String(localized: "\(item.files) 个文件，点一下进去看") : item.url.path(percentEncoded: false)
        return HStack(spacing: 8) {
            Image(systemName: item.isFolder ? "folder.fill" : "doc")
                .foregroundStyle(item.isFolder ? Color.accentColor : Color.secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 3) {
                Text(root.map { DiskUsage.relativePath(item.url, in: $0) } ?? item.url.lastPathComponent)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.middle)
                GeometryReader { geometry in
                    Capsule()
                        .fill(Color.accentColor.opacity(0.55))
                        .frame(width: max(geometry.size.width * fraction, 2))
                }
                .frame(height: 4)
            }
            Text(FileInfo.shortSize(item.size))
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .trailing)
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .opacity(item.isFolder ? 1 : 0)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture {
            model.open(item)
        }
        .help(tip)
        .contextMenu {
            Button("在访达中显示") { onReveal([item.url]) }
            Button("移到废纸篓") { model.trash(item) }
        }
    }
}
