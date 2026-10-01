import AppKit
import SwiftUI
@testable import Pop

/// 磁盘测速卡片：选磁盘和测试文件多大，开始以后先写后读，两个大数字跟着跳，测完写着平均速度，可以复制
@MainActor
final class DiskSpeedModel: ObservableObject {
    enum Size: Int64, CaseIterable, Identifiable {
        case small = 256_000_000
        case medium = 1_000_000_000
        case large = 4_000_000_000

        var id: Self { self }

        var title: String {
            switch self {
            case .small: return "256 MB"
            case .medium: return "1 GB"
            case .large: return "4 GB"
            }
        }
    }

    enum Phase: Equatable {
        case idle
        case running(DiskSpeed.Pass)
        case done
        case failed(String)
    }

    static let sizeKey = "pop.diskSpeed.size"

    @Published private(set) var volumes: [DiskSpeed.Volume]
    @Published var selectedID: URL? {
        didSet {
            if selectedID != oldValue, phase != .idle, !isRunning {
                reset()
            }
        }
    }
    @Published var size: Size {
        didSet { UserDefaults.standard.set(size.rawValue, forKey: Self.sizeKey) }
    }
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var writeSpeed: Double?
    @Published private(set) var readSpeed: Double?
    /// 正在测的那一项此刻的速度
    @Published private(set) var current: Double?
    @Published private(set) var fraction: Double = 0

    /// 测试时把测试文件的大小换小
    private let bytesOverride: Int64?
    private let folderFor: (DiskSpeed.Volume) -> URL
    private let cancelled = SpeedTestStop()
    private var task: Task<Void, Never>?
    /// 写的那一遍到现在的平均速度：开始读以后先显示它，测完换成算上落盘时间的
    private var writeAverage: Double?

    init(volumes: [DiskSpeed.Volume] = DiskSpeed.volumes(), selecting volume: URL? = nil, folderFor: @escaping (DiskSpeed.Volume) -> URL = DiskSpeed.folder(for:),
         bytesOverride: Int64? = nil) {
        self.volumes = volumes
        self.folderFor = folderFor
        self.bytesOverride = bytesOverride
        selectedID = volumes.first { $0.url == volume }?.url ?? volumes.first?.url
        size = Size(rawValue: Int64(UserDefaults.standard.integer(forKey: Self.sizeKey))) ?? .medium
    }

    var selected: DiskSpeed.Volume? {
        volumes.first { $0.url == selectedID } ?? volumes.first
    }

    var isRunning: Bool {
        if case .running = phase { return true }
        return false
    }

    private var bytes: Int64 {
        bytesOverride ?? size.rawValue
    }

    /// 空间不够写测试文件时的说明
    var spaceProblem: String? {
        guard let volume = selected, volume.available < bytes + DiskSpeed.headroom else { return nil }
        return String(localized: "「\(volume.name)」上的空间不够，换小一点的测试文件")
    }

    /// 复制的文字：「T7 Shield（ExFAT · 外接 · …）\n写入 921 MB/s\n读取 1,012 MB/s」
    var resultText: String? {
        guard phase == .done, let volume = selected, let writeSpeed, let readSpeed else { return nil }
        return [
            String(localized: "\(volume.name)（\(DiskSpeed.describe(volume))）"),
            String(localized: "写入 \(DiskSpeed.speedText(writeSpeed))"),
            String(localized: "读取 \(DiskSpeed.speedText(readSpeed))"),
            String(localized: "测试文件 \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))"),
        ].joined(separator: "\n")
    }

    func start() {
        guard !isRunning, let volume = selected, spaceProblem == nil else { return }
        reset()
        cancelled.reset()
        phase = .running(.write)
        let folder = folderFor(volume)
        let bytes = bytes
        let cancelled = cancelled
        task = Task {
            let result = await runInBackground { () -> Result<DiskSpeed.Speeds, Error> in
                Result {
                    try DiskSpeed.measure(in: folder, size: bytes, isCancelled: { cancelled.isSet }) { progress in
                        DispatchQueue.main.async { [weak self] in
                            MainActor.assumeIsolated {
                                self?.show(progress)
                            }
                        }
                    }
                }
            }
            switch result {
            case .success(let speeds):
                writeSpeed = speeds.write
                readSpeed = speeds.read
                current = nil
                fraction = 1
                phase = .done
            case .failure(let error as DiskSpeed.Failure):
                phase = .failed(error.message)
            case .failure(is CancellationError):
                reset()
            case .failure(let error):
                phase = .failed(error.localizedDescription)
            }
        }
    }

