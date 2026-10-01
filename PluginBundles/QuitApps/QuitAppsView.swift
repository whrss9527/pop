import AppKit
import SwiftUI
@testable import Pop

/// 「退出 App」卡片：每个 App 一行，点「退出」后等它退出再从列表里拿掉；几秒还没退出就换成「强制退出」。
/// 开着时每 1.5 秒读一次各个 App 用了多少 CPU 时间，和上一次比算出 CPU 占用；可以按内存或者 CPU 排。
@MainActor
final class QuitAppsModel: ObservableObject {
    struct Row: Identifiable {
        var entry: RunningApps.Entry
        let icon: NSImage?
        var state = State.running

        var id: pid_t { entry.pid }
    }

    enum State: Equatable {
        case running
        /// 请它退出了，还没退
        case quitting
        /// 等了一会儿还没退出（可能没有响应，或者在问要不要存）
        case stuck
    }

    /// 退出或强制退出这个进程；返回 false 表示没能发出去（比如已经退出了）
    typealias Terminate = @MainActor (_ pid: pid_t, _ force: Bool) -> Bool
    typealias IsRunning = @MainActor (_ pid: pid_t) -> Bool
    /// 这个 App（连同子进程）一共用了多少 CPU 时间（纳秒）；演示时不读
    typealias CPUTime = (_ pid: pid_t) -> UInt64?

    static let sortKey = "pop.quitApps.sort"

    @Published private(set) var rows: [Row]
    /// 按内存还是 CPU 排；会记住
    @Published var sort: RunningApps.Sort {
        didSet {
            guard sort != oldValue else { return }
            UserDefaults.standard.set(sort.rawValue, forKey: Self.sortKey)
            resort()
        }
    }
    /// 正在确认「退出其他 App」
    @Published var confirmingOthers = false
    /// 唤起时在用的 App：「退出其他 App」时留着它
    let front: pid_t?
    /// 等多久还没退出就算卡住了
    var patience: Duration = .seconds(4)
    private let terminate: Terminate
    private let isRunning: IsRunning
    private let cpuTime: CPUTime?
    private var lastSample: (date: Date, values: [pid_t: UInt64])?
    private var timer: Timer?

    init(rows: [Row], front: pid_t?, terminate: @escaping Terminate, isRunning: @escaping IsRunning, cpuTime: CPUTime? = nil,
         sort: RunningApps.Sort? = nil) {
        self.rows = rows
        self.front = front
        self.terminate = terminate
        self.isRunning = isRunning
        self.cpuTime = cpuTime
        self.sort = sort ?? UserDefaults.standard.string(forKey: Self.sortKey).flatMap(RunningApps.Sort.init(rawValue:)) ?? .memory
        resort()
    }

    /// 按现在的排法重新排一次
    private func resort() {
        let order = RunningApps.sorted(rows.map(\.entry), by: sort).map(\.pid)
        let byPID = Dictionary(rows.map { ($0.entry.pid, $0) }, uniquingKeysWith: { first, _ in first })
        rows = order.compactMap { byPID[$0] }
    }

    /// 开着卡片时读 CPU：先记一次，之后每 1.5 秒算一次占用
    func startSampling() {
        guard cpuTime != nil, timer == nil else { return }
        sampleInBackground()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.sampleInBackground()
            }
        }
    }

    func stopSampling() {
        timer?.invalidate()
        timer = nil
    }

    private func sampleInBackground() {
        guard let cpuTime else { return }
        let pids = rows.map(\.entry.pid)
        Task { [weak self] in
            let values = await runInBackground {
                Dictionary(pids.compactMap { pid in cpuTime(pid).map { (pid, $0) } }, uniquingKeysWith: { first, _ in first })
            }
            self?.apply(values, at: Date())
        }
    }

    /// 记下这一次读到的 CPU 时间，和上一次比算出每个 App 的占用。第一次算出来时按 CPU 排的话排一次，
    /// 之后只换数字、不重新排，免得正要点的那一行跑掉
    func apply(_ values: [pid_t: UInt64], at date: Date) {
        defer { lastSample = (date, values) }
        guard let last = lastSample else { return }
        let seconds = date.timeIntervalSince(last.date)
        let first = rows.allSatisfy { $0.entry.cpu == nil }
        for index in rows.indices {
            let pid = rows[index].entry.pid
            guard let old = last.values[pid], let new = values[pid] else { continue }
            rows[index].entry.cpu = RunningApps.cpuPercent(from: old, to: new, seconds: seconds)
        }
        if first && sort == .cpu {
            resort()
        }
    }

    var total: UInt64 {
        RunningApps.total(rows.map(\.entry))
    }

    var others: [Row] {
        rows.filter { $0.entry.pid != front }
    }

    var frontName: String? {
        rows.first { $0.entry.pid == front }?.entry.name
    }

    var summary: String {
        String(localized: "正在运行 \(rows.count) 个 App，一共占用 \(RunningApps.format(total)) 内存")
    }

    func quit(_ pid: pid_t, force: Bool = false) {
        guard let index = rows.firstIndex(where: { $0.entry.pid == pid }) else { return }
        guard terminate(pid, force) else {
            // 没能发出去：已经退出了就拿掉，还在运行就让用户强制退出
            if isRunning(pid) {
                rows[index].state = .stuck
            } else {
                rows.remove(at: index)
            }
            return
        }
        rows[index].state = .quitting
        watch(pid)
    }

    func quitOthers() {
        confirmingOthers = false
        for row in others where row.state == .running {
            quit(row.entry.pid)
        }
    }

    /// 退出了就从列表里拿掉；等了一会儿还在就标成卡住了，给出「强制退出」
    private func watch(_ pid: pid_t) {
        let patience = self.patience
        Task { [weak self] in
            let deadline = ContinuousClock.now + patience
            while ContinuousClock.now < deadline {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self else { return }
                if !self.isRunning(pid) {
                    withAnimation(Motion.content) { self.rows.removeAll { $0.entry.pid == pid } }
                    return
                }
            }
            guard let self, let index = self.rows.firstIndex(where: { $0.entry.pid == pid }) else { return }
            self.rows[index].state = .stuck
        }
    }
}

