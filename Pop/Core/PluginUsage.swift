import Foundation

/// 功能最近一次用的时间（只存在这台 Mac 上，不同步）。「全部功能」列表把最近用过的排在前面。
final class PluginUsage {
    static let shared = PluginUsage()

    /// 最多记这么多个功能
    static let capacity = 40
    /// 多久以内用过的算「最近」
    static let recentWindow: TimeInterval = 30 * 24 * 3600

    private let defaults: UserDefaults
    private let key = "pop.pluginUsage"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// 功能 ID → 最近一次用的时间（1970 年以来的秒数）
    var lastUsed: [String: Double] {
        defaults.dictionary(forKey: key) as? [String: Double] ?? [:]
    }

    func record(_ pluginID: String, at date: Date = Date()) {
        var usage = lastUsed
        usage[pluginID] = date.timeIntervalSince1970
        if usage.count > Self.capacity {
            let kept = usage.sorted { $0.value > $1.value }.prefix(Self.capacity)
            usage = Dictionary(uniqueKeysWithValues: kept.map { ($0.key, $0.value) })
        }
        defaults.set(usage, forKey: key)
    }

    /// 最近用过的功能，从近到远，最多 limit 个
    func recent(limit: Int = 5, now: Date = Date()) -> [String] {
        lastUsed
            .filter { now.timeIntervalSince1970 - $0.value < Self.recentWindow }
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(limit)
            .map(\.key)
    }

    /// 最近用过的排到最前面（按从近到远），其余保持原来的顺序；返回排好的列表和排在前面的个数
    static func ordered(_ plugins: [PluginInfo], recent: [String]) -> (plugins: [PluginInfo], recentCount: Int) {
        let front = recent.compactMap { id in plugins.first { $0.id == id } }
        let rest = plugins.filter { !recent.contains($0.id) }
        return (front + rest, front.count)
    }
}
