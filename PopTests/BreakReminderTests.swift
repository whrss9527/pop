import XCTest
@testable import Pop

@MainActor
final class BreakReminderTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_790_820_000)

    private func freshDefaults() -> UserDefaults {
        let suite = "PopBreakReminderTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    // MARK: - 计时

    func testScheduleRemindsAfterTheInterval() {
        var schedule = BreakSchedule(interval: 45 * 60, breakLength: 300)
        XCTAssertEqual(schedule.update(now: start, idle: 0, quiet: false), .none)
        XCTAssertEqual(schedule.workStart, start)
        XCTAssertEqual(schedule.untilReminder(now: start.addingTimeInterval(600)), 35 * 60)
        XCTAssertEqual(schedule.update(now: start.addingTimeInterval(44 * 60), idle: 5, quiet: false), .none)
        XCTAssertEqual(schedule.update(now: start.addingTimeInterval(45 * 60), idle: 5, quiet: false), .remind)
        XCTAssertTrue(schedule.isDue)
        XCTAssertNil(schedule.untilReminder(now: start.addingTimeInterval(45 * 60)))
        // 提醒过了不再提醒，直到处理
        XCTAssertEqual(schedule.update(now: start.addingTimeInterval(46 * 60), idle: 5, quiet: false), .none)

        // 过 5 分钟再提醒
        schedule.snooze(now: start.addingTimeInterval(46 * 60), for: 300)
        XCTAssertFalse(schedule.isDue)
        XCTAssertEqual(schedule.untilReminder(now: start.addingTimeInterval(46 * 60)), 300)
        XCTAssertEqual(schedule.update(now: start.addingTimeInterval(50 * 60), idle: 5, quiet: false), .none)
        XCTAssertEqual(schedule.update(now: start.addingTimeInterval(51 * 60), idle: 5, quiet: false), .remind)

        // 跳过：从现在起重新算
        let skipped = start.addingTimeInterval(52 * 60)
        schedule.skip(now: skipped)
        XCTAssertEqual(schedule.untilReminder(now: skipped), 45 * 60)
        XCTAssertEqual(schedule.update(now: skipped.addingTimeInterval(44 * 60), idle: 5, quiet: false), .none)
        XCTAssertEqual(schedule.update(now: skipped.addingTimeInterval(45 * 60), idle: 5, quiet: false), .remind)
    }

    func testStepAwayCountsAsRest() {
        var schedule = BreakSchedule(interval: 45 * 60, breakLength: 300)
        XCTAssertEqual(schedule.restThreshold, 300)
        XCTAssertEqual(BreakSchedule(interval: 1200, breakLength: 20).restThreshold, 180)
        XCTAssertEqual(BreakSchedule(interval: 1200, breakLength: 600).restThreshold, 600)

        _ = schedule.update(now: start, idle: 0, quiet: false)
        // 离开不够久：照样算
        XCTAssertEqual(schedule.update(now: start.addingTimeInterval(20 * 60), idle: 240, quiet: false), .none)
        XCTAssertEqual(schedule.workStart, start)
        // 离开够久：算休息过了；没在提醒时不用收起什么
        XCTAssertEqual(schedule.update(now: start.addingTimeInterval(30 * 60), idle: 300, quiet: false), .none)
        XCTAssertNil(schedule.workStart)
        XCTAssertEqual(schedule.worked(now: start.addingTimeInterval(30 * 60)), 0)
        // 回来：从碰键盘鼠标的那一刻算起
        XCTAssertEqual(schedule.update(now: start.addingTimeInterval(40 * 60), idle: 30, quiet: false), .none)
        XCTAssertEqual(schedule.workStart, start.addingTimeInterval(40 * 60 - 30))

        // 提醒着的时候走开了：收起提醒
        let back = start.addingTimeInterval(40 * 60 - 30)
        XCTAssertEqual(schedule.update(now: back.addingTimeInterval(45 * 60), idle: 1, quiet: false), .remind)
        XCTAssertEqual(schedule.update(now: back.addingTimeInterval(52 * 60), idle: 400, quiet: false), .rested)
        XCTAssertFalse(schedule.isDue)
        XCTAssertNil(schedule.workStart)
    }

    func testQuietWhileVideoOrMeeting() {
        var schedule = BreakSchedule(interval: 45 * 60, breakLength: 300)
        // 一开始就在看视频：从现在算，不管多久没碰键盘鼠标
        XCTAssertEqual(schedule.update(now: start, idle: 600, quiet: true), .none)
        XCTAssertEqual(schedule.workStart, start)
        // 看着视频：不提醒，也不算休息
        XCTAssertEqual(schedule.update(now: start.addingTimeInterval(50 * 60), idle: 3000, quiet: true), .none)
        XCTAssertEqual(schedule.workStart, start)
        XCTAssertFalse(schedule.isDue)
        // 看完了：该提醒就提醒
        XCTAssertEqual(schedule.update(now: start.addingTimeInterval(51 * 60), idle: 2, quiet: false), .remind)

        // 开了 40 分钟的会，一直没碰键盘鼠标：会一结束不算休息过，该提醒就提醒
        var meeting = BreakSchedule(interval: 45 * 60, breakLength: 300)
        _ = meeting.update(now: start, idle: 0, quiet: false)
        XCTAssertEqual(meeting.update(now: start.addingTimeInterval(20 * 60), idle: 60, quiet: true), .none)
        XCTAssertEqual(meeting.update(now: start.addingTimeInterval(60 * 60), idle: 41 * 60, quiet: true), .none)
        XCTAssertEqual(meeting.update(now: start.addingTimeInterval(60 * 60 + 10), idle: 41 * 60 + 10, quiet: false), .remind)
        XCTAssertEqual(meeting.workStart, start)
        // 开完会真的走开了：从会结束的时候算，离开够久才算休息过
        XCTAssertEqual(meeting.update(now: start.addingTimeInterval(64 * 60), idle: 45 * 60, quiet: false), .none)
        XCTAssertTrue(meeting.isDue)
        XCTAssertEqual(meeting.update(now: start.addingTimeInterval(66 * 60), idle: 47 * 60, quiet: false), .rested)
        XCTAssertNil(meeting.workStart)
    }

    func testBreakCountdown() {
        var schedule = BreakSchedule(interval: 45 * 60, breakLength: 300)
        _ = schedule.update(now: start, idle: 0, quiet: false)
        _ = schedule.update(now: start.addingTimeInterval(45 * 60), idle: 0, quiet: false)
        let breakStart = start.addingTimeInterval(46 * 60)
        schedule.startBreak(now: breakStart)
        XCTAssertTrue(schedule.isOnBreak)
        XCTAssertFalse(schedule.isDue)
        XCTAssertNil(schedule.untilReminder(now: breakStart))
        XCTAssertEqual(schedule.breakRemaining(now: breakStart.addingTimeInterval(100)), 200)
        // 休息时打字也照样倒计时
        XCTAssertEqual(schedule.update(now: breakStart.addingTimeInterval(100), idle: 0, quiet: false), .none)
        XCTAssertEqual(schedule.update(now: breakStart.addingTimeInterval(300), idle: 0, quiet: true), .breakFinished)
        XCTAssertFalse(schedule.isOnBreak)
        XCTAssertNil(schedule.workStart)
        // 提前结束也算休息过
        schedule.startBreak(now: breakStart)
        schedule.finishBreak()
        XCTAssertFalse(schedule.isOnBreak)
        XCTAssertNil(schedule.workStart)
    }

    func testDisplayAssertions() {
        XCTAssertTrue(BreakSignals.keepsDisplayAwake([123: [["AssertType": "PreventUserIdleDisplaySleep", "AssertName": "Video Wake Lock"]]], ownPID: 1))
        XCTAssertTrue(BreakSignals.keepsDisplayAwake([7: [["AssertType": "PreventUserIdleSystemSleep"]], 9: [["AssertType": "NoDisplaySleepAssertion"]]], ownPID: 1))
        // Pop 自己的「保持唤醒」不算；只是不让电脑睡眠的不算
        XCTAssertFalse(BreakSignals.keepsDisplayAwake([1: [["AssertType": "PreventUserIdleDisplaySleep"]]], ownPID: 1))
        XCTAssertFalse(BreakSignals.keepsDisplayAwake([123: [["AssertType": "PreventUserIdleSystemSleep"]]], ownPID: 1))
        XCTAssertFalse(BreakSignals.keepsDisplayAwake([:], ownPID: 1))
        // 读这台 Mac 的不出错
        _ = BreakSignals.othersKeepDisplayAwake()
        XCTAssertGreaterThanOrEqual(BreakSignals.idleSeconds(), 0)
    }

    // MARK: - 文字

    func testTexts() {
        XCTAssertEqual(BreakReminder.durationText(0), "不到一分钟")
        XCTAssertEqual(BreakReminder.durationText(59), "不到一分钟")
        XCTAssertEqual(BreakReminder.durationText(60), "1 分钟")
        XCTAssertEqual(BreakReminder.durationText(45 * 60 + 30), "45 分钟")
        XCTAssertEqual(BreakReminder.durationText(60 * 60), "1 小时")
        XCTAssertEqual(BreakReminder.durationText(90 * 60), "1 小时 30 分钟")
        XCTAssertEqual(BreakReminder.lengthTitle(20), "20 秒")
        XCTAssertEqual(BreakReminder.lengthTitle(300), "5 分钟")
        XCTAssertEqual(BreakReminder.countdown(299.2), "5:00")
        XCTAssertEqual(BreakReminder.countdown(61), "1:01")
        XCTAssertEqual(BreakReminder.countdown(-3), "0:00")
    }

    // MARK: - 提醒

    func testReminderFlow() {
        let defaults = freshDefaults()
        var now = start
        var idle: TimeInterval = 0
        var quiet = false
        let reminder = BreakReminder(defaults: defaults, clock: { now }, idle: { idle }, quiet: { quiet }, isLive: false)
        XCTAssertFalse(reminder.isEnabled)
        XCTAssertEqual(reminder.intervalMinutes, 45)
        XCTAssertEqual(reminder.breakSeconds, 300)
        XCTAssertEqual(reminder.statusText, "没开。打开以后，连续用电脑 45 分钟会提醒你休息 5 分钟。")
        // 没开时不计时
        reminder.tick()
        XCTAssertNil(reminder.schedule.workStart)

        reminder.setEnabled(true)
        XCTAssertTrue(defaults.bool(forKey: BreakReminder.enabledKey))
        XCTAssertEqual(reminder.schedule.workStart, start)
        now = start.addingTimeInterval(32 * 60)
        reminder.tick()
        XCTAssertEqual(reminder.statusText, "已经连续用了 32 分钟，13 分钟后提醒休息")
        XCTAssertEqual(reminder.phase, .hidden)

        // 到点：弹出提醒
        now = start.addingTimeInterval(45 * 60)
        reminder.tick()
        XCTAssertEqual(reminder.phase, .reminder)
        XCTAssertEqual(reminder.statusText, "该休息了：已经连续用了 45 分钟")
        XCTAssertEqual(reminder.reminderDetail, "已经连续用了 45 分钟，起来活动活动、看看远处")

        // 5 分钟后再提醒
        reminder.snooze()
        XCTAssertEqual(reminder.phase, .hidden)
        XCTAssertEqual(reminder.statusText, "已经连续用了 45 分钟，5 分钟后提醒休息")
        now = start.addingTimeInterval(50 * 60)
        reminder.tick()
        XCTAssertEqual(reminder.phase, .reminder)

        // 休息：倒计时，走完了说一句
        reminder.takeBreak()
        XCTAssertEqual(reminder.phase, .onBreak)
        XCTAssertEqual(reminder.statusText, "正在休息，还剩 5:00")
        XCTAssertEqual(reminder.breakRemainingText, "5:00")
        XCTAssertEqual(reminder.breakProgress, 0, accuracy: 0.001)
        XCTAssertEqual(reminder.tip, "看看 6 米外的地方，眨眨眼")
        now = now.addingTimeInterval(150)
        reminder.tick()
        XCTAssertEqual(reminder.breakRemainingText, "2:30")
        XCTAssertEqual(reminder.breakProgress, 0.5, accuracy: 0.001)
        now = now.addingTimeInterval(150)
        reminder.tick()
        XCTAssertEqual(reminder.phase, .finished)
        XCTAssertEqual(reminder.statusText, "刚休息过，碰键盘鼠标时开始算")

        // 回来接着用；在开会：不提醒
        now = now.addingTimeInterval(60)
        reminder.tick()
        XCTAssertNotNil(reminder.schedule.workStart)
        quiet = true
        now = now.addingTimeInterval(50 * 60)
        idle = 1200
        reminder.tick()
        XCTAssertTrue(reminder.isQuiet)
        XCTAssertEqual(reminder.statusText, "已经连续用了 50 分钟。有 App 在放视频或者开会，先不提醒")
        XCTAssertNotEqual(reminder.phase, .reminder)
        // 会开完了：提醒；走开够久：收起
        quiet = false
        idle = 2
        reminder.tick()
        XCTAssertEqual(reminder.phase, .reminder)
        idle = 400
        now = now.addingTimeInterval(400)
        reminder.tick()
        XCTAssertEqual(reminder.phase, .hidden)
        XCTAssertEqual(reminder.statusText, "刚休息过，碰键盘鼠标时开始算")

        // 跳过：从现在重新算
        idle = 0
        reminder.tick()
        now = now.addingTimeInterval(45 * 60)
        reminder.tick()
        XCTAssertEqual(reminder.phase, .reminder)
        reminder.skip()
        XCTAssertEqual(reminder.phase, .hidden)
        XCTAssertEqual(reminder.schedule.workStart, now)

        // 关掉
        reminder.setEnabled(false)
        XCTAssertNil(reminder.schedule.workStart)
        XCTAssertEqual(reminder.statusText, "没开。打开以后，连续用电脑 45 分钟会提醒你休息 5 分钟。")
    }

    func testSleepCountsAsRest() {
        var now = start
        let reminder = BreakReminder(defaults: freshDefaults(), clock: { now }, idle: { 0 }, quiet: { false }, isLive: false)
        reminder.setEnabled(true)
        now = start.addingTimeInterval(45 * 60)
        reminder.tick()
        XCTAssertEqual(reminder.phase, .reminder)
        // 合上盖子睡了一个小时（睡醒时「多久没碰键盘鼠标」清零了）：算休息过了，提醒收起来，从睡醒算起
        reminder.willSleep()
        now = now.addingTimeInterval(60 * 60)
        reminder.didWake()
        XCTAssertEqual(reminder.phase, .hidden)
        XCTAssertFalse(reminder.schedule.isDue)
        XCTAssertEqual(reminder.schedule.workStart, now)
        // 只睡了两分钟：照样算
        now = now.addingTimeInterval(30 * 60)
        reminder.tick()
        reminder.willSleep()
        now = now.addingTimeInterval(120)
        reminder.didWake()
        XCTAssertEqual(reminder.statusText, "已经连续用了 32 分钟，13 分钟后提醒休息")
        // 正在休息时睡醒：休息照样倒计时
        reminder.takeBreak()
        reminder.willSleep()
        now = now.addingTimeInterval(400)
        reminder.didWake()
        XCTAssertEqual(reminder.phase, .finished)
    }

    func testMeetingHidesTheReminderAndBreaksKeepGoing() {
        let defaults = freshDefaults()
        var now = start
        var quiet = false
        let reminder = BreakReminder(defaults: defaults, clock: { now }, idle: { 0 }, quiet: { quiet }, isLive: false)
        reminder.setEnabled(true)
        now = start.addingTimeInterval(45 * 60)
        reminder.tick()
        XCTAssertEqual(reminder.phase, .reminder)
        // 提醒着的时候开始开会：先收起来，开完了再弹出来
        quiet = true
        now = now.addingTimeInterval(10)
        reminder.tick()
        XCTAssertEqual(reminder.phase, .hidden)
        XCTAssertTrue(reminder.schedule.isDue)
        quiet = false
        now = now.addingTimeInterval(30 * 60)
        reminder.tick()
        XCTAssertEqual(reminder.phase, .reminder)

        // 没开的时候点了「现在休息」，休息时打开：接着休息
        let other = BreakReminder(defaults: freshDefaults(), clock: { now }, idle: { 0 }, quiet: { false }, isLive: false)
        other.takeBreak()
        other.setEnabled(true)
        XCTAssertTrue(other.isEnabled)
        XCTAssertTrue(other.schedule.isOnBreak)
        XCTAssertEqual(other.phase, .onBreak)

        // 卸载时设置一起删掉了，又装上：按存着的来，不接着计时
        reminder.shutDown()
        defaults.removeObject(forKey: BreakReminder.enabledKey)
        reminder.startIfEnabled()
        XCTAssertFalse(reminder.isEnabled)
        XCTAssertEqual(reminder.statusText, "没开。打开以后，连续用电脑 45 分钟会提醒你休息 5 分钟。")
    }

    func testFullScreenBreakAndSettings() {
        let defaults = freshDefaults()
        var now = start
        let reminder = BreakReminder(defaults: defaults, clock: { now }, idle: { 0 }, quiet: { false }, isLive: false)
        reminder.setInterval(minutes: 30)
        reminder.setInterval(minutes: 7)
        reminder.setBreakLength(seconds: 20)
        reminder.setBreakLength(seconds: 42)
        reminder.fullScreen = true
        XCTAssertEqual(reminder.intervalMinutes, 30)
        XCTAssertEqual(reminder.breakSeconds, 20)
        // 盖住屏幕时上方不放小条
        reminder.takeBreak()
        XCTAssertEqual(reminder.phase, .onBreak)
        XCTAssertTrue(reminder.schedule.isOnBreak)
        XCTAssertEqual(reminder.statusText, "正在休息，还剩 0:20")
        reminder.endBreak()
        XCTAssertEqual(reminder.phase, .hidden)
        XCTAssertFalse(reminder.schedule.isOnBreak)
        // 第二次休息换一句
        now = now.addingTimeInterval(60)
        reminder.takeBreak()
        XCTAssertEqual(reminder.tip, "站起来走走，伸个懒腰")
        reminder.shutDown()
        XCTAssertFalse(reminder.schedule.isOnBreak)

        // 设置都记住
        let again = BreakReminder(defaults: defaults, isLive: false)
        XCTAssertEqual(again.intervalMinutes, 30)
        XCTAssertEqual(again.breakSeconds, 20)
        XCTAssertTrue(again.fullScreen)
        XCTAssertFalse(again.isEnabled)
        // 存的值不在几档里：用默认的
        defaults.set(7, forKey: BreakReminder.intervalKey)
        defaults.set(42, forKey: BreakReminder.lengthKey)
        let fallback = BreakReminder(defaults: defaults, isLive: false)
        XCTAssertEqual(fallback.intervalMinutes, 45)
        XCTAssertEqual(fallback.breakSeconds, 300)
    }

    func testPluginAndDemo() {
        XCTAssertTrue(BreakReminderPlugin().info.canHandle(.empty))
        let demo = BreakReminder.demo()
        XCTAssertTrue(demo.isEnabled)
        XCTAssertEqual(demo.statusText, "已经连续用了 32 分钟，13 分钟后提醒休息")
        XCTAssertEqual(BreakReminder.demo(phase: .reminder).phase, .reminder)
        XCTAssertEqual(Set(BreakReminder.defaultsKeys), Set(PluginCatalog.packages.first { $0.id == "breakReminder" }?.defaultsKeys ?? []))
    }
}