struct QuitAppsView: View {
    @ObservedObject var model: QuitAppsModel
    var onClose: () -> Void

    var body: some View {
        CardContainer(title: String(localized: "退出 App"), subtitle: model.summary, width: 420, onClose: onClose) {
            if model.rows.isEmpty {
                Text("没有别的 App 在运行了")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                Picker("排序", selection: $model.sort) {
                    ForEach(RunningApps.Sort.allCases) { sort in
                        Text(sort.title).tag(sort)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 180)
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(model.rows) { row in
                            rowView(row)
                        }
                    }
                }
                .frame(height: min(CGFloat(model.rows.count) * 38, 304))
            }
            Text("没存的文稿，App 会先问你要不要存；点了「退出」几秒还没退出的，可以强制退出")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            footer
        }
        .controlSize(.small)
        .onAppear { model.startSampling() }
        .onDisappear { model.stopSampling() }
    }

    private func rowView(_ row: QuitAppsModel.Row) -> some View {
        HStack(spacing: 10) {
            Group {
                if let icon = row.icon {
                    Image(nsImage: icon)
                        .resizable()
                } else {
                    Image(systemName: "app.dashed")
                        .resizable()
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 24, height: 24)
            Text(row.entry.name)
                .lineLimit(1)
                .truncationMode(.tail)
            if row.entry.pid == model.front {
                Text("在用")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
            }
            Spacer(minLength: 8)
            // 用满一个核以上标橙：多半是它在耗电、发热
            Text(verbatim: row.entry.cpu.map(RunningApps.formatCPU) ?? "")
                .font(.callout.monospacedDigit())
                .foregroundStyle((row.entry.cpu ?? 0) >= 80 ? Color.orange : Color.secondary)
                .frame(width: 46, alignment: .trailing)
            Text(row.entry.memory.map(RunningApps.format) ?? "—")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 60, alignment: .trailing)
            Group {
                switch row.state {
                case .running:
                    Button("退出") { model.quit(row.entry.pid) }
                case .quitting:
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 56)
                case .stuck:
                    Button("强制退出") { model.quit(row.entry.pid, force: true) }
                        .foregroundStyle(.red)
                }
            }
            .frame(minWidth: 64, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .frame(height: 36)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.04)))
        .contextMenu {
            Button("退出") { model.quit(row.entry.pid) }
            Button("强制退出") { model.quit(row.entry.pid, force: true) }
        }
    }

    @ViewBuilder
    private var footer: some View {
        HStack(spacing: 8) {
            if model.confirmingOthers {
                Text(model.frontName.map { String(localized: "除了「\($0)」，退出其他 \(model.others.count) 个 App？") }
                     ?? String(localized: "退出这 \(model.others.count) 个 App？"))
                    .font(.callout)
                    .lineLimit(2)
                Spacer(minLength: 8)
                Button("取消") { model.confirmingOthers = false }
                Button(String(localized: "退出 \(model.others.count) 个")) { model.quitOthers() }
                    .keyboardShortcut(.defaultAction)
            } else {
                Spacer()
                Button("退出其他 App") { model.confirmingOthers = true }
                    .disabled(model.others.filter { $0.state == .running }.isEmpty)
            }
        }
    }
}
