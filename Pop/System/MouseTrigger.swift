import AppKit
import CoreGraphics
import os

@MainActor
protocol MouseTriggerDelegate: AnyObject {
    /// 即将开始一次唤起；返回 false 时这次按压原样交给系统（比如当前 App 在排除名单里）。
    func mouseTriggerShouldBegin() -> Bool
    /// 唤起成功。坐标是 Quartz 全局坐标（主屏左上角为原点）。
    func mouseTriggerDidActivate(at location: CGPoint)
    /// 唤起后按住拖动
    func mouseTriggerDidDrag(to location: CGPoint)
    /// 唤起后松开
    func mouseTriggerDidRelease(at location: CGPoint)
    /// 拦截停用、配置变化或停止：取消本次手势，不执行指向的功能。
    func mouseTriggerDidCancel()
}

/// 用 CGEventTap 拦截鼠标事件实现「长按右键 / 修饰键+右键 / 中键」唤起。
///
/// 长按模式的关键：macOS 的右键菜单在按下瞬间就会弹出，所以先把 rightMouseDown 扣住，
/// - 在判定时长内松开：按原顺序补发「按下 + 松开」，系统右键菜单照常出现；
/// - 按住拖动超过几个像素：补发按下并放行拖动，不影响游戏、3D 软件的右键拖拽；
/// - 计时到：这次按压归我们，之后的拖动和松开也一并吞掉。
/// 补发的事件带有标记，回到这里时直接放行。
///
/// Tap 跑在自己的线程上（EventTapThread）：系统里每一次右键、中键都要等回调返回，放在主线程上的话，
/// Pop 一忙全系统的右键都跟着卡。判定在拦截的线程上做（MouseTriggerCore）；按下时要不要接手问主线程上的 delegate，
/// 最多等 0.1 秒，等不到就当普通的右键放过。唤起、拖动、松开按顺序交给主线程，不等它。
@MainActor
final class MouseTrigger {
    typealias Configuration = MouseTriggerConfiguration

    weak var delegate: MouseTriggerDelegate?

    var configuration = Configuration() {
        didSet {
            if configuration != oldValue {
                core?.configuration = configuration
            }
        }
    }

    private(set) var isRunning = false

    private var tap: EventTapThread?
    private var core: MouseTriggerCore?

    /// 需要辅助功能权限，没有权限时返回 false。
    @discardableResult
    func start() -> Bool {
        if isRunning { return true }
        // 这两个闭包在拦截的线程上调用
        let core = MouseTriggerCore(
            configuration: configuration,
            shouldBegin: { @Sendable [weak self] in
                EventTapThread.askMain(fallback: false) { [weak self] in
                    self?.delegate?.mouseTriggerShouldBegin() == true
                }
            },
            deliver: { @Sendable [weak self] signal in
                DispatchQueue.main.async { [weak self] in
                    MainActor.assumeIsolated {
                        self?.deliver(signal)
                    }
                }
            })
        let tap = EventTapThread(name: "Pop.MouseTrigger") { type, event in
            core.handle(type: type, event: event)
        }
        guard tap.start(events: MouseTriggerCore.eventTypes) else {
            return false
        }
        self.tap = tap
        self.core = core
        isRunning = true
        return true
    }

    func stop() {
        // 扣住的按下事件还给系统，之后的事件都放过
        core?.stop()
        tap?.stop()
        tap = nil
        core = nil
        isRunning = false
    }

    private func deliver(_ signal: MouseTriggerSignal) {
        switch signal {
        case .activate(let location): delegate?.mouseTriggerDidActivate(at: location)
        case .drag(let location): delegate?.mouseTriggerDidDrag(to: location)
        case .release(let location): delegate?.mouseTriggerDidRelease(at: location)
        case .cancel: delegate?.mouseTriggerDidCancel()
        }
    }
}

