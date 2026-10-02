import AppKit
import XCTest
@testable import Pop

@MainActor
final class SleepTimerTests: XCTestCase {
    private func freshDefaults() -> UserDefaults {
        let suite = "PopSleepTimerTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    /// 假的睡眠、关机、音量、通知和时钟
    private final class World {
        var performed: [SleepTimerAction] = []
        var performResult: String?
        var permission: String?
        var permissionChecks = 0
        var volume: Float? = 0.8
        var volumes: [Float] = []
        var notices: [(title: String, body: String)] = []
        /// 2026 年 10 月 9 日 23:01:19（UTC）
        var now = Date(timeIntervalSince1970: 1_791_586_879)
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }

    private func make(defaults: UserDefaults? = nil, world: World = World()) -> (SleepTimer, World) {
        let environment = SleepTimer.Environment(
            perform: { action in
                world.performed.append(action)
                return world.performResult
            },
            checkPermission: {
                world.permissionChecks += 1
                return world.permission
            },
            volume: { world.volume },
            setVolume: { value in
                world.volumes.append(value)
                world.volume = value
            },
            notify: { title, body in world.notices.append((title, body)) },
            now: { world.now },
            calendar: calendar)
        return (SleepTimer(defaults: defaults ?? freshDefaults(), environment: environment, isLive: false), world)
    }

    private func at(_ hour: Int, _ minute: Int, day: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute)) ?? Date()
    }

    func testStartAfterMinutesAndAtTime() async {
        let (model, world) = make()
        XCTAssertEqual(world.now, calendar.date(from: DateComponents(year: 2026, month: 10, day: 9, hour: 23, minute: 1, second: 19)))
        await model.start(minutes: 7)
        XCTAssertNil(model.pending, "不在几档里的不要")
        await model.start(minutes: 45)
        XCTAssertEqual(model.pending, SleepTimer.Pending(deadline: world.now.addingTimeInterval(45 * 60), action: .sleep))
        XCTAssertEqual(model.minutes, 45)
        // 到几点：今天的还没过就是今天
        await model.start(at: at(23, 30))
        XCTAssertEqual(model.pending?.deadline, at(23, 30))
        // 已经过了、不到一分钟以后的：明天
        await model.start(at: at(22, 0))
        XCTAssertEqual(model.pending?.deadline, at(22, 0, day: 10))
        await model.start(at: at(23, 2))
        XCTAssertEqual(model.pending?.deadline, at(23, 2, day: 10))
        await model.start(at: at(23, 3))
        XCTAssertEqual(model.pending?.deadline, at(23, 3))
        XCTAssertTrue(world.performed.isEmpty)
    }

    func testWarningFadesVolumeThenSleeps() async {
        let (model, world) = make()
        await model.start(minutes: 15)
        let deadline = world.now.addingTimeInterval(15 * 60)
        // 还早：不提示、不动音量
        world.now = deadline.addingTimeInterval(-70)
        model.tick()
        XCTAssertFalse(model.isWarning)
        XCTAssertTrue(world.volumes.isEmpty)
        // 最后一分钟：提示，音量从 0.8 慢慢往下调
        world.now = deadline.addingTimeInterval(-60)
        model.tick()
        XCTAssertTrue(model.isWarning)
        XCTAssertEqual(model.fadedFrom, 0.8)
        world.now = deadline.addingTimeInterval(-30)
        model.tick()
        XCTAssertEqual(world.volume ?? 0, 0.4, accuracy: 0.001)
        // 到点：睡眠，音量调到 0
        world.now = deadline
        model.tick()
        await model.firing?.value
        XCTAssertEqual(world.performed, [.sleep])
        XCTAssertNil(model.pending)
        XCTAssertFalse(model.isWarning)
        XCTAssertEqual(world.volume, 0)
        // 醒来：音量调回去
        model.woke()
        XCTAssertEqual(world.volume, 0.8)
        XCTAssertNil(model.fadedFrom)
    }

    func testPostponeAndCancel() async {
        let (model, world) = make()
        await model.start(minutes: 30)
        let deadline = world.now.addingTimeInterval(30 * 60)
        world.now = deadline.addingTimeInterval(-20)
        model.tick()
        XCTAssertTrue(model.isWarning)
        // 推迟：从现在算 10 分钟，音量调回去
        model.postpone()
        XCTAssertEqual(model.pending?.deadline, world.now.addingTimeInterval(10 * 60))
        XCTAssertFalse(model.isWarning)
        XCTAssertEqual(world.volume, 0.8)
        // 还早的时候推迟：在原来的时间上加
        let (early, earlyWorld) = make()
        await early.start(minutes: 30)
        early.postpone()
        XCTAssertEqual(early.pending?.deadline, earlyWorld.now.addingTimeInterval(40 * 60))
        // 取消
        world.now = model.pending?.deadline.addingTimeInterval(-10) ?? world.now
        model.tick()
        model.cancel()
        XCTAssertNil(model.pending)
        XCTAssertEqual(world.volume, 0.8)
        world.now += 60
        model.tick()
        XCTAssertTrue(world.performed.isEmpty)
    }

    func testShutDownAsksForPermissionFirst() async {
        let (model, world) = make()
        model.setAction(.shutDown)
        world.permission = "要先在「系统设置 → 隐私与安全性 → 自动化」里允许 Pop 控制「System Events」"
        await model.start(minutes: 60)
        XCTAssertNil(model.pending)
        XCTAssertEqual(model.message, world.permission)
        XCTAssertEqual(world.permissionChecks, 1)
        // 允许了
        world.permission = nil
        await model.start(minutes: 60)
        XCTAssertEqual(model.pending?.action, .shutDown)
        XCTAssertNil(model.message)
        // 睡眠不用问
        model.setAction(.sleep)
        await model.start(minutes: 15)
        XCTAssertEqual(world.permissionChecks, 2)
    }

    func testFailureAndActionsWithoutFade() async {
        let (model, world) = make()
        // 锁屏：不动音量
        model.setAction(.lock)
        await model.start(minutes: 15)
        world.now += 15 * 60 - 30
        model.tick()
        XCTAssertTrue(model.isWarning)
        XCTAssertTrue(world.volumes.isEmpty)
        world.now += 30
        model.tick()
        await model.firing?.value
        XCTAssertEqual(world.performed, [.lock])
        XCTAssertTrue(world.notices.isEmpty)
        // 关掉「慢慢调小音量」：睡眠也不动音量
        model.setAction(.sleep)
        model.setFades(false)
        await model.start(minutes: 15)
        world.now += 15 * 60 - 30
        model.tick()
        XCTAssertTrue(world.volumes.isEmpty)
        // 没做成：说一声，音量调回去
        model.setFades(true)
        world.performResult = "睡眠失败"
        await model.start(minutes: 15)
        world.now += 15 * 60 - 30
        model.tick()
        world.now += 30
        model.tick()
        await model.firing?.value
        XCTAssertEqual(world.notices.first?.title, "定时睡眠没做成")
        XCTAssertEqual(world.notices.first?.body, "睡眠失败")
        XCTAssertEqual(world.volume, 0.8)
        XCTAssertNil(model.fadedFrom)
    }

    func testRelaunchAndWake() async {
        let defaults = freshDefaults()
        let world = World()
        let (model, _) = make(defaults: defaults, world: world)
        await model.start(minutes: 30)
        // Pop 重新打开：还没到点的接着等
        let (reopened, _) = make(defaults: defaults, world: world)
        reopened.startIfNeeded()
        XCTAssertEqual(reopened.pending, model.pending)
        // 最后一分钟调小了音量，这时关机了：下次打开 Pop 时调回去
        world.now += 30 * 60 - 30
        model.tick()
        XCTAssertEqual(world.volume ?? 0, 0.4, accuracy: 0.001)
        world.volume = 0.4
        let (afterReboot, _) = make(defaults: defaults, world: world)
        world.now += 3600
        afterReboot.startIfNeeded()
        XCTAssertEqual(world.volume, 0.8)
        XCTAssertNil(afterReboot.pending, "过了点的不再做")
        XCTAssertTrue(world.performed.isEmpty)
        // 睡着的时候过了点：醒来不再睡
        let (sleeper, sleeperWorld) = make()
        await sleeper.start(minutes: 15)
        sleeperWorld.now += 3600
        sleeper.woke()
        XCTAssertNil(sleeper.pending)
        XCTAssertTrue(sleeperWorld.performed.isEmpty)
        // 卸载：取消
        let (removed, removedWorld) = make()
        await removed.start(minutes: 15)
        removed.shutDown()
        XCTAssertNil(removed.pending)
        removedWorld.now += 3600
        removed.tick()
        XCTAssertTrue(removedWorld.performed.isEmpty)
    }

    func testSettingsAndTitles() {
        let defaults = freshDefaults()
        let (model, _) = make(defaults: defaults)
        XCTAssertEqual(model.action, .sleep)
        XCTAssertTrue(model.fades)
        model.setAction(.displaySleep)
        model.setFades(false)
        let (reopened, _) = make(defaults: defaults)
        XCTAssertEqual(reopened.action, .displaySleep)
        XCTAssertFalse(reopened.fades)
        XCTAssertEqual(SleepTimer.durations.map(SleepTimer.durationTitle), ["15 分钟", "30 分钟", "45 分钟", "1 小时", "1 小时 30 分钟", "2 小时"])
        XCTAssertEqual(SleepTimerAction.allCases.map(\.title), ["睡眠", "熄屏", "锁屏", "关机"])
        XCTAssertEqual(SleepTimerAction.sleep.at("23:30"), "23:30 睡眠")
        XCTAssertEqual(SleepTimerAction.shutDown.after("0:42"), "0:42 后关机")
        XCTAssertEqual(SleepTimer.clock(28 * 60 + 40.2), "28:41")
        XCTAssertEqual(SleepTimer.clock(-3), "0:00")
        XCTAssertTrue(SleepTimerAction.sleep.fadesVolume)
        XCTAssertFalse(SleepTimerAction.lock.fadesVolume)
        // 「到几点」默认一小时以后，往后取整到五分钟
        XCTAssertEqual(SleepTimerView.roundedHourLater(from: at(23, 1).addingTimeInterval(19), calendar: calendar), at(0, 5, day: 10))
        XCTAssertEqual(SleepTimerView.roundedHourLater(from: at(22, 55), calendar: calendar), at(23, 55))
        let start = Date(timeIntervalSince1970: 1_791_586_879)
        XCTAssertNil(SleepTimer.Pending(dictionary: ["deadline": start, "action": "explode"]))
        XCTAssertEqual(SleepTimer.Pending(dictionary: SleepTimer.Pending(deadline: start, action: .lock).dictionary)?.action, .lock)
    }

    func testPluginAndDemo() {
        let plugin = SleepTimerPlugin()
        XCTAssertEqual(plugin.info.id, SleepTimerPlugin.id)
        XCTAssertTrue(plugin.info.canHandle(.empty))
        let active = SleepTimer.demo(remaining: 28 * 60 + 41)
        XCTAssertEqual(active.pending?.action, .sleep)
        XCTAssertFalse(active.isWarning)
        XCTAssertTrue(SleepTimer.demo(remaining: 42).isWarning)
        XCTAssertNil(SleepTimer.demo(remaining: nil).pending)
        // 插件包目录信息（plugin.json）里卸载时要删的偏好和代码里用的一样
        XCTAssertEqual(Set(SleepTimer.defaultsKeys), Set(TestCatalog.publishedMeta("SleepTimer")?.defaultsKeys ?? []))
    }
}
