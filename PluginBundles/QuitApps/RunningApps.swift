import Darwin
import Foundation
@testable import Pop

/// 正在运行的 App：各占多少内存、用了多少 CPU（App 和它开出来的子进程合起来算），按占得多的排在前面。
enum RunningApps {
    struct Entry: Identifiable, Equatable {
        let pid: pid_t
        let name: String
        let bundleID: String?
        /// 一共占的内存（字节）；读不到时为 nil
        var memory: UInt64?
        /// CPU 占用（%，用满一个核是 100）；还没算出来时为 nil
        var cpu: Double? = nil

        var id: pid_t { pid }
    }

    /// 按什么排
    enum Sort: String, CaseIterable, Identifiable {
        case memory
        case cpu

        var id: String { rawValue }

        var title: String {
            switch self {
            case .memory: return String(localized: "按内存")
            case .cpu: return String(localized: "按 CPU")
            }
        }
    }

    /// 不列出来的：访达（退出了会马上重新打开）
    static let hidden: Set<String> = ["com.apple.finder"]

    /// 子进程最多往下找这么多个
    static let maxProcesses = 512

    /// 按占用内存（或者 CPU）从多到少排，读不到的排在后面；一样多（或者都读不到）时比另一项，再按名字排
    static func sorted(_ entries: [Entry], by sort: Sort = .memory) -> [Entry] {
        func value(_ entry: Entry, _ key: Sort) -> Double? {
            key == .memory ? entry.memory.map { Double($0) } : entry.cpu
        }
        let keys: [Sort] = sort == .memory ? [.memory, .cpu] : [.cpu, .memory]
        return entries.sorted { a, b in
            for key in keys {
                switch (value(a, key), value(b, key)) {
                case let (x?, y?) where x != y: return x > y
                case (.some, nil): return true
                case (nil, .some): return false
                default: continue
                }
            }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
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

    /// 「12%」「3.4%」：不到 10% 带一位小数，几乎没用的写「0%」
    static func formatCPU(_ percent: Double) -> String {
        if percent < 0.05 { return "0%" }
        return percent < 10 ? String(format: "%.1f%%", percent) : String(format: "%.0f%%", percent)
    }

    /// 进程和它一层层开出来的子进程占的内存合计，和「活动监视器」的「内存」一栏一样按 phys_footprint 算
    static func memory(of pid: pid_t) -> UInt64? {
        guard let own = usage(pid) else { return nil }
        return tree(of: pid).dropFirst().reduce(own.ri_phys_footprint) { $0 + (usage($1)?.ri_phys_footprint ?? 0) }
    }

    /// 进程和子进程一共用了多少 CPU 时间（纳秒）；读不到时为 nil
    static func cpuTime(of pid: pid_t) -> UInt64? {
        guard let own = usage(pid) else { return nil }
        let ticks = tree(of: pid).dropFirst().reduce(own.ri_user_time + own.ri_system_time) { total, child in
            guard let info = usage(child) else { return total }
            return total + info.ri_user_time + info.ri_system_time
        }
        return nanoseconds(ticks)
    }

    /// 只算进程自己（不算子进程）用了多少 CPU 时间（纳秒）
    static func ownCPUTime(of pid: pid_t) -> UInt64? {
        usage(pid).map { nanoseconds($0.ri_user_time + $0.ri_system_time) }
    }

    /// 两次读数之间的 CPU 占用（%）：这段时间里用了多少 CPU 时间，除以过了多久。子进程退出了、少了的算 0
    static func cpuPercent(from old: UInt64, to new: UInt64, seconds: Double) -> Double {
        guard seconds > 0, new > old else { return 0 }
        return Double(new - old) / 1_000_000_000 / seconds * 100
    }

    /// rusage 里的时间是 mach 时间单位：Apple 芯片上按 timebase 换成纳秒（125/3），Intel 上本来就是纳秒
    static let timebase: (numer: UInt64, denom: UInt64) = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return (UInt64(info.numer), UInt64(max(info.denom, 1)))
    }()

    static func nanoseconds(_ ticks: UInt64) -> UInt64 {
        // 先除后乘，不会溢出
        ticks / timebase.denom * timebase.numer + ticks % timebase.denom * timebase.numer / timebase.denom
    }

    /// 进程和它一层层开出来的子进程（最多 maxProcesses 个）
    static func tree(of pid: pid_t) -> [pid_t] {
        var result = [pid]
        var visited: Set<pid_t> = [pid]
        var queue = children(of: pid)
        while let next = queue.popLast(), visited.count < maxProcesses {
            guard visited.insert(next).inserted else { continue }
            result.append(next)
            queue.append(contentsOf: children(of: next))
        }
        return result
    }

    private static func usage(_ pid: pid_t) -> rusage_info_v2? {
        var info = rusage_info_v2()
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V2, $0) }
        }
        return result == 0 ? info : nil
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
