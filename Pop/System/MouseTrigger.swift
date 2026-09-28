import AppKit
import CoreGraphics

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
}

/// 用 CGEventTap 拦截鼠标事件实现「长按右键 / 修饰键+右键 / 中键」唤起。
///
/// 长按模式的关键：macOS 的右键菜单在按下瞬间就会弹出，所以先把 rightMouseDown 扣住，
/// - 在判定时长内松开：按原顺序补发「按下 + 松开」，系统右键菜单照常出现；
/// - 按住拖动超过几个像素：补发按下并放行拖动，不影响游戏、3D 软件的右键拖拽；
/// - 计时到：这次按压归我们，之后的拖动和松开也一并吞掉。
/// 补发的事件带有标记，回到这里时直接放行。
///
/// Tap 挂在主线程 RunLoop 上，回调里只做状态判断，耗时的事情（取选中内容等）都交给 delegate 异步处理。
@MainActor
final class MouseTrigger {
    struct Configuration: Equatable {
        var mode: TriggerMode = .longPressRight
        var holdDuration: TimeInterval = 0.25
        var modifier: TriggerModifier = .option
    }

    weak var delegate: MouseTriggerDelegate?

    var configuration = Configuration() {
        didSet {
            if configuration != oldValue {
                reset(replayPending: true)
            }
        }
    }

    private(set) var isRunning = false

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private enum State {
        case idle
        /// 长按判定中：按下事件被扣住了
        case pending(down: CGEvent, timer: Timer)
        /// 已唤起：本次按压归我们
        case active
        /// 已判定为普通按压，剩下的事件都放行
        case passthrough
    }

    private var state: State = .idle

    /// 补发事件的标记（写在 eventSourceUserData 里）
    static let replayMarker: Int64 = 0x504F_5021
    private let dragTolerance: CGFloat = 6

    /// 需要辅助功能权限，没有权限时返回 false。
    @discardableResult
    func start() -> Bool {
        if isRunning { return true }
        let types: [CGEventType] = [.rightMouseDown, .rightMouseUp, .rightMouseDragged,
                                    .otherMouseDown, .otherMouseUp, .otherMouseDragged]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << CGEventMask($1.rawValue)) }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                          place: .headInsertEventTap,
                                          options: .defaultTap,
                                          eventsOfInterest: mask,
                                          callback: mouseTriggerCallback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            return false
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        runLoopSource = source
        isRunning = true
        return true
    }

    func stop() {
        reset(replayPending: true)
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
        isRunning = false
    }

    /// 返回 true 表示吞掉这个事件。
    fileprivate func handle(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // 回调太慢或系统原因被停用了，重新启用；扣住的按下事件还给系统。
            reset(replayPending: true)
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
        if event.getIntegerValueField(.eventSourceUserData) == Self.replayMarker {
            return false
        }
        switch configuration.mode {
        case .longPressRight: return handleLongPress(type: type, event: event)
        case .modifierRightClick: return handleModifierClick(type: type, event: event)
        case .middleClick: return handleMiddleClick(type: type, event: event)
        case .disabled: return false
        }
    }

    private func handleLongPress(type: CGEventType, event: CGEvent) -> Bool {
        switch (type, state) {
        case (.rightMouseDown, _):
            reset(replayPending: true)
            guard delegate?.mouseTriggerShouldBegin() == true, let down = event.copy() else {
                state = .passthrough
                return false
            }
            let location = event.location
            let timer = Timer(timeInterval: configuration.holdDuration, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.holdTimerFired(at: location)
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            state = .pending(down: down, timer: timer)
            return true

        case (.rightMouseDragged, .pending(let down, let timer)):
            let dx = event.location.x - down.location.x
            let dy = event.location.y - down.location.y
            if (dx * dx + dy * dy).squareRoot() > dragTolerance {
                timer.invalidate()
                state = .passthrough
                replay([down, event])
            }
            return true

        case (.rightMouseDragged, .active):
            delegate?.mouseTriggerDidDrag(to: event.location)
            return true

        case (.rightMouseUp, .pending(let down, let timer)):
            timer.invalidate()
            state = .idle
            replay([down, event])
            return true

        case (.rightMouseUp, .active):
            state = .idle
            delegate?.mouseTriggerDidRelease(at: event.location)
            return true

        case (.rightMouseUp, .passthrough):
            state = .idle
            return false

        default:
            return false
        }
    }

    private func handleModifierClick(type: CGEventType, event: CGEvent) -> Bool {
        switch (type, state) {
        case (.rightMouseDown, _):
            state = .idle
            guard event.flags.contains(configuration.modifier.eventFlag),
                  delegate?.mouseTriggerShouldBegin() == true else { return false }
            state = .active
            delegate?.mouseTriggerDidActivate(at: event.location)
            return true
        case (.rightMouseDragged, .active):
            delegate?.mouseTriggerDidDrag(to: event.location)
            return true
        case (.rightMouseUp, .active):
            state = .idle
            delegate?.mouseTriggerDidRelease(at: event.location)
            return true
        default:
            return false
        }
    }

    private func handleMiddleClick(type: CGEventType, event: CGEvent) -> Bool {
        guard event.getIntegerValueField(.mouseEventButtonNumber) == 2 else { return false }
        switch (type, state) {
        case (.otherMouseDown, _):
            state = .idle
            guard delegate?.mouseTriggerShouldBegin() == true else { return false }
            state = .active
            delegate?.mouseTriggerDidActivate(at: event.location)
            return true
        case (.otherMouseDragged, .active):
            delegate?.mouseTriggerDidDrag(to: event.location)
            return true
        case (.otherMouseUp, .active):
            state = .idle
            delegate?.mouseTriggerDidRelease(at: event.location)
            return true
        default:
            return false
        }
    }

    private func holdTimerFired(at location: CGPoint) {
        guard case .pending = state else { return }
        // 扣住的按下事件不再补发：目标 App 完全感知不到这次按压，选区也不会被右键改变。
        state = .active
        delegate?.mouseTriggerDidActivate(at: location)
    }

    private func reset(replayPending: Bool) {
        if case .pending(let down, let timer) = state {
            timer.invalidate()
            if replayPending {
                replay([down])
            }
        }
        state = .idle
    }

    private func replay(_ events: [CGEvent]) {
        for event in events {
            guard let copy = event.copy() else { continue }
            copy.setIntegerValueField(.eventSourceUserData, value: Self.replayMarker)
            copy.post(tap: .cgSessionEventTap)
        }
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

private func mouseTriggerCallback(proxy: CGEventTapProxy,
                                  type: CGEventType,
                                  event: CGEvent,
                                  userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let trigger = Unmanaged<MouseTrigger>.fromOpaque(userInfo).takeUnretainedValue()
    // Tap 的 RunLoop source 挂在主线程上，所以这里一定在主线程。
    let swallow = MainActor.assumeIsolated {
        trigger.handle(type: type, event: event)
    }
    return swallow ? nil : Unmanaged.passUnretained(event)
}
