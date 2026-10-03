import SwiftUI
@testable import Pop

/// 后台线程和界面之间共用的「不用再算了」标记
final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set() {
        lock.lock()
        value = true
        lock.unlock()
    }
}

/// 查找重复文件卡片的状态：先在后台扫描（显示进度），扫完列出每一组，可以只留一个、其余移到废纸篓。
@MainActor
final class DuplicatesModel: ObservableObject {
    enum Phase: Equatable {
        case scanning(DuplicateFinder.Progress)
        case done(DuplicateFinder.Result)
    }

    let roots: [URL]
    @Published private(set) var phase: Phase = .scanning(DuplicateFinder.Progress())
    /// 移到废纸篓之后的一句话
    @Published private(set) var message: String?
    private var started = false
    private let cancelFlag = CancelFlag()

    init(roots: [URL]) {
        self.roots = roots
    }

    deinit {
        // 卡片关掉了就不用再扫
        cancelFlag.set()
    }

    func start() {
        guard !started else { return }
        started = true
        let roots = self.roots
        let flag = cancelFlag
        Task { [weak self] in
            let result = await runInBackground {
                DuplicateFinder.find(in: roots, isCancelled: { flag.isSet }, progress: { progress in
                    Task { @MainActor [weak self] in
                        guard let self, case .scanning = self.phase else { return }
                        self.phase = .scanning(progress)
                    }
                })
            }
            guard let self, !flag.isSet else { return }
            self.phase = .done(result)
        }
    }

    func cancel() {
        cancelFlag.set()
    }

    /// 正在移到废纸篓：按钮先不能点
    @Published private(set) var isTrashing = false

    /// 每组留下最早的那个，其余的移到废纸篓
    func keepOne(in groups: [DuplicateFinder.Group]) async {
        await trash(groups.flatMap { $0.files.dropFirst() })
    }

    /// 一个个移到废纸篓：几千个要好一会儿，放在后台移
    func trash(_ urls: [URL]) async {
        guard case .done = phase, !urls.isEmpty, !isTrashing else { return }
        isTrashing = true
        let outcome = await runInBackground { DuplicateFinder.trash(urls) }
        isTrashing = false
        guard case .done(var result) = phase else { return }
        let moved = Set(outcome.moved)
        result.groups = result.groups.compactMap { group in
            var remaining = group
            remaining.files.removeAll { moved.contains($0) }
            return remaining.files.count > 1 ? remaining : nil
        }
        phase = .done(result)
        if let failure = outcome.failures.first {
            message = String(localized: "有 \(outcome.failures.count) 个没能移走：\(failure)")
        } else {
            message = String(localized: "已把 \(outcome.moved.count) 个文件移到废纸篓，可以从废纸篓放回")
        }
    }
}

struct DuplicatesView: View {
    @ObservedObject var model: DuplicatesModel
    var onReveal: ([URL]) -> Void
    var onClose: () -> Void

    private var subtitle: String {
        model.roots.count == 1 ? model.roots[0].lastPathComponent : String(localized: "\(model.roots.count) 个文件夹")
    }

    var body: some View {
        CardContainer(title: String(localized: "查找重复文件"), subtitle: subtitle, width: 500, onClose: {
            model.cancel()
            onClose()
        }) {
            switch model.phase {
            case .scanning(let progress):
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text(progress.toHash == 0 ? String(localized: "正在列出文件，已经找到 \(progress.scanned) 个…")
                        : String(localized: "正在比较内容：\(progress.hashed) / \(progress.toHash)"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            case .done(let result):
                results(result)
            }
        }
        .task {
            model.start()
        }
    }

    @ViewBuilder
    private func results(_ result: DuplicateFinder.Result) -> some View {
        let limited = result.truncated ? String(localized: "（文件太多，只看了前 \(DuplicateFinder.fileLimit) 个）") : ""
        if result.groups.isEmpty {
            Text("看了 \(result.scanned) 个文件，没有内容完全一样的。\(limited)")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            if let message = model.message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            Text("看了 \(result.scanned) 个文件，有 \(result.groups.count) 组内容完全一样，每组只留一个可以腾出 \(FileInfo.shortSize(result.wasted))。\(limited)")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(result.groups) { group in
                        groupView(group)
                    }
                }
                .padding(.trailing, 6)
            }
            .frame(height: min(CGFloat(result.groups.reduce(0) { $0 + $1.files.count + 1 }) * 19 + 12, 300))
            HStack(spacing: 8) {
                if let message = model.message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Button("每组只留一个") { Task { await model.keepOne(in: result.groups) } }
                    .disabled(model.isTrashing)
                    .help("每组留下最早的那个，其余的移到废纸篓（可以从废纸篓放回）")
            }
            .controlSize(.small)
        }
    }

    private func groupView(_ group: DuplicateFinder.Group) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(group.files[0].lastPathComponent)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(group.files.count) 个，每个 \(FileInfo.shortSize(group.size))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize()
                Spacer(minLength: 8)
                Button("在访达中显示") { onReveal(group.files) }
                    .buttonStyle(.link)
                    .font(.caption)
                Button("只留一个") { Task { await model.keepOne(in: [group]) } }
                    .disabled(model.isTrashing)
                    .buttonStyle(.link)
                    .font(.caption)
            }
            ForEach(Array(group.files.enumerated()), id: \.offset) { index, file in
                HStack(spacing: 6) {
                    // 每一行都占着「留」字的宽度（英文的 Keep 也放得下），路径对齐
                    ZStack(alignment: .leading) {
                        Text("留").hidden()
                        if index == 0 {
                            Text("留").foregroundStyle(.green)
                        }
                    }
                    .font(.caption2)
                    .fixedSize()
                    Text(Self.abbreviated(file))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                        .help(file.path(percentEncoded: false))
                }
                .contextMenu {
                    Button("在访达中显示") { onReveal([file]) }
                    Button("移到废纸篓") { Task { await model.trash([file]) } }
                        .disabled(model.isTrashing)
                }
            }
        }
    }

    /// 家目录换成 ~
    static func abbreviated(_ url: URL) -> String {
        (url.path(percentEncoded: false) as NSString).abbreviatingWithTildeInPath
    }
}
