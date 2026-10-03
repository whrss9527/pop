import Foundation

/// 主线程卡顿检测，给 CI 用：演示模式（POP_DEMO=1，截图）和设了 POP_HANG_LOG 时（启动测试）才开。
///
/// 后台每 50 毫秒往主线程放一个空任务，看主线程多久才做到：超过 0.25 秒就算卡了一次。卡完以后写一行
/// 「hang 开始的时间戳 卡了几秒」：演示模式写进 POP_DEMO_LOG（和演示步骤在一起，截图脚本按步骤列出来），
/// 否则写进 POP_HANG_LOG。卡了半秒还没缓过来时先写一行「stall 开始的时间戳」，截图脚本看到就去采样主线程在忙什么
/// （等卡完再采就晚了：卡一两秒的，采样开始时多半已经缓过来了）。
/// 整个 Pop 被停住的时间不算主线程卡的（采样的工具接上时会把 Pop 停一下，装着一百多个插件包时要停一两秒）：
/// 检测的线程自己也隔了好久才轮到时，多出来的那段从等的时间里扣掉，hang 行后面写上「paused 扣掉的秒数」。
/// 平时不开，菜单栏 App 不该一秒醒来二十次。
final class HangWatchdog: @unchecked Sendable {
    /// 主线程超过这么久没空就记下来
    static let threshold: TimeInterval = 0.25
    /// 卡了这么久还没缓过来就先说一声（stall 行）
    static let stallNotice: TimeInterval = 0.5
    private static let interval: DispatchTimeInterval = .milliseconds(50)
    private static let intervalSeconds: TimeInterval = 0.05
    /// 检测的线程比该到的时候晚这么多，才算 Pop 被停住了（平常排队晚个几毫秒、几十毫秒不算）
    static let pauseSlack: TimeInterval = 0.1

    private let path: String
    private let queue = DispatchQueue(label: "io.github.whrss9527.pop.hang-watchdog", qos: .userInteractive)
    /// 只在 queue 上读写
    private var timer: DispatchSourceTimer?
    /// 检测期间不让系统给 Pop 打盹（App Nap 会推迟计时、降低优先级，量出来的就不是 Pop 自己卡的了）。只在 queue 上读写
    private var activity: NSObjectProtocol?
    /// 发出去还没做到的那个空任务：什么时候发的（单调时钟、墙上时间）。只在 queue 上读写
    private var pending: (sent: UInt64, wall: TimeInterval)?
    /// 这一次卡住已经写过 stall 行了。只在 queue 上读写
    private var noticed = false
    /// 检测的线程上次做事（发空任务、看结果）的时候（单调时钟）。只在 queue 上读写
    private var lastCheck: UInt64 = 0
    /// 等着这个空任务的时候，整个 Pop 被停住了多久（不算主线程卡的）。只在 queue 上读写
    private var paused: TimeInterval = 0

    init(path: String) {
        self.path = path
    }

    @MainActor private static var shared: HangWatchdog?

    /// 写到哪：演示模式写进演示日志，否则看 POP_HANG_LOG；都没有时不检测
    static func requestedPath(environment: [String: String]) -> String? {
        let path = environment["POP_DEMO"] == "1" ? environment["POP_DEMO_LOG"] : environment["POP_HANG_LOG"]
        guard let path, !path.isEmpty else { return nil }
        return path
    }

    /// App 一启动就调用：环境变量要求时开始检测
    @MainActor
    static func startIfRequested(environment: [String: String] = ProcessInfo.processInfo.environment) {
        guard shared == nil, let path = requestedPath(environment: environment) else { return }
        let watchdog = HangWatchdog(path: path)
        shared = watchdog
        watchdog.start()
    }

    func start() {
        queue.async { [self] in
            guard timer == nil else { return }
            let source = DispatchSource.makeTimerSource(queue: queue)
            source.schedule(deadline: .now() + Self.interval, repeating: Self.interval, leeway: .milliseconds(5))
            source.setEventHandler { [weak self] in
                self?.tick()
            }
            timer = source
            activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical],
                                                             reason: "Main thread hang detection")
            source.resume()
        }
    }

    func stop() {
        queue.async { [self] in
            timer?.cancel()
            timer = nil
            if let activity {
                ProcessInfo.processInfo.endActivity(activity)
            }
            activity = nil
        }
    }

    /// 上一个空任务已经做到了就再发一个；还没做到就接着等（卡多久只记一次），卡了半秒时先写一行 stall
    private func tick() {
        let now = DispatchTime.now().uptimeNanoseconds
        notePause(until: now)
        if let pending {
            let waited = TimeInterval(now &- pending.sent) / 1_000_000_000 - paused
            if waited >= Self.stallNotice, !noticed {
                noticed = true
                LineLog.append(String(format: "stall %.3f", pending.wall), to: path)
            }
            return
        }
        pending = (now, Date().timeIntervalSince1970)
        paused = 0
        DispatchQueue.main.async { [weak self] in
            let arrived = DispatchTime.now().uptimeNanoseconds
            self?.queue.async { [weak self] in
                self?.answered(arrived: arrived)
            }
        }
    }

    private func answered(arrived: UInt64) {
        // 主线程做到时如果检测的线程已经好久没轮到，这段也是 Pop 被停住了（只算到主线程做到的时候）
        notePause(until: arrived)
        guard let pending else { return }
        self.pending = nil
        noticed = false
        let waited = TimeInterval(arrived &- pending.sent) / 1_000_000_000 - paused
        guard waited >= Self.threshold else { return }
        let line = String(format: "hang %.3f %.3f", pending.wall, waited)
        LineLog.append(paused > 0 ? line + String(format: " paused %.3f", paused) : line, to: path)
    }

    /// 检测的线程上次做事以后隔了多久：比该隔的多出 pauseSlack 以上，就是整个 Pop 被停住了，等着空任务的话记下来
    private func notePause(until now: UInt64) {
        guard now > lastCheck else { return }
        defer { lastCheck = now }
        guard lastCheck > 0, pending != nil else { return }
        paused += Self.pausedTime(gap: TimeInterval(now &- lastCheck) / 1_000_000_000)
    }

    /// 测试用：过 delay 秒以后让检测的线程停 seconds 秒（像整个 Pop 被停住时那样）
    func holdUpForTesting(_ seconds: TimeInterval, after delay: TimeInterval) {
        queue.asyncAfter(deadline: .now() + delay) {
            Thread.sleep(forTimeInterval: seconds)
        }
    }

    /// 两次做事隔了 gap 秒，其中有多少算 Pop 被停住了
    static func pausedTime(gap: TimeInterval) -> TimeInterval {
        gap > intervalSeconds + pauseSlack ? gap - intervalSeconds : 0
    }
}

/// 往日志文件末尾追加一行。用 O_APPEND 打开：主线程和检测卡顿的线程同时写也不会互相盖掉
enum LineLog {
    static func append(_ line: String, to path: String) {
        let fd = open(path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
        guard fd >= 0 else { return }
        defer { close(fd) }
        let data = Array((line + "\n").utf8)
        _ = data.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
    }
}
