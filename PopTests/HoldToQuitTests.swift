import CoreGraphics
import XCTest
@testable import Pop

@MainActor
final class HoldToQuitTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_790_820_000)
    private static let safari = HoldToQuit.FrontApp(pid: 42, bundleID: "com.apple.Safari", name: "Safari")

    private func freshDefaults() -> UserDefaults {
        let suite = "PopHoldToQuitTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    // MARK: - 按住、连按的判断

    func testHoldQuitsAfterTheDuration() {
        var quitGuard = QuitGuard(mode: .hold, duration: 1)
        XCTAssertEqual(quitGuard.pressQuit(app: 42, now: start), .swallow)
        XCTAssertTrue(quitGuard.isWaiting)
        XCTAssertEqual(quitGuard.progress(now: start.addingTimeInterval(0.5)), 0.5)
        XCTAssertEqual(quitGuard.repeatKey(), .swallow)
        XCTAssertNil(quitGuard.check(now: start.addingTimeInterval(0.9)))
        XCTAssertEqual(quitGuard.check(now: start.addingTimeInterval(1)), 42)
        XCTAssertFalse(quitGuard.isWaiting)
        XCTAssertNil(quitGuard.progress(now: start.addingTimeInterval(1.1)))
        // 还按着不放：自动重复的照样吞掉，不再退一次
        XCTAssertEqual(quitGuard.repeatKey(), .swallow)
        XCTAssertNil(quitGuard.check(now: start.addingTimeInterval(2)))
        XCTAssertEqual(quitGuard.releaseKey(), .swallow)
        XCTAssertNil(quitGuard.target)
        // 没吞着的键：放过
        XCTAssertEqual(quitGuard.releaseKey(), .pass)
        XCTAssertEqual(quitGuard.repeatKey(), .pass)
    }

    func testLettingGoEarlyKeepsTheApp() {
        var quitGuard = QuitGuard(mode: .hold, duration: 1)
        _ = quitGuard.pressQuit(app: 42, now: start)
        XCTAssertEqual(quitGuard.releaseKey(), .swallow)
        XCTAssertFalse(quitGuard.isWaiting)
        XCTAssertNil(quitGuard.check(now: start.addingTimeInterval(2)))
        // 先松开 ⌘：不退了，Q 松开之前自动重复的还吞着（App 里不会冒出一串 q）
        _ = quitGuard.pressQuit(app: 42, now: start)
        quitGuard.releaseCommand()
        XCTAssertFalse(quitGuard.isWaiting)
        XCTAssertEqual(quitGuard.repeatKey(), .swallow)
        XCTAssertNil(quitGuard.check(now: start.addingTimeInterval(2)))
        XCTAssertEqual(quitGuard.releaseKey(), .swallow)
    }

    func testPressTwice() {
        var quitGuard = QuitGuard(mode: .twice, duration: 1)
        XCTAssertEqual(quitGuard.pressQuit(app: 42, now: start), .swallow)
        XCTAssertEqual(quitGuard.releaseKey(), .swallow)
        // 第二下还剩多少时间；松开 ⌘ 也接着等
        XCTAssertEqual(quitGuard.progress(now: start.addingTimeInterval(0.25)), 0.75)
        quitGuard.releaseCommand()
        XCTAssertTrue(quitGuard.isWaiting)
        XCTAssertEqual(quitGuard.pressQuit(app: 42, now: start.addingTimeInterval(0.6)), .quit(42))
        XCTAssertFalse(quitGuard.isWaiting)
        XCTAssertEqual(quitGuard.repeatKey(), .swallow)
        XCTAssertEqual(quitGuard.releaseKey(), .swallow)
        XCTAssertNil(quitGuard.target)
        // 等太久：第二下当成新的第一下
        _ = quitGuard.pressQuit(app: 42, now: start)
        _ = quitGuard.releaseKey()
        XCTAssertNil(quitGuard.check(now: start.addingTimeInterval(1.2)))
        XCTAssertFalse(quitGuard.isWaiting)
        XCTAssertEqual(quitGuard.pressQuit(app: 42, now: start.addingTimeInterval(1.3)), .swallow)
        _ = quitGuard.releaseKey()
        // 第二下按在别的 App 里：从这个 App 重新算
        XCTAssertEqual(quitGuard.pressQuit(app: 7, now: start.addingTimeInterval(1.5)), .swallow)
        XCTAssertEqual(quitGuard.target, 7)
    }

    // MARK: - 拦 ⌘Q

    func testQuitShortcut() throws {
        func event(_ keyCode: CGKeyCode, _ flags: CGEventFlags) throws -> CGEvent {
            let event = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true))
            event.flags = flags
            return event
        }
        XCTAssertTrue(QuitKeyTap.isQuitShortcut(try event(12, .maskCommand)))
        // 开着大写锁定也算
        XCTAssertTrue(QuitKeyTap.isQuitShortcut(try event(12, [.maskCommand, .maskAlphaShift])))
        // ⇧⌘Q（退出登录）、⌃⌘Q（锁屏）、⌥⌘Q 不管
        XCTAssertFalse(QuitKeyTap.isQuitShortcut(try event(12, [.maskCommand, .maskShift])))
        XCTAssertFalse(QuitKeyTap.isQuitShortcut(try event(12, [.maskCommand, .maskControl])))
        XCTAssertFalse(QuitKeyTap.isQuitShortcut(try event(12, [.maskCommand, .maskAlternate])))
        XCTAssertFalse(QuitKeyTap.isQuitShortcut(try event(12, [])))
        XCTAssertFalse(QuitKeyTap.isQuitShortcut(try event(0, .maskCommand)))
    }

    func testHoldingQuitsTheFrontApp() {
        var now = start
        var sent: [pid_t] = []
        let model = HoldToQuit(defaults: freshDefaults(), isLive: false, clock: { now }, isTrusted: { true }, isInstalled: { _ in false })
        model.sendQuit = { sent.append($0) }
        model.frontmostApp = { Self.safari }
        model.startIfNeeded()
        XCTAssertTrue(model.isEnabled)
        XCTAssertTrue(model.isRunning)
        XCTAssertEqual(model.statusText, "正在拦 ⌘Q：按住 1 秒才退出")
        // ⌘Q 按下：吞掉，屏幕中间提示
        XCTAssertTrue(model.decide(isDown: true, keyCode: 12, isRepeat: false, isQuitShortcut: true))
        XCTAssertEqual(model.trackedKeyCode, 12)
        XCTAssertEqual(model.prompt?.app.name, "Safari")
        XCTAssertEqual(model.prompt?.progress, 0)
        XCTAssertEqual(model.prompt.map { QuitPromptView.title($0) }, "按住 ⌘Q 退出「Safari」")
        now = start.addingTimeInterval(0.5)
        XCTAssertTrue(model.decide(isDown: true, keyCode: 12, isRepeat: true, isQuitShortcut: true))
        model.tick()
        XCTAssertEqual(model.prompt?.progress, 0.5)
        XCTAssertTrue(sent.isEmpty)
        // 按够了：把 ⌘Q 交给 Safari
        now = start.addingTimeInterval(1)
        model.tick()
        XCTAssertEqual(sent, [42])
        XCTAssertEqual(model.prompt?.isQuitting, true)
        XCTAssertEqual(model.prompt.map { QuitPromptView.title($0) }, "正在退出「Safari」")
        // 还按着：不再发；松开也吞掉
        now = start.addingTimeInterval(1.5)
        XCTAssertTrue(model.decide(isDown: true, keyCode: 12, isRepeat: true, isQuitShortcut: true))
        model.tick()
        XCTAssertEqual(sent, [42])
        XCTAssertTrue(model.decide(isDown: false, keyCode: 12, isRepeat: false, isQuitShortcut: false))
        XCTAssertNil(model.trackedKeyCode)
        XCTAssertFalse(model.decide(isDown: false, keyCode: 12, isRepeat: false, isQuitShortcut: false))
        // 没按 ⌘ 的 q、别的键：放过
        XCTAssertFalse(model.decide(isDown: true, keyCode: 12, isRepeat: false, isQuitShortcut: false))
        XCTAssertFalse(model.decide(isDown: true, keyCode: 0, isRepeat: false, isQuitShortcut: false))
    }

    func testLettingGoEarlyHidesThePrompt() {
        var now = start
        var sent: [pid_t] = []
        let model = HoldToQuit(defaults: freshDefaults(), isLive: false, clock: { now }, isTrusted: { true }, isInstalled: { _ in false })
        model.sendQuit = { sent.append($0) }
        model.frontmostApp = { Self.safari }
        model.startIfNeeded()
        XCTAssertTrue(model.decide(isDown: true, keyCode: 12, isRepeat: false, isQuitShortcut: true))
        now = start.addingTimeInterval(0.4)
        XCTAssertTrue(model.decide(isDown: false, keyCode: 12, isRepeat: false, isQuitShortcut: false))
        XCTAssertNil(model.prompt)
        // 收起以后窗口里还画着上一次的样子，大小不变
        XCTAssertEqual(model.promptState.lastShown?.app.name, "Safari")
        now = start.addingTimeInterval(2)
        model.tick()
        XCTAssertTrue(sent.isEmpty)
        // 先松开 ⌘：也不退
        XCTAssertTrue(model.decide(isDown: true, keyCode: 12, isRepeat: false, isQuitShortcut: true))
        model.releaseCommand()
        XCTAssertNil(model.prompt)
        now = start.addingTimeInterval(4)
        model.tick()
        XCTAssertTrue(model.decide(isDown: true, keyCode: 12, isRepeat: true, isQuitShortcut: false))
        XCTAssertTrue(model.decide(isDown: false, keyCode: 12, isRepeat: false, isQuitShortcut: false))
        XCTAssertTrue(sent.isEmpty)
        // 没收到松开就又按了一下：当作松开过，重新开始
        XCTAssertTrue(model.decide(isDown: true, keyCode: 12, isRepeat: false, isQuitShortcut: true))
        XCTAssertTrue(model.decide(isDown: true, keyCode: 12, isRepeat: false, isQuitShortcut: true))
        XCTAssertEqual(model.prompt?.progress, 0)
    }

    func testPressingTwice() {
        var now = start
        var sent: [pid_t] = []
        let defaults = freshDefaults()
        let model = HoldToQuit(defaults: defaults, isLive: false, clock: { now }, isTrusted: { true }, isInstalled: { _ in false })
        model.sendQuit = { sent.append($0) }
        model.frontmostApp = { Self.safari }
        model.setMode(.twice)
        model.startIfNeeded()
        XCTAssertEqual(model.mode, .twice)
        XCTAssertEqual(model.statusText, "正在拦 ⌘Q：1 秒内连按两下才退出")
        XCTAssertTrue(model.decide(isDown: true, keyCode: 12, isRepeat: false, isQuitShortcut: true))
        XCTAssertEqual(model.prompt.map { QuitPromptView.title($0) }, "再按一次 ⌘Q 退出「Safari」")
        XCTAssertEqual(model.prompt?.progress, 1)
        XCTAssertTrue(model.decide(isDown: false, keyCode: 12, isRepeat: false, isQuitShortcut: false))
        now = start.addingTimeInterval(0.5)
        model.tick()
        XCTAssertEqual(model.prompt?.progress, 0.5)
        XCTAssertTrue(model.decide(isDown: true, keyCode: 12, isRepeat: false, isQuitShortcut: true))
        XCTAssertEqual(sent, [42])
        XCTAssertEqual(model.prompt?.isQuitting, true)
        XCTAssertTrue(model.decide(isDown: false, keyCode: 12, isRepeat: false, isQuitShortcut: false))
        // 只按一下：过了时间提示收起，什么都不发
        now = start.addingTimeInterval(5)
        XCTAssertTrue(model.decide(isDown: true, keyCode: 12, isRepeat: false, isQuitShortcut: true))
        XCTAssertEqual(model.prompt?.isQuitting, false)
        XCTAssertTrue(model.decide(isDown: false, keyCode: 12, isRepeat: false, isQuitShortcut: false))
        now = start.addingTimeInterval(6.1)
        model.tick()
        XCTAssertNil(model.prompt)
        XCTAssertEqual(sent, [42])
    }

    func testExceptionsFinderAndSwitchingApps() {
        var now = start
        var sent: [pid_t] = []
        let model = HoldToQuit(defaults: freshDefaults(), isLive: false, clock: { now }, isTrusted: { true }, isInstalled: { _ in false })
        model.sendQuit = { sent.append($0) }
        let terminal = HoldToQuit.FrontApp(pid: 7, bundleID: "com.apple.Terminal", name: "终端")
        let finder = HoldToQuit.FrontApp(pid: 8, bundleID: HoldToQuit.finderID, name: "访达")
        let notes = HoldToQuit.FrontApp(pid: 9, bundleID: "com.apple.Notes", name: "备忘录")
        model.startIfNeeded()
        // 访达的 ⌘Q 本来就不退出，照旧交给它；加也加不进例外
        XCTAssertFalse(model.pressQuit(in: finder))
        model.addException(HoldToQuit.finderID)
        XCTAssertEqual(model.exceptions, [])
        // 加进例外的照旧一按就退出，拿掉以后又拦
        model.addException("com.apple.Terminal")
        model.addException("com.apple.Terminal")
        XCTAssertEqual(model.exceptions, ["com.apple.Terminal"])
        XCTAssertFalse(model.pressQuit(in: terminal))
        model.removeException("com.apple.Terminal")
        XCTAssertTrue(model.pressQuit(in: terminal))
        _ = model.releaseKey()
        // 按住的时候前台换成了别的 App：不退，免得退错
        model.frontmostApp = { notes }
        XCTAssertTrue(model.pressQuit(in: terminal))
        now = start.addingTimeInterval(1.5)
        model.tick()
        XCTAssertTrue(sent.isEmpty)
        XCTAssertNil(model.prompt)
        _ = model.releaseKey()
        // 关掉以后照旧一按就退出
        model.setEnabled(false)
        XCTAssertFalse(model.isRunning)
        XCTAssertFalse(model.pressQuit(in: notes))
        XCTAssertEqual(model.statusText, "没开：⌘Q 一按就退出")
        // 没装了的 App 只写 bundle ID
        XCTAssertEqual(model.exceptionApp("com.example.missing").name, "com.example.missing")
    }

    func testChromeStartsAsAnException() {
        let defaults = freshDefaults()
        let isInstalled: (String) -> Bool = { $0 == "com.google.Chrome" }
        let chrome = HoldToQuit.FrontApp(pid: 5, bundleID: "com.google.Chrome", name: "Google Chrome")
        // 装了 Chrome：一开始就在例外里，交给它自己（它能设成按住 ⌘Q 才退出，收到补发的 ⌘Q 只当是按了一下）
        let model = HoldToQuit(defaults: defaults, isLive: false, isTrusted: { true }, isInstalled: isInstalled)
        XCTAssertEqual(model.exceptions, ["com.google.Chrome"])
        XCTAssertTrue(model.passes(chrome))
        // 拿掉以后记住，不再自己加回来
        model.removeException("com.google.Chrome")
        XCTAssertFalse(model.passes(chrome))
        let again = HoldToQuit(defaults: defaults, isLive: false, isTrusted: { true }, isInstalled: isInstalled)
        XCTAssertEqual(again.exceptions, [])
        // 卸载时设置一起删掉，再装上：又在例外里
        for key in HoldToQuit.defaultsKeys {
            defaults.removeObject(forKey: key)
        }
        again.startIfNeeded()
        XCTAssertEqual(again.exceptions, ["com.google.Chrome"])
        again.shutDown()
    }

    func testSettingsAreRemembered() {
        let defaults = freshDefaults()
        let model = HoldToQuit(defaults: defaults, isLive: false, isTrusted: { true }, isInstalled: { _ in false })
        // 没设过：开着，按住 1 秒
        XCTAssertTrue(model.isEnabled)
        XCTAssertEqual(model.mode, .hold)
        XCTAssertEqual(model.duration, 1)
        model.setMode(.twice)
        model.setDuration(1.5)
        model.setDuration(3)
        model.addException("com.apple.Terminal")
        model.setEnabled(false)
        let again = HoldToQuit(defaults: defaults, isLive: false, isTrusted: { true }, isInstalled: { _ in false })
        XCTAssertFalse(again.isEnabled)
        XCTAssertEqual(again.mode, .twice)
        XCTAssertEqual(again.duration, 1.5)
        XCTAssertEqual(again.exceptions, ["com.apple.Terminal"])
        // 存的值不对时用默认的
        defaults.set(7.0, forKey: HoldToQuit.durationKey)
        defaults.set("triple", forKey: HoldToQuit.modeKey)
        again.startIfNeeded()
        XCTAssertEqual(again.duration, 1)
        XCTAssertEqual(again.mode, .hold)
        XCTAssertFalse(again.isRunning)
        // 卸载时设置一起删掉，再装上：开着
        for key in HoldToQuit.defaultsKeys {
            defaults.removeObject(forKey: key)
        }
        again.startIfNeeded()
        XCTAssertTrue(again.isEnabled)
        XCTAssertTrue(again.isRunning)
        XCTAssertEqual(again.exceptions, [])
        again.shutDown()
        XCTAssertFalse(again.isRunning)
    }

    func testPermission() {
        var trusted = false
        let model = HoldToQuit(defaults: freshDefaults(), isLive: false, isTrusted: { trusted }, isInstalled: { _ in false })
        model.startIfNeeded()
        XCTAssertTrue(model.needsPermission)
        XCTAssertFalse(model.isRunning)
        XCTAssertEqual(model.statusText, "要先在「系统设置 → 隐私与安全性 → 辅助功能」里允许 Pop，才能拦下 ⌘Q")
        trusted = true
        model.startIfNeeded()
        XCTAssertFalse(model.needsPermission)
        XCTAssertTrue(model.isRunning)
    }

    func testPluginAndDemo() {
        XCTAssertTrue(HoldToQuitPlugin().info.accepts.isEmpty)
        XCTAssertEqual(Set(HoldToQuit.defaultsKeys), Set(PluginCatalog.packages.first { $0.id == "holdToQuit" }?.defaultsKeys ?? []))
        XCTAssertEqual(HoldToQuit.durationTitle(0.5), "0.5 秒")
        XCTAssertEqual(HoldToQuit.durationTitle(2), "2 秒")
        let demo = HoldToQuit.demo()
        XCTAssertTrue(demo.isEnabled)
        XCTAssertTrue(demo.isRunning)
        XCTAssertEqual(demo.exceptions, ["com.apple.Terminal"])
        XCTAssertEqual(demo.statusText, "正在拦 ⌘Q：按住 1 秒才退出")
    }
}
