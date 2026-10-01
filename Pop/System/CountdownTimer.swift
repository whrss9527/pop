import AppKit

/// 倒计时：到点时响一声、发一条通知、在屏幕上提示。退出 Pop 后不再计时。
/// 也可以是番茄钟：专注和休息轮流来，一直到取消。
@MainActor
final class CountdownTimer: ObservableObject {
    static let shared = CountdownTimer()

    /// 番茄钟的一段：专注 25 分钟，然后休息 5 分钟（每四个番茄休息 15 分钟），再开始下一个
    struct Pomodoro: Equatable {
        enum Phase: Equatable {
            case focus
            case rest
        }

        static let focusMinutes = 25
        static let restMinutes = 5
        static let longRestMinutes = 15

        var phase: Phase
        /// 第几个番茄（从 1 开始）
        var round: Int

        static let first = Pomodoro(phase: .focus, round: 1)

        var duration: TimeInterval {
            switch phase {
            case .focus: return TimeInterval(Self.focusMinutes * 60)
            case .rest: return TimeInterval((round % 4 == 0 ? Self.longRestMinutes : Self.restMinutes) * 60)
            }
        }

        /// 这一段结束以后的下一段
        var next: Pomodoro {
            switch phase {
            case .focus: return Pomodoro(phase: .rest, round: round)
            case .rest: return Pomodoro(phase: .focus, round: round + 1)
            }
        }

        /// 这一段结束时的提示
        var finishedMessage: String {
            switch phase {
            case .focus:
                return String(localized: "第 \(round) 个番茄完成，休息 \(CountdownTimer.title(seconds: next.duration))")
            case .rest:
                return String(localized: "休息结束，开始第 \(round + 1) 个番茄")
            }
        }
    }

    /// 卡片上可以直接选的时长（分钟）
    static let presets = [1, 3, 5, 10, 15, 25, 45, 60]

    /// 什么时候到点；没在计时时为 nil
    @Published private(set) var endsAt: Date?
    /// 这次计时有多长（秒）
    private(set) var duration: TimeInterval = 0
    /// 番茄钟进行到哪一段；普通计时时为 nil
    @Published private(set) var pomodoro: Pomodoro?
    private var timer: Timer?
    /// 到点时在屏幕上提示（AppController 接上浮窗的提示）
    var onFinish: (String) -> Void = { _ in }

    var isRunning: Bool { endsAt != nil }

    func start(seconds: TimeInterval) {
        start(seconds: seconds, pomodoro: nil)
    }

    /// 番茄钟从第一个番茄开始
    func startPomodoro() {
        start(seconds: Pomodoro.first.duration, pomodoro: .first)
    }

    private func start(seconds: TimeInterval, pomodoro: Pomodoro?) {
        cancel()
        duration = seconds
        self.pomodoro = pomodoro
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
        pomodoro = nil
    }

    private func finish() {
        // 番茄钟：提示一下，接着开始下一段
        if let pomodoro {
            let message = pomodoro.finishedMessage
            NSSound(named: "Glass")?.play()
            Notifier.shared.showReminder(title: String(localized: "番茄钟"), body: message)
            onFinish(message)
            let next = pomodoro.next
            start(seconds: next.duration, pomodoro: next)
            return
        }
        let message = String(localized: "\(Self.title(seconds: duration))的计时到了")
        cancel()
        NSSound(named: "Glass")?.play()
        Notifier.shared.showReminder(title: String(localized: "时间到"), body: message)
        onFinish(String(localized: "时间到：\(message)"))
    }

    /// 「计时还剩 12:34（到 15:30）」；没在计时时为 nil
    func statusText(now: Date = Date()) -> String? {
        guard let endsAt else { return nil }
        let remaining = max(Int(endsAt.timeIntervalSince(now).rounded(.up)), 0)
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let end = formatter.string(from: endsAt)
        switch pomodoro?.phase {
        case .focus?:
            return String(localized: "第 \(pomodoro?.round ?? 1) 个番茄，专注还剩 \(Self.clock(remaining))（到 \(end)）")
        case .rest?:
            return String(localized: "番茄钟休息还剩 \(Self.clock(remaining))（到 \(end)）")
        case nil:
            return String(localized: "计时还剩 \(Self.clock(remaining))（到 \(end)）")
        }
    }

    /// 90 → 「1:30」，3700 → 「1:01:40」
    nonisolated static func clock(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = seconds % 3600 / 60
        let rest = seconds % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, rest) : String(format: "%d:%02d", minutes, rest)
    }

    /// 1500 → 「25 分钟」，90 → 「1 分 30 秒」，5400 → 「1 小时 30 分钟」
    nonisolated static func title(seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = total % 3600 / 60
        let rest = total % 60
        switch (hours, minutes, rest) {
        case (0, 0, _): return String(localized: "\(rest) 秒")
        case (0, _, 0): return String(localized: "\(minutes) 分钟")
        case (0, _, _): return String(localized: "\(minutes) 分 \(rest) 秒")
        case (_, 0, 0): return String(localized: "\(hours) 小时")
        case (_, _, 0): return String(localized: "\(hours) 小时 \(minutes) 分钟")
        default: return String(localized: "\(hours) 小时 \(minutes) 分 \(rest) 秒")
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
