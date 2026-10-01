import Darwin
import Foundation
@testable import Pop

/// 正在运行的 App：各占多少内存（App 和它开出来的子进程合起来算），按占得多的排在前面。
enum RunningApps {
    struct Entry: Identifiable, Equatable {
        let pid: pid_t
        let name: String
        let bundleID: String?
        /// 一共占的内存（字节）；读不到时为 nil
        var memory: UInt64?

        var id: pid_t { pid }
    }

    /// 不列出来的：访达（退出了会马上重新打开）
    static let hidden: Set<String> = ["com.apple.finder"]

    /// 子进程最多往下找这么多个
    static let maxProcesses = 512

    /// 按占用内存从多到少排；读不到内存的排在后面，按名字排
    static func sorted(_ entries: [Entry]) -> [Entry] {
        entries.sorted { a, b in
            switch (a.memory, b.memory) {
            case let (x?, y?) where x != y: return x > y
            case (.some, nil): return true
            case (nil, .some): return false
            default: return a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
        }
    }

    /// 「退出其他 App」要退出的：刚才在用的那个 App 留着
    static func others(_ entries: [Entry], keeping front: pid_t?) -> [Entry] {
        entries.filter { $0.pid != front }
    }

    static func total(_ entries: [Entry]) -> UInt64 {
        entries.reduce(0) { $0 + ($1.memory ?? 0) }
    }

    /// 「1.2 GB」
    static func format(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .memory)
    }

    /// 进程和它一层层开出来的子进程占的内存合计，和「活动监视器」的「内存」一栏一样按 phys_footprint 算
    static func memory(of pid: pid_t) -> UInt64? {
        guard let own = footprint(pid) else { return nil }
        var total = own
        var visited: Set<pid_t> = [pid]
        var queue = children(of: pid)
        while let next = queue.popLast(), visited.count < maxProcesses {
            guard visited.insert(next).inserted else { continue }
            total += footprint(next) ?? 0
            queue.append(contentsOf: children(of: next))
        }
        return total
    }

    private static func footprint(_ pid: pid_t) -> UInt64? {
        var info = rusage_info_v2()
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V2, $0) }
        }
        return result == 0 ? info.ri_phys_footprint : nil
    }

    private static func children(of pid: pid_t) -> [pid_t] {
        var pids = [pid_t](repeating: 0, count: 256)
        let result = pids.withUnsafeMutableBytes { buffer in
            proc_listchildpids(pid, buffer.baseAddress, Int32(buffer.count))
        }
        // 返回值在不同系统上有的是个数、有的是字节数，进程号不会是 0，直接取不是 0 的
        guard result > 0 else { return [] }
        return pids.filter { $0 > 0 }
    }
}
