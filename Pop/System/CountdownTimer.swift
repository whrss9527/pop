import AppKit

/// 倒计时：到点时响一声、发一条通知、在屏幕上提示。退出 Pop 后不再计时。
@MainActor
final class CountdownTimer: ObservableObject {
    static let shared = CountdownTimer()

    /// 卡片上可以直接选的时长（分钟）
    static let presets = [1, 3, 5, 10, 15, 25, 45, 60]

    /// 什么时候到点；没在计时时为 nil
    @Published private(set) var endsAt: Date?
    /// 这次计时有多长（秒）
    private(set) var duration: TimeInterval = 0
    private var timer: Timer?
    /// 到点时在屏幕上提示（AppController 接上浮窗的提示）
    var onFinish: (String) -> Void = { _ in }

    var isRunning: Bool { endsAt != nil }

    func start(seconds: TimeInterval) {
        cancel()
        duration = seconds
        endsAt = Date().addingTimeInterval(seconds)
        timer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.finish()
            }
        }
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
        endsAt = nil
    }

    private func finish() {
        let message = "\(Self.title(seconds: duration))的计时到了"
        cancel()
        NSSound(named: "Glass")?.play()
        Notifier.shared.showReminder(title: "时间到", body: message)
        onFinish("时间到：\(message)")
    }

    /// 「计时还剩 12:34（到 15:30）」；没在计时时为 nil
    func statusText(now: Date = Date()) -> String? {
        guard let endsAt else { return nil }
        let remaining = max(Int(endsAt.timeIntervalSince(now).rounded(.up)), 0)
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return "计时还剩 \(Self.clock(remaining))（到 \(formatter.string(from: endsAt))）"
    }

    /// 90 → 「1:30」，3700 → 「1:01:40」
    static func clock(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = seconds % 3600 / 60
        let rest = seconds % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, rest) : String(format: "%d:%02d", minutes, rest)
    }

    /// 1500 → 「25 分钟」，90 → 「1 分 30 秒」，5400 → 「1 小时 30 分钟」
    static func title(seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = total % 3600 / 60
        let rest = total % 60
        switch (hours, minutes, rest) {
        case (0, 0, _): return "\(rest) 秒"
        case (0, _, 0): return "\(minutes) 分钟"
        case (0, _, _): return "\(minutes) 分 \(rest) 秒"
        case (_, 0, 0): return "\(hours) 小时"
        case (_, _, 0): return "\(hours) 小时 \(minutes) 分钟"
        default: return "\(hours) 小时 \(minutes) 分 \(rest) 秒"
        }
    }
}

/// 从「25 分钟」「1h30m」「90s」「1:30」这样的文字里读出时长（秒）
enum DurationParser {
    private static let part = try! NSRegularExpression(
        pattern: #"(\d+(?:\.\d+)?)\s*(小时|钟头|时|hours?|hrs?|h|分钟|分|minutes?|mins?|m|秒钟|秒|seconds?|secs?|s)"#)

    static func parse(_ text: String) -> TimeInterval? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty, trimmed.count <= 30 else { return nil }
        // 1:30 是 1 分 30 秒，1:30:00 是 1 小时 30 分
        let pieces = trimmed.split(separator: ":", omittingEmptySubsequences: false)
        if pieces.count == 2 || pieces.count == 3 {
            let numbers = pieces.compactMap { Int($0) }
            guard numbers.count == pieces.count, pieces.dropFirst().allSatisfy({ $0.count == 2 }),
                  numbers.dropFirst().allSatisfy({ $0 < 60 }) else { return nil }
            let seconds = numbers.reduce(0) { $0 * 60 + $1 }
            return seconds > 0 ? TimeInterval(seconds) : nil
        }
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        // 整段都得是时长，去掉时长以后只能剩下空白
        let rest = part.stringByReplacingMatches(in: trimmed, range: range, withTemplate: "")
        guard rest.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        var total: TimeInterval = 0
        for match in part.matches(in: trimmed, range: range) {
            guard let valueRange = Range(match.range(at: 1), in: trimmed), let unitRange = Range(match.range(at: 2), in: trimmed),
                  let value = Double(trimmed[valueRange]) else { return nil }
            switch trimmed[unitRange] {
            case "小时", "钟头", "时", "hour", "hours", "hr", "hrs", "h": total += value * 3600
            case "秒钟", "秒", "second", "seconds", "sec", "secs", "s": total += value
            default: total += value * 60
            }
        }
        return total > 0 ? total : nil
    }
}