/// 怎么唤起：拦截的线程上也要读，所以不放在 MouseTrigger（主线程）里面
struct MouseTriggerConfiguration: Equatable {
    var mode: TriggerMode = .longPressRight
    var holdDuration: TimeInterval = 0.25
    var modifier: TriggerModifier = .option
}

/// 拦截的线程交给主线程的事
enum MouseTriggerSignal: Equatable {
    case activate(CGPoint)
    case drag(CGPoint)
    case release(CGPoint)
    case cancel
}

/// 长按、修饰键+右键、中键的判定，在拦截的线程上跑（长按计时到了在计时的队列上）。
/// 状态在锁里改；交给主线程的唤起、拖动、松开也在锁里排队，顺序和状态的变化一致。
/// 问 delegate 要不要接手（可能要等主线程）时不拿着锁
final class MouseTriggerCore: @unchecked Sendable {
    /// 补发事件的标记（写在 eventSourceUserData 里）
    static let replayMarker: Int64 = 0x504F_5021
    static let eventTypes: [CGEventType] = [.rightMouseDown, .rightMouseUp, .rightMouseDragged,
                                            .otherMouseDown, .otherMouseUp, .otherMouseDragged]
    private static let log = Logger(subsystem: "io.github.whrss9527.pop", category: "gesture")
    private static let dragTolerance: CGFloat = 6
    private static let timerQueue = DispatchQueue(label: "io.github.whrss9527.pop.mouse-trigger", qos: .userInteractive)

    private enum State {
        case idle
        /// 长按判定中：按下事件被扣住了。id 认计时，cancel 取消计时
        case pending(down: CGEvent, id: Int, cancel: () -> Void)
        /// 已唤起：本次按压归我们
        case active
        /// 已判定为普通按压，剩下的事件都放行
        case passthrough
    }

    private let lock = NSLock()
    private var state: State = .idle
    private var current: MouseTriggerConfiguration
    private var nextTimerID = 0
    private var recoveryID = 0
    private var recoveryCancel: (() -> Void)?
    private var lastLocation = CGPoint.zero
    private(set) var disabledCount = 0
    /// 停下来以后不再接手，也不再交事给主线程（拦截的线程上可能还有一个事件在判定）
    private var isStopped = false

    /// 要不要接手这次按压（可能要等主线程，等不到当作不要）
    private let shouldBegin: () -> Bool
    /// 交给主线程的事，在锁里调用，不能等
    private let deliver: (MouseTriggerSignal) -> Void
    /// 补发事件
    private let post: ([CGEvent]) -> Void
    /// 长按计时：过多久调用 fire，返回取消计时的闭包
    private let startTimer: (TimeInterval, @escaping () -> Void) -> () -> Void
    private let startRecoveryTimer: (TimeInterval, @escaping () -> Void) -> () -> Void
    private let isPressed: (CGMouseButton) -> Bool

