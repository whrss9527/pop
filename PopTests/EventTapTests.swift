import CoreGraphics
import XCTest
@testable import Pop

@MainActor
final class EventTapThreadTests: XCTestCase {
    /// 拦截的线程把决定交给主线程：主线程空着时照它的决定；主线程正忙时最多等一小会儿就按 fallback 处理，
    /// 不让整个系统的键盘、鼠标跟着卡住
    func testAskMainDoesNotWaitLongForABusyMainThread() async {
        let free = await Task.detached { EventTapThread.askMain(fallback: true) { false } }.value
        XCTAssertFalse(free)

        let asking = DispatchSemaphore(value: 0)
        let busy = Task.detached { () -> (answer: Bool, waited: TimeInterval) in
            asking.signal()
            let asked = Date()
            let answer = EventTapThread.askMain(timeout: 0.1, fallback: true) { false }
            return (answer, Date().timeIntervalSince(asked))
        }
        // 主线程卡住：等那边开始问了，再卡 0.5 秒
        blockMainThread(after: asking, for: 0.5)
        let result = await busy.value
        XCTAssertTrue(result.answer)
        XCTAssertLessThan(result.waited, 0.4)
    }

    /// 同步地卡住主线程（在 async 的测试里不能直接等信号、调用 Thread.sleep）
    private func blockMainThread(after signal: DispatchSemaphore, for seconds: TimeInterval) {
        signal.wait()
        Thread.sleep(forTimeInterval: seconds)
    }
}

/// 长按右键、修饰键+右键、中键的判定（拦截的线程上那一半）：计时、补发事件都换成记下来，手动触发
final class MouseTriggerTests: XCTestCase {
    private final class Recorder: @unchecked Sendable {
        var signals: [MouseTriggerSignal] = []
        var posted: [(type: CGEventType, location: CGPoint)] = []
        var asked = 0
        var accepts = true
        var pressed = true
        var recovery: [(fire: () -> Void, cancelled: Bool)] = []
        var timers: [(seconds: TimeInterval, fire: () -> Void, cancelled: Bool)] = []

        func fireTimer(_ index: Int = 0) {
            timers[index].fire()
        }
    }

    private func makeCore(_ configuration: MouseTrigger.Configuration = .init(), recorder: Recorder) -> MouseTriggerCore {
        MouseTriggerCore(configuration: configuration,
                         shouldBegin: {
                             recorder.asked += 1
                             return recorder.accepts
                         },
                         deliver: { recorder.signals.append($0) },
                         post: { events in recorder.posted += events.map { (type: $0.type, location: $0.location) } },
                         startTimer: { seconds, fire in
                             let index = recorder.timers.count
                             recorder.timers.append((seconds, fire, false))
                             return { recorder.timers[index].cancelled = true }
                         }, startRecoveryTimer: { _, fire in
                             let index = recorder.recovery.count
                             recorder.recovery.append((fire, false))
                             return { recorder.recovery[index].cancelled = true }
                         }, isPressed: { _ in recorder.pressed })
    }

