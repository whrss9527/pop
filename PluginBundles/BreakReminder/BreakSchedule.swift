import CoreGraphics
import Foundation
import IOKit.pwr_mgt
@testable import Pop

/// 休息提醒的计时：连续用了多久、什么时候该提醒、什么时候算休息过。只看「多久没碰键盘鼠标」，纯逻辑，方便测试
struct BreakSchedule: Equatable {
    /// 连续用多久提醒一次
    var interval: TimeInterval
    /// 一次休息多久
    var breakLength: TimeInterval
    /// 这一段从什么时候开始连续用的；nil 是刚休息过（或者刚打开），下次碰键盘鼠标时开始算
    private(set) var workStart: Date?
    /// 「过一会儿再提醒」到什么时候
    private(set) var snoozedUntil: Date?
    /// 正在休息：休息到什么时候
    private(set) var breakEndsAt: Date?
    /// 提醒弹出来了，还没处理
    private(set) var isDue = false
    /// 上一次看到有 App 不让屏幕变暗（在放视频、开会）的时刻
    private(set) var lastQuiet: Date?

    init(interval: TimeInterval, breakLength: TimeInterval) {
        self.interval = interval
        self.breakLength = breakLength
    }

    /// 离开电脑这么久就算休息过了：休息时长，但至少 3 分钟（看文章时一两分钟不碰键盘鼠标很平常）
    var restThreshold: TimeInterval {
        max(breakLength, 180)
    }

    enum Change: Equatable {
        case none
        /// 该提醒了
        case remind
        /// 提醒着的时候离开够久，算休息过了（提醒收起来）
        case rested
        /// 休息的时间到了
        case breakFinished
    }

    var isOnBreak: Bool {
        breakEndsAt != nil
    }

    /// 每隔一会儿看一次。quiet 是有别的 App 不让屏幕变暗（在放视频、开会、演示）：这时不提醒，也不把没碰键盘鼠标算成休息
    mutating func update(now: Date, idle rawIdle: TimeInterval, quiet: Bool) -> Change {
        if let breakEndsAt {
            guard now >= breakEndsAt else { return .none }
            finishBreak()
            return .breakFinished
        }
        if quiet {
            lastQuiet = now
        }
        let idle = away(now: now, idle: rawIdle)
        if !quiet, idle >= restThreshold {
            let wasDue = isDue
            rest()
            return wasDue ? .rested : .none
        }
        if workStart == nil {
            // 刚回来：从碰键盘鼠标的那一刻算起
            workStart = quiet ? now : now.addingTimeInterval(-idle)
        }
        guard !quiet, !isDue, worked(now: now) >= interval else { return .none }
        if let snoozedUntil, now < snoozedUntil {
            return .none
        }
        isDue = true
        return .remind
    }

    /// 离开够久了（走开了，或者合上盖子睡了一觉）：算休息过了，下次碰键盘鼠标时重新算。正在休息时不管
    mutating func rest() {
        guard breakEndsAt == nil else { return }
        workStart = nil
        snoozedUntil = nil
        isDue = false
    }

    /// 离开了多久：多久没碰键盘鼠标，但刚看完视频、开完会时那段时间不算休息，从结束的那一刻算起
    func away(now: Date, idle: TimeInterval) -> TimeInterval {
        lastQuiet.map { min(idle, max(0, now.timeIntervalSince($0))) } ?? idle
    }

    /// 「跳过」：从现在起重新算一段
    mutating func skip(now: Date) {
        workStart = now
        snoozedUntil = nil
        isDue = false
    }

    /// 「过一会儿再提醒」
    mutating func snooze(now: Date, for duration: TimeInterval) {
        snoozedUntil = now.addingTimeInterval(duration)
        isDue = false
    }

    mutating func startBreak(now: Date) {
        breakEndsAt = now.addingTimeInterval(breakLength)
        snoozedUntil = nil
        isDue = false
    }

    /// 休息完了（时间到了，或者提前结束）：下次碰键盘鼠标时重新算
    mutating func finishBreak() {
        breakEndsAt = nil
        workStart = nil
        snoozedUntil = nil
        isDue = false
    }

    /// 关掉、重新打开时从头算
    mutating func reset() {
        finishBreak()
    }

    /// 这一段已经连续用了多久
    func worked(now: Date) -> TimeInterval {
        workStart.map { max(0, now.timeIntervalSince($0)) } ?? 0
    }

    /// 还有多久提醒；正在提醒、正在休息时为 nil
    func untilReminder(now: Date) -> TimeInterval? {
        guard !isDue, breakEndsAt == nil else { return nil }
        let due = max(0, interval - worked(now: now))
        if let snoozedUntil {
            return max(due, snoozedUntil.timeIntervalSince(now))
        }
        return due
    }

    /// 休息还剩多久
    func breakRemaining(now: Date) -> TimeInterval? {
        breakEndsAt.map { max(0, $0.timeIntervalSince(now)) }
    }
}

/// 系统的状态：多久没碰键盘鼠标、有没有别的 App 不让屏幕变暗
enum BreakSignals {
    /// 上一次按键、点鼠标、动触控板到现在几秒
    static func idleSeconds() -> TimeInterval {
        guard let anyInput = CGEventType(rawValue: ~0) else { return 0 }
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
    }

    /// 有别的 App 不让屏幕变暗：一般是在放视频、开视频会议或者演示
    static func othersKeepDisplayAwake() -> Bool {
        var result: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&result) == kIOReturnSuccess,
              let byProcess = result?.takeRetainedValue() as? [NSNumber: [[String: Any]]] else { return false }
        let assertions = Dictionary(byProcess.map { ($0.key.int32Value, $0.value) }, uniquingKeysWith: { first, _ in first })
        return keepsDisplayAwake(assertions, ownPID: ProcessInfo.processInfo.processIdentifier)
    }

    /// 按进程列出的电源断言里，有没有别的进程不让屏幕变暗（Pop 自己的「保持唤醒」不算）
    static func keepsDisplayAwake(_ assertions: [Int32: [[String: Any]]], ownPID: Int32) -> Bool {
        assertions.contains { pid, list in
            pid != ownPID && list.contains { entry in
                let type = entry["AssertType"] as? String
                return type == "PreventUserIdleDisplaySleep" || type == "NoDisplaySleepAssertion"
            }
        }
    }
}