    init(configuration: MouseTriggerConfiguration,
         shouldBegin: @escaping () -> Bool,
         deliver: @escaping (MouseTriggerSignal) -> Void,
         post: @escaping ([CGEvent]) -> Void = MouseTriggerCore.replay,
         startTimer: @escaping (TimeInterval, @escaping () -> Void) -> () -> Void = MouseTriggerCore.dispatchTimer(after:fire:),
         startRecoveryTimer: @escaping (TimeInterval, @escaping () -> Void) -> () -> Void = MouseTriggerCore.dispatchTimer(after:fire:),
         isPressed: @escaping (CGMouseButton) -> Bool = { CGEventSource.buttonState(.combinedSessionState, button: $0) }) {
        current = configuration
        self.shouldBegin = shouldBegin
        self.deliver = deliver
        self.post = post
        self.startTimer = startTimer
        self.startRecoveryTimer = startRecoveryTimer
        self.isPressed = isPressed
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    /// 改了设置：扣着的按下事件还给系统，重新开始
    var configuration: MouseTriggerConfiguration {
        get { withLock { current } }
        set {
            withLock {
                current = newValue
                resetLocked(replayPending: true)
            }
        }
    }

    /// 扣着的按下事件还给系统，重新开始
    func reset() {
        withLock { resetLocked(replayPending: true) }
    }

    /// 停下来：扣着的按下事件还给系统，之后的事件都放过
    func stop() {
        withLock {
            resetLocked(replayPending: true)
            isStopped = true
        }
    }

    /// 拦截的线程上：返回 true 表示吞掉这个事件。
    func handle(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // EventTapThread 已重新启用拦截；取消已唤起的手势，不能静默留下按住状态。
            let count = withLock { () -> Int in
                disabledCount += 1
                resetLocked(replayPending: true)
                return disabledCount
            }
            Self.log.notice("鼠标拦截被停用，累计 \(count, privacy: .public) 次，原因 \(String(describing: type), privacy: .public)")
            return false
        }
        let (configuration, isStopped) = withLock { (current, self.isStopped) }
        if isStopped || event.getIntegerValueField(.eventSourceUserData) == Self.replayMarker {
            return false
        }
        switch configuration.mode {
        case .longPressRight: return handleLongPress(type: type, event: event, holdDuration: configuration.holdDuration)
        case .modifierRightClick: return handleModifierClick(type: type, event: event, modifier: configuration.modifier)
        case .middleClick: return handleMiddleClick(type: type, event: event)
        case .disabled: return false
        }
    }

    private func handleLongPress(type: CGEventType, event: CGEvent, holdDuration: TimeInterval) -> Bool {
        if type == .rightMouseDown {
            let pressedAt = ProcessInfo.processInfo.systemUptime
            reset()
            guard shouldBegin(), let down = event.copy() else {
                withLock { state = .passthrough }
                return false
            }
            let location = event.location
            // 问 delegate 用掉的时间也算在长按里
            let remaining = max(0, holdDuration - (ProcessInfo.processInfo.systemUptime - pressedAt))
            return withLock {
                guard !isStopped else { return false }
                nextTimerID += 1
                let id = nextTimerID
                let cancel = startTimer(remaining) { [weak self] in
                    self?.holdTimerFired(id: id, at: location)
                }
                state = .pending(down: down, id: id, cancel: cancel)
                return true
            }
        }
        return withLock {
            switch (type, state) {
            case (.rightMouseDragged, .pending(let down, _, let cancel)):
                let dx = event.location.x - down.location.x
                let dy = event.location.y - down.location.y
                if (dx * dx + dy * dy).squareRoot() > Self.dragTolerance {
                    cancel()
                    state = .passthrough
                    post([down, event])
                }
                return true

            case (.rightMouseDragged, .active):
                lastLocation = event.location
                deliver(.drag(event.location))
                return true

            case (.rightMouseUp, .pending(let down, _, let cancel)):
                cancel()
                state = .idle
                post([down, event])
                return true

            case (.rightMouseUp, .active):
                resetRecoveryLocked()
                state = .idle
                deliver(.release(event.location))
                return true

            case (.rightMouseUp, .passthrough):
                state = .idle
                return false

            default:
                return false
            }
        }
    }

    private func handleModifierClick(type: CGEventType, event: CGEvent, modifier: TriggerModifier) -> Bool {
        if type == .rightMouseDown {
            reset()
            // 没按着修饰键的右键不问主线程，马上放过
            guard event.flags.contains(modifier.eventFlag), shouldBegin() else { return false }
            return activate(at: event.location)
        }
        return withLock {
            switch (type, state) {
            case (.rightMouseDragged, .active):
                lastLocation = event.location
                deliver(.drag(event.location))
                return true
            case (.rightMouseUp, .active):
                resetRecoveryLocked()
                state = .idle
                deliver(.release(event.location))
                return true
            default:
                return false
            }
        }
    }