    private func mouse(_ type: CGEventType, _ x: CGFloat, _ y: CGFloat, button: CGMouseButton = .right,
                       flags: CGEventFlags = []) throws -> CGEvent {
        let event = try XCTUnwrap(CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: CGPoint(x: x, y: y),
                                          mouseButton: button))
        event.flags = flags
        return event
    }

    func testLongPressActivatesAndTakesTheDragAndRelease() throws {
        let recorder = Recorder()
        let core = makeCore(recorder: recorder)
        // 按下先扣住，开始计时
        XCTAssertTrue(core.handle(type: .rightMouseDown, event: try mouse(.rightMouseDown, 100, 100)))
        XCTAssertEqual(recorder.asked, 1)
        XCTAssertEqual(recorder.timers.count, 1)
        XCTAssertEqual(recorder.timers[0].seconds, 0.25, accuracy: 0.05)
        XCTAssertTrue(recorder.signals.isEmpty)
        // 抖了几个像素不算拖动
        XCTAssertTrue(core.handle(type: .rightMouseDragged, event: try mouse(.rightMouseDragged, 103, 102)))
        XCTAssertTrue(recorder.posted.isEmpty)

        recorder.fireTimer()
        XCTAssertEqual(recorder.signals, [.activate(CGPoint(x: 100, y: 100))])
        XCTAssertTrue(core.handle(type: .rightMouseDragged, event: try mouse(.rightMouseDragged, 160, 120)))
        XCTAssertTrue(core.handle(type: .rightMouseUp, event: try mouse(.rightMouseUp, 170, 125)))
        XCTAssertEqual(recorder.signals, [.activate(CGPoint(x: 100, y: 100)), .drag(CGPoint(x: 160, y: 120)),
                                          .release(CGPoint(x: 170, y: 125))])
        // 扣住的按下事件不再补发：目标 App 感知不到这次按压
        XCTAssertTrue(recorder.posted.isEmpty)
    }

    func testQuickClickIsGivenBackToTheSystem() throws {
        let recorder = Recorder()
        let core = makeCore(recorder: recorder)
        XCTAssertTrue(core.handle(type: .rightMouseDown, event: try mouse(.rightMouseDown, 10, 20)))
        // 计时到之前松开：按原顺序补发按下、松开，系统的右键菜单照常出来
        XCTAssertTrue(core.handle(type: .rightMouseUp, event: try mouse(.rightMouseUp, 10, 20)))
        XCTAssertEqual(recorder.posted.map { $0.type }, [.rightMouseDown, .rightMouseUp])
        XCTAssertTrue(recorder.timers[0].cancelled)
        // 取消前已经到点的计时也不算
        recorder.fireTimer()
        XCTAssertTrue(recorder.signals.isEmpty)
    }

    func testDraggingAwayIsGivenBackToTheSystem() throws {
        let recorder = Recorder()
        let core = makeCore(recorder: recorder)
        XCTAssertTrue(core.handle(type: .rightMouseDown, event: try mouse(.rightMouseDown, 10, 10)))
        // 拖开超过 6 个点：补发按下和这次拖动，之后的都放行（游戏、3D 软件的右键拖拽）
        XCTAssertTrue(core.handle(type: .rightMouseDragged, event: try mouse(.rightMouseDragged, 30, 10)))
        XCTAssertEqual(recorder.posted.map { $0.type }, [.rightMouseDown, .rightMouseDragged])
        XCTAssertTrue(recorder.timers[0].cancelled)
        XCTAssertFalse(core.handle(type: .rightMouseDragged, event: try mouse(.rightMouseDragged, 60, 10)))
        XCTAssertFalse(core.handle(type: .rightMouseUp, event: try mouse(.rightMouseUp, 60, 10)))
        recorder.fireTimer()
        XCTAssertTrue(recorder.signals.isEmpty)
        // 下一次按压重新判定
        XCTAssertTrue(core.handle(type: .rightMouseDown, event: try mouse(.rightMouseDown, 60, 10)))
        XCTAssertEqual(recorder.timers.count, 2)
    }

    func testDeclinedPressPassesThrough() throws {
        let recorder = Recorder()
        recorder.accepts = false
        let core = makeCore(recorder: recorder)
        // 排除的 App、已经暂停，或者主线程正忙没来得及回答：这次按压原样交给系统
        XCTAssertFalse(core.handle(type: .rightMouseDown, event: try mouse(.rightMouseDown, 10, 10)))
        XCTAssertFalse(core.handle(type: .rightMouseDragged, event: try mouse(.rightMouseDragged, 11, 10)))
        XCTAssertFalse(core.handle(type: .rightMouseUp, event: try mouse(.rightMouseUp, 11, 10)))
        XCTAssertTrue(recorder.timers.isEmpty)
        XCTAssertTrue(recorder.posted.isEmpty)
    }

    func testReplayedEventsPassThrough() throws {
        let recorder = Recorder()
        let core = makeCore(recorder: recorder)
        let replayed = try mouse(.rightMouseDown, 10, 10)
        replayed.setIntegerValueField(.eventSourceUserData, value: MouseTriggerCore.replayMarker)
        XCTAssertFalse(core.handle(type: .rightMouseDown, event: replayed))
        XCTAssertEqual(recorder.asked, 0)
    }

    func testChangingSettingsOrStoppingGivesTheHeldPressBack() throws {
        let recorder = Recorder()
        let core = makeCore(recorder: recorder)
        XCTAssertTrue(core.handle(type: .rightMouseDown, event: try mouse(.rightMouseDown, 10, 10)))
        core.configuration = MouseTrigger.Configuration(mode: .longPressRight, holdDuration: 0.5, modifier: .option)
        XCTAssertEqual(recorder.posted.map { $0.type }, [.rightMouseDown])
        recorder.fireTimer()
        XCTAssertTrue(recorder.signals.isEmpty)
        // 按新的时长计时
        XCTAssertTrue(core.handle(type: .rightMouseDown, event: try mouse(.rightMouseDown, 10, 10)))
        XCTAssertEqual(recorder.timers[1].seconds, 0.5, accuracy: 0.05)

        // 系统停用过拦截（回调太慢）：扣着的也还回去
        XCTAssertFalse(core.handle(type: .tapDisabledByTimeout, event: try mouse(.rightMouseDown, 0, 0)))
        XCTAssertEqual(recorder.posted.map { $0.type }, [.rightMouseDown, .rightMouseDown])

        // 停下来以后：扣着的还回去，计时到了也不唤起，之后的按压都放过
        XCTAssertTrue(core.handle(type: .rightMouseDown, event: try mouse(.rightMouseDown, 10, 10)))
        core.stop()
        XCTAssertEqual(recorder.posted.count, 3)
        recorder.fireTimer(2)
        XCTAssertTrue(recorder.signals.isEmpty)
        XCTAssertFalse(core.handle(type: .rightMouseDown, event: try mouse(.rightMouseDown, 10, 10)))
        XCTAssertEqual(recorder.timers.count, 3)
    }

    func testModifierRightClick() throws {
        let recorder = Recorder()
        let core = makeCore(MouseTrigger.Configuration(mode: .modifierRightClick, holdDuration: 0.25, modifier: .option),
                            recorder: recorder)
        // 没按着修饰键的右键马上放过，不用问主线程
        XCTAssertFalse(core.handle(type: .rightMouseDown, event: try mouse(.rightMouseDown, 10, 10)))
        XCTAssertFalse(core.handle(type: .rightMouseUp, event: try mouse(.rightMouseUp, 10, 10)))
        XCTAssertEqual(recorder.asked, 0)

        XCTAssertTrue(core.handle(type: .rightMouseDown, event: try mouse(.rightMouseDown, 10, 10, flags: .maskAlternate)))
        XCTAssertTrue(core.handle(type: .rightMouseDragged, event: try mouse(.rightMouseDragged, 40, 10, flags: .maskAlternate)))
        XCTAssertTrue(core.handle(type: .rightMouseUp, event: try mouse(.rightMouseUp, 40, 10)))
        XCTAssertEqual(recorder.signals, [.activate(CGPoint(x: 10, y: 10)), .drag(CGPoint(x: 40, y: 10)),
                                          .release(CGPoint(x: 40, y: 10))])
        XCTAssertTrue(recorder.timers.isEmpty)
    }

    func testMiddleClick() throws {
        let recorder = Recorder()
        let core = makeCore(MouseTrigger.Configuration(mode: .middleClick, holdDuration: 0.25, modifier: .option),
                            recorder: recorder)
        // 右键、别的侧键都不管
        XCTAssertFalse(core.handle(type: .rightMouseDown, event: try mouse(.rightMouseDown, 10, 10)))
        let side = try XCTUnwrap(CGMouseButton(rawValue: 3))
        XCTAssertFalse(core.handle(type: .otherMouseDown, event: try mouse(.otherMouseDown, 10, 10, button: side)))
        XCTAssertEqual(recorder.asked, 0)

        XCTAssertTrue(core.handle(type: .otherMouseDown, event: try mouse(.otherMouseDown, 10, 10, button: .center)))
        XCTAssertTrue(core.handle(type: .otherMouseUp, event: try mouse(.otherMouseUp, 12, 10, button: .center)))
        XCTAssertEqual(recorder.signals, [.activate(CGPoint(x: 10, y: 10)), .release(CGPoint(x: 12, y: 10))])
    }

    func testActiveGestureCancelsExactlyOnceWhenTapIsDisabledOrSettingsChange() throws {
        for reason in [CGEventType.tapDisabledByTimeout, .tapDisabledByUserInput] {
            let recorder = Recorder() // 每种原因用独立实例，旧计时回调也不能再次通知。
            let active = makeCore(recorder: recorder)
            XCTAssertTrue(active.handle(type: .rightMouseDown, event: try mouse(.rightMouseDown, 10, 20)))
            recorder.fireTimer()
            XCTAssertFalse(active.handle(type: reason, event: try mouse(.rightMouseDown, 0, 0)))
            XCTAssertFalse(active.handle(type: reason, event: try mouse(.rightMouseDown, 0, 0)))
            recorder.recovery[0].fire()
            XCTAssertEqual(recorder.signals, [.activate(CGPoint(x: 10, y: 20)), .cancel])
            XCTAssertEqual(active.disabledCount, 2)
        }
        let recorder = Recorder()
        let active = makeCore(recorder: recorder)
        XCTAssertTrue(active.handle(type: .rightMouseDown, event: try mouse(.rightMouseDown, 10, 20)))
        recorder.fireTimer()
        active.configuration = .init(mode: .disabled)
        active.stop()
        XCTAssertEqual(recorder.signals.last, .cancel)
        XCTAssertEqual(recorder.signals.count, 2)
    }

    func testNextPressCancelsOrphanedGestureBeforeStartingAnother() throws {
        for mode in [TriggerMode.longPressRight, .modifierRightClick, .middleClick] {
            let recorder = Recorder()
            let core = makeCore(.init(mode: mode), recorder: recorder)
            let middle = mode == .middleClick
            let down: CGEventType = middle ? .otherMouseDown : .rightMouseDown
            let button: CGMouseButton = middle ? .center : .right
            for point in [CGPoint(x: 10, y: 20), CGPoint(x: 30, y: 40)] {
                XCTAssertTrue(core.handle(type: down, event: try mouse(down, point.x, point.y, button: button, flags: .maskAlternate)))
                if mode == .longPressRight { recorder.fireTimer(recorder.timers.count - 1) }
            }
            XCTAssertEqual(recorder.signals, [.activate(CGPoint(x: 10, y: 20)), .cancel, .activate(CGPoint(x: 30, y: 40))])
            core.stop()
            XCTAssertEqual(recorder.signals.last, .cancel)
        }
    }

    func testDisabledPendingPressWithLostMouseUpReplaysBalancedClick() throws {
        let recorder = Recorder()
        let core = makeCore(recorder: recorder)
        XCTAssertTrue(core.handle(type: .rightMouseDown, event: try mouse(.rightMouseDown, 10, 20)))
        recorder.pressed = false
        XCTAssertFalse(core.handle(type: .tapDisabledByTimeout, event: try mouse(.rightMouseDown, 0, 0)))
        recorder.fireTimer()
        XCTAssertTrue(recorder.signals.isEmpty)
        XCTAssertEqual(recorder.posted.map { $0.type }, [.rightMouseDown, .rightMouseUp])
    }

    func testLostMouseUpBeforeActivationReplaysBalancedClick() throws {
        let recorder = Recorder()
        let pending = makeCore(recorder: recorder)
        XCTAssertTrue(pending.handle(type: .rightMouseDown, event: try mouse(.rightMouseDown, 10, 20)))
        recorder.pressed = false
        recorder.fireTimer()
        XCTAssertTrue(recorder.signals.isEmpty)
        XCTAssertEqual(recorder.posted.map { $0.type }, [.rightMouseDown, .rightMouseUp])
    }

    func testLostMouseUpAfterActivationUsesLastDragAndStopsRecovery() throws {
        for mode in [TriggerMode.longPressRight, .modifierRightClick, .middleClick] {
            let recorder = Recorder()
            let core = makeCore(.init(mode: mode), recorder: recorder)
            let middle = mode == .middleClick
            let down: CGEventType = middle ? .otherMouseDown : .rightMouseDown
            let drag: CGEventType = middle ? .otherMouseDragged : .rightMouseDragged
            let button: CGMouseButton = middle ? .center : .right
            XCTAssertTrue(core.handle(type: down, event: try mouse(down, 10, 20, button: button, flags: .maskAlternate)))
            if mode == .longPressRight { recorder.fireTimer() }
            XCTAssertTrue(core.handle(type: drag, event: try mouse(drag, 30, 40, button: button)))
            recorder.recovery[0].fire() // 仍按着：继续等，不提前松开。
            XCTAssertEqual(recorder.recovery.count, 2)
            recorder.pressed = false
            recorder.recovery[1].fire()
            recorder.recovery[1].fire()
            XCTAssertEqual(recorder.signals.last, .release(CGPoint(x: 30, y: 40)))
            XCTAssertEqual(recorder.signals.count, 3)
        }
    }

    func testDisabledModeTakesNothing() throws {
        let recorder = Recorder()
        let core = makeCore(MouseTrigger.Configuration(mode: .disabled, holdDuration: 0.25, modifier: .option),
                            recorder: recorder)
        XCTAssertFalse(core.handle(type: .rightMouseDown, event: try mouse(.rightMouseDown, 10, 10)))
        XCTAssertFalse(core.handle(type: .otherMouseDown, event: try mouse(.otherMouseDown, 10, 10, button: .center)))
        XCTAssertEqual(recorder.asked, 0)
    }
}
