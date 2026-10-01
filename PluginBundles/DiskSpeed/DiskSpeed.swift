import Foundation
@testable import Pop

/// 磁盘测速：在要测的磁盘上写一个测试文件再读回来，算出连续写入、读取的速度。
/// 写读都绕过系统缓存（F_NOCACHE），写完用 F_FULLFSYNC 真正落盘再停表；数据是随机的，压缩不了。测完删掉测试文件。
enum DiskSpeed {
    struct Volume: Identifiable, Equatable {
        /// 挂载的位置（启动磁盘是「/」）
        let url: URL
        let name: String
        /// 「APFS」「ExFAT」……
        let format: String?
        let isInternal: Bool
        let isRemovable: Bool
        let isLocal: Bool
        let total: Int64
        let available: Int64

        var id: URL { url }
        var isStartup: Bool { url.path(percentEncoded: false) == "/" }
    }

    enum Pass: Equatable {
        case write
        case read
    }

    struct Progress: Equatable {
        let pass: Pass
        let done: Int64
        let total: Int64
        /// 最近半秒左右的速度（字节每秒）
        let speed: Double
    }

    struct Speeds: Equatable {
        /// 字节每秒
        let write: Double
        let read: Double
    }

    struct Failure: Error, Equatable {
        let message: String
    }

    /// 测试文件写多大：另外还要留出这么多空间
    static let headroom: Int64 = 200_000_000

    // MARK: - 磁盘

    private static let keys: Set<URLResourceKey> = [.volumeLocalizedNameKey, .volumeLocalizedFormatDescriptionKey, .volumeIsInternalKey,
                                                    .volumeIsRemovableKey, .volumeIsLocalKey, .volumeTotalCapacityKey,
                                                    .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey,
                                                    .volumeIsReadOnlyKey]