    private func handleMiddleClick(type: CGEventType, event: CGEvent) -> Bool {
        guard event.getIntegerValueField(.mouseEventButtonNumber) == 2 else { return false }
        if type == .otherMouseDown {
            reset()
            guard shouldBegin() else { return false }
            return activate(at: event.location)
        }
        return withLock {
            switch (type, state) {
            case (.otherMouseDragged, .active):
                lastLocation = event.location
                deliver(.drag(event.location))
                return true
            case (.otherMouseUp, .active):
                resetRecoveryLocked()
                state = .idle
                deliver(.release(event.location))
                return true
            default:
                return false
            }
        }
    }

    /// 修饰键+右键、中键按下：马上唤起，这次按压归我们
    private func activate(at location: CGPoint) -> Bool {
        withLock {
            guard !isStopped else { return false }
            state = .active
            lastLocation = location
            startRecoveryLocked()
            deliver(.activate(location))
            return true
        }
    }

    /// 计时的队列上
    private func holdTimerFired(id: Int, at location: CGPoint) {
        withLock {
            // 计时到之前已经松开、拖开、重新开始或者停下来了
            guard !isStopped, case .pending(let down, let pendingID, _) = state, pendingID == id else { return }
            // 松开事件丢失时不误唤起，也不能只补按下让目标 App 一直按住。
            guard isPressed(.right) else {
                state = .idle
                if let up = down.copy() { up.type = .rightMouseUp; post([down, up]) }
                else { post([down]) }
                return
            }
            // 扣住的按下事件不再补发：目标 App 完全感知不到这次按压，选区也不会被右键改变。
            state = .active
            lastLocation = location
            startRecoveryLocked()
            deliver(.activate(location))
        }
    }

    /// 拿着锁调用
    private func resetLocked(replayPending: Bool) {
        if case .pending(let down, _, let cancel) = state {
            cancel()
            if replayPending {
                if !isPressed(.right), let up = down.copy() {
                    up.type = .rightMouseUp
                    post([down, up])
                } else {
                    post([down])
                }
            }
        }
        if case .active = state { deliver(.cancel) }
        resetRecoveryLocked()
        state = .idle
    }

    private func resetRecoveryLocked() {
        recoveryID += 1
        recoveryCancel?()
        recoveryCancel = nil
    }

    /// 只在本次手势已唤起且按住时检查，不增加常驻轮询。
    private func startRecoveryLocked() {
        let id = recoveryID
        recoveryCancel = startRecoveryTimer(0.5) { [weak self] in
            guard let self else { return }
            self.withLock {
                guard !self.isStopped, self.recoveryID == id, case .active = self.state else { return }
                let button: CGMouseButton = self.current.mode == .middleClick ? .center : .right
                if self.isPressed(button) {
                    self.startRecoveryLocked()
                } else {
                    self.resetRecoveryLocked()
                    self.state = .idle
                    self.deliver(.release(self.lastLocation))
                }
            }
        }
    }

    /// 补发扣住的事件：带上标记，回到这里时直接放行
    static func replay(_ events: [CGEvent]) {
        for event in events {
            guard let copy = event.copy() else { continue }
            copy.setIntegerValueField(.eventSourceUserData, value: replayMarker)
            copy.post(tap: .cgSessionEventTap)
        }
    }

    /// 长按计时：到点在 timerQueue 上调用 fire；返回的闭包取消计时，在哪个线程上调用都行
    static func dispatchTimer(after seconds: TimeInterval, fire: @escaping () -> Void) -> () -> Void {
        let timer = DispatchSource.makeTimerSource(queue: timerQueue)
        timer.schedule(deadline: .now() + seconds)
        timer.setEventHandler(handler: fire)
        timer.resume()
        return { timer.cancel() }
    }
}

extension TriggerModifier {
    var eventFlag: CGEventFlags {
        switch self {
        case .option: return .maskAlternate
        case .control: return .maskControl
        case .command: return .maskCommand
        case .shift: return .maskShift
        }
    }
}