    /// 停下来：测试文件删掉，数字清空
    func stop() {
        cancelled.set()
    }

    /// 等测完或者停下（测试用）
    func waitUntilDone() async {
        await task?.value
    }

    private func show(_ progress: DiskSpeed.Progress) {
        guard isRunning else { return }
        phase = .running(progress.pass)
        current = progress.speed
        // 进度：写占前一半，读占后一半
        let part = progress.total > 0 ? Double(progress.done) / Double(progress.total) : 0
        fraction = progress.pass == .write ? part / 2 : 0.5 + part / 2
        if progress.pass == .write {
            writeAverage = progress.average
        } else if writeSpeed == nil {
            writeSpeed = writeAverage
        }
    }

    private func reset() {
        phase = .idle
        writeAverage = nil
        writeSpeed = nil
        readSpeed = nil
        current = nil
        fraction = 0
    }

    /// 演示用：直接显示测完的样子
    func showResult(write: Double, read: Double) {
        writeSpeed = write
        readSpeed = read
        fraction = 1
        phase = .done
    }
}

/// 后台线程能读、主线程能设的「停下来」开关（每次开始测速时清掉）
private final class SpeedTestStop: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isSet: Bool {
        lock.withLock { value }
    }

    func set() {
        lock.withLock { value = true }
    }

    func reset() {
        lock.withLock { value = false }
    }
}

struct DiskSpeedView: View {
    @ObservedObject var model: DiskSpeedModel
    var onCopy: (String) -> Void
    var onClose: () -> Void

    var body: some View {
        CardContainer(title: String(localized: "磁盘测速"), subtitle: model.selected?.name, width: 380, onClose: onClose) {
            HStack(spacing: 8) {
                Picker("磁盘", selection: $model.selectedID) {
                    ForEach(model.volumes) { volume in
                        Text(verbatim: volume.name).tag(Optional(volume.url))
                    }
                }
                .labelsHidden()
                .fixedSize()
                Spacer(minLength: 4)
                Picker("测试文件", selection: $model.size) {
                    ForEach(DiskSpeedModel.Size.allCases) { size in
                        Text(verbatim: size.title).tag(size)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help("测试文件越大，结果越接近长时间拷大文件的速度")
            }
            .disabled(model.isRunning)
            if let volume = model.selected {
                Text(DiskSpeed.describe(volume))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                SpeedTile(title: String(localized: "写入"), symbol: "arrow.down.to.line", speed: model.phase == .running(.write) ? model.current : model.writeSpeed,
                          active: model.phase == .running(.write))
                SpeedTile(title: String(localized: "读取"), symbol: "arrow.up.to.line", speed: model.phase == .running(.read) ? model.current : model.readSpeed,
                          active: model.phase == .running(.read))
            }
            if model.isRunning {
                ProgressView(value: model.fraction)
            }
            if case .failed(let message) = model.phase {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if let problem = model.spaceProblem {
                Text(problem)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            HStack(spacing: 8) {
                Text("先写后读，绕过系统缓存；测完删掉测试文件")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                if let text = model.resultText {
                    Button("复制结果") { onCopy(text) }
                }
                if model.isRunning {
                    Button("停止", action: model.stop)
                } else {
                    Button(model.phase == .done ? String(localized: "再测一次") : String(localized: "开始测速"), action: model.start)
                        .keyboardShortcut(.defaultAction)
                        .disabled(model.selected == nil || model.spaceProblem != nil)
                }
            }
        }
        .controlSize(.small)
        .onDisappear { model.stop() }
    }
}

/// 一项速度：大数字和 MB/s，正在测的那项亮起来
private struct SpeedTile: View {
    let title: String
    let symbol: String
    let speed: Double?
    let active: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(title, systemImage: symbol)
                .font(.caption)
                .foregroundStyle(active ? Color.accentColor : Color.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(verbatim: speed.map { DiskSpeed.numberText($0 / 1_000_000) } ?? "—")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(verbatim: "MB/s")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(active ? 0.08 : 0.04)))
        .animation(.easeOut(duration: 0.2), value: speed)
    }
}