    /// 能测的磁盘：启动磁盘在前，其他按名字排；只读的不要
    static func volumes() -> [Volume] {
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: Array(keys), options: [.skipHiddenVolumes]) ?? []
        // 启动磁盘的数据卷、预启动这些系统卷不单列
        return urls.filter { !$0.path(percentEncoded: false).hasPrefix("/System/Volumes/") }.compactMap(volume(at:))
            .sorted { ($0.isStartup ? 0 : 1, $0.name) < ($1.isStartup ? 0 : 1, $1.name) }
    }

    /// 某个文件或文件夹所在的磁盘；用户的文件在启动磁盘的数据卷（/System/Volumes/Data）上，算启动磁盘
    static func volume(containing url: URL) -> Volume? {
        guard let root = try? url.resourceValues(forKeys: [.volumeURLKey]).volume else { return nil }
        if root.path(percentEncoded: false).hasPrefix("/System/Volumes/") {
            return volume(at: URL(fileURLWithPath: "/"))
        }
        return volume(at: root)
    }

    private static func volume(at url: URL) -> Volume? {
        guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
        // 启动磁盘的系统卷本身是只读的，测试文件写在数据卷上的临时文件夹里；别的只读磁盘测不了
        guard values.volumeIsReadOnly != true || url.path(percentEncoded: false) == "/" else { return nil }
        let available = values.volumeAvailableCapacityForImportantUsage ?? values.volumeAvailableCapacity.map(Int64.init) ?? 0
        return Volume(url: url, name: values.volumeLocalizedName ?? url.lastPathComponent, format: values.volumeLocalizedFormatDescription,
                      isInternal: values.volumeIsInternal ?? false, isRemovable: values.volumeIsRemovable ?? false,
                      isLocal: values.volumeIsLocal ?? true, total: Int64(values.volumeTotalCapacity ?? 0), available: available)
    }

    /// 测试文件放在哪：启动磁盘上放进临时文件夹（根目录写不了），别的磁盘放在最上层
    static func folder(for volume: Volume) -> URL {
        volume.isStartup ? FileManager.default.temporaryDirectory : volume.url
    }

    // MARK: - 测

    /// 写 size 字节再读回来；isCancelled 返回 true 时停下（扔出 CancellationError），progress 在后台线程调用
    static func measure(in folder: URL, size: Int64, chunk: Int = 8 << 20, isCancelled: () -> Bool = { false },
                        progress: (Progress) -> Void = { _ in }) throws -> Speeds {
        let file = folder.appending(path: ".pop-disk-speed-\(UUID().uuidString)")
        let path = file.path(percentEncoded: false)
        defer { unlink(path) }
        var buffer = [UInt8](repeating: 0, count: chunk)
        buffer.withUnsafeMutableBytes { arc4random_buf($0.baseAddress, chunk) }

        // 写
        let output = open(path, O_CREAT | O_WRONLY | O_TRUNC, 0o600)
        guard output >= 0 else { throw Failure(message: String(localized: "这里写不了文件：\(String(cString: strerror(errno)))")) }
        _ = fcntl(output, F_NOCACHE, 1)
        var meter = Meter(pass: .write, total: size)
        var written: Int64 = 0
        while written < size {
            if isCancelled() {
                close(output)
                throw CancellationError()
            }
            let count = Int(min(Int64(chunk), size - written))
            let result = buffer.withUnsafeBytes { Darwin.write(output, $0.baseAddress, count) }
            guard result == count else {
                let reason = String(cString: strerror(errno))
                close(output)
                throw Failure(message: String(localized: "写到一半出错了：\(reason)"))
            }
            written += Int64(result)
            progress(meter.add(Int64(result)))
        }
        _ = fcntl(output, F_FULLFSYNC)
        close(output)
        let writeSpeed = meter.average

        // 读
        let input = open(path, O_RDONLY)
        guard input >= 0 else { throw Failure(message: String(localized: "读不了测试文件：\(String(cString: strerror(errno)))")) }
        defer { close(input) }
        _ = fcntl(input, F_NOCACHE, 1)
        meter = Meter(pass: .read, total: size)
        var read: Int64 = 0
        while read < size {
            if isCancelled() { throw CancellationError() }
            let result = buffer.withUnsafeMutableBytes { Darwin.read(input, $0.baseAddress, chunk) }
            guard result > 0 else {
                if result == 0 { break }
                throw Failure(message: String(localized: "读到一半出错了：\(String(cString: strerror(errno)))"))
            }
            read += Int64(result)
            progress(meter.add(Int64(result)))
        }
        return Speeds(write: writeSpeed, read: meter.average)
    }

    /// 计时：平均速度从开始算，当前速度看最近半秒
    struct Meter {
        let pass: Pass
        let total: Int64
        private let start = ProcessInfo.processInfo.systemUptime
        private var done: Int64 = 0
        private var window: [(time: TimeInterval, done: Int64)] = []

        init(pass: Pass, total: Int64) {
            self.pass = pass
            self.total = total
            window = [(start, 0)]
        }

        mutating func add(_ bytes: Int64, at time: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Progress {
            done += bytes
            window.append((time, done))
            while window.count > 2, time - window[1].time > 0.5 {
                window.removeFirst()
            }
            let first = window[0]
            let speed = time > first.time ? Double(done - first.done) / (time - first.time) : 0
            return Progress(pass: pass, done: done, total: total, speed: speed)
        }

        var average: Double {
            let elapsed = ProcessInfo.processInfo.systemUptime - start
            return elapsed > 0 ? Double(done) / elapsed : 0
        }
    }

    // MARK: - 写法

    /// 「2,834 MB/s」「86.4 MB/s」：和硬盘厂商一样按 1 MB = 1,000,000 字节
    static func speedText(_ bytesPerSecond: Double) -> String {
        let megabytes = bytesPerSecond / 1_000_000
        return "\(numberText(megabytes)) MB/s"
    }

    static func numberText(_ megabytes: Double) -> String {
        megabytes >= 100 ? megabytes.formatted(.number.precision(.fractionLength(0)))
            : megabytes.formatted(.number.precision(.fractionLength(1)))
    }

    /// 「APFS · 外接 · 可用 312 GB，共 994 GB」
    static func describe(_ volume: Volume) -> String {
        var parts: [String] = []
        if let format = volume.format {
            parts.append(format)
        }
        parts.append(!volume.isLocal ? String(localized: "网络磁盘") : volume.isInternal ? String(localized: "内置") : String(localized: "外接"))
        let available = ByteCountFormatter.string(fromByteCount: volume.available, countStyle: .file)
        let total = ByteCountFormatter.string(fromByteCount: volume.total, countStyle: .file)
        parts.append(String(localized: "可用 \(available)，共 \(total)"))
        return parts.joined(separator: " · ")
    }
}
