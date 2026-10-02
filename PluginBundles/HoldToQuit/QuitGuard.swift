import Foundation

/// 长按（或者连按两下）⌘Q 才退出：⌘Q 按下、自动重复、松开时该怎么办。纯逻辑，方便测试
struct QuitGuard: Equatable {
    enum Mode: String, CaseIterable {
        /// 按住一会儿才退出
        case hold
        /// 一小会儿里连按两下才退出
        case twice
    }

    enum Action: Equatable {
        /// 原样交给 App
        case pass
        /// 吞掉，App 收不到
        case swallow
        /// 吞掉，并且把 ⌘Q 交给这个 App，让它退出
        case quit(pid_t)
    }

    var mode: Mode
    /// 按住多久才退出；连按两下时，两下之间最多隔多久
    var duration: TimeInterval

    /// 正在等的 App：按住时是按下时在前台的那个，连按时是按第一下时在前台的那个
    private(set) var target: pid_t?
    /// 从什么时候开始等的
    private(set) var startedAt: Date?
    /// 这一下已经退出过了：还按着不放的话，自动重复的按键不要再退一次
    private(set) var hasQuit = false
    /// 吞掉了 Q 的按下：这个键松开之前，自动重复的、松开的都吞掉，App 里不会冒出一串 q
    private(set) var holdsKey = false

    init(mode: Mode, duration: TimeInterval) {
        self.mode = mode
        self.duration = duration
    }

    /// 在等着退出（还没退）
    var isWaiting: Bool {
        target != nil && !hasQuit
    }

    /// 按下了 ⌘Q（不是自动重复的）
    mutating func pressQuit(app pid: pid_t, now: Date) -> Action {
        holdsKey = true
        if mode == .twice, target == pid, !hasQuit, let startedAt, now.timeIntervalSince(startedAt) <= duration {
            hasQuit = true
            return .quit(pid)
        }
        target = pid
        startedAt = now
        hasQuit = false
        return .swallow
    }

    /// 吞着的那个键自动重复
    func repeatKey() -> Action {
        holdsKey ? .swallow : .pass
    }

    /// 吞着的那个键松开了。按住的方式没按够就不退出了；连按的方式接着等第二下
    mutating func releaseKey() -> Action {
        guard holdsKey else { return .pass }
        holdsKey = false
        if mode == .hold || hasQuit {
            clear()
        }
        return .swallow
    }

    /// ⌘ 松开了：按住的方式没按够就不退出了（Q 松开之前还是吞着）
    mutating func releaseCommand() {
        guard mode == .hold, !hasQuit else { return }
        clear()
    }

    /// 隔一小会儿看一次：按住够久了返回要退出的 App；连按时等第二下等太久就算了
    mutating func check(now: Date) -> pid_t? {
        guard let target, let startedAt, !hasQuit else { return nil }
        let elapsed = now.timeIntervalSince(startedAt)
        switch mode {
        case .hold:
            guard elapsed >= duration else { return nil }
            hasQuit = true
            return target
        case .twice:
            if elapsed > duration {
                clear()
            }
            return nil
        }
    }

    /// 不等了（要退出的 App 已经不在前台了）
    mutating func cancel() {
        clear()
    }

    /// 进度（0…1）：按住时按了多久，连按时第二下还剩多少时间；没在等时为 nil
    func progress(now: Date) -> Double? {
        guard isWaiting, let startedAt else { return nil }
        let fraction = min(1, max(0, now.timeIntervalSince(startedAt) / max(duration, 0.01)))
        return mode == .hold ? fraction : 1 - fraction
    }

    private mutating func clear() {
        target = nil
        startedAt = nil
        hasQuit = false
    }
}
