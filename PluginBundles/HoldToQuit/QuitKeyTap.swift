import Carbon.HIToolbox
import CoreGraphics
import Foundation
@testable import Pop

/// 拦 ⌘Q 的 CGEventTap，跑在自己的线程上：别的按键在这个线程上马上放过，不经过 Pop 的主线程，Pop 忙的时候打字也不会卡；
/// 只有 ⌘Q 和吞着的那个键才到主线程上交给 HoldToQuit 决定
final class QuitKeyTap: @unchecked Sendable {
    /// 补发给 App 的 ⌘Q 带着这个记号，自己不再拦
    static let marker: Int64 = 0x506F_7051

    private let lock = NSLock()
    private var tap: CFMachPort?
    private var runLoop: CFRunLoop?
    /// tap 建着的时候留住自己：回调里拿的是这个指针
    private var retained: Unmanaged<QuitKeyTap>?
    private var trackedKey: Int64?
    private weak var model: HoldToQuit?

    init(model: HoldToQuit?) {
        self.model = model
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    /// 吞着的那个键（按 ⌘Q 时的 Q 键）；主线程上设，拦截的线程上看
    var trackedKeyCode: Int64? {
        get { withLock { trackedKey } }
        set { withLock { trackedKey = newValue } }
    }

    var isRunning: Bool {
        withLock { tap != nil }
    }

    /// 建着、没有失效、没有被系统停掉（睡眠醒来、权限收回以后可能这样）
    var isHealthy: Bool {
        withLock { tap.map { CFMachPortIsValid($0) && CGEvent.tapIsEnabled(tap: $0) } ?? false }
    }

    /// 建 tap、开线程；没有辅助功能权限时建不了，返回 false
    func start() -> Bool {
        if isRunning {
            return true
        }
        let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << CGEventMask($1.rawValue)) }
        let retained = Unmanaged.passRetained(self)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: quitKeyTapCallback, userInfo: retained.toOpaque()) else {
            retained.release()
            return false
        }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            retained.release()
            return false
        }
        let box = RunLoopBox()
        let started = DispatchSemaphore(value: 0)
        let thread = Thread {
            box.runLoop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            started.signal()
            // tap 失效（stop 里 invalidate）以后没有源了，CFRunLoopRun 就返回，线程结束
            CFRunLoopRun()
        }
        thread.name = "Pop.HoldToQuit"
        thread.qualityOfService = .userInteractive
        thread.start()
        started.wait()
        CGEvent.tapEnable(tap: tap, enable: true)
        withLock {
            self.tap = tap
            self.runLoop = box.runLoop
            self.retained = retained
        }
        return true
    }

    func stop() {
        let (tap, runLoop, retained) = withLock { () -> (CFMachPort?, CFRunLoop?, Unmanaged<QuitKeyTap>?) in
            let values = (self.tap, self.runLoop, self.retained)
            self.tap = nil
            self.runLoop = nil
            self.retained = nil
            trackedKey = nil
            return values
        }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoop {
            CFRunLoopStop(runLoop)
        }
        retained?.release()
    }

    /// 拦截的线程上：返回 true 是吞掉这个事件
    fileprivate func shouldSwallow(type: CGEventType, event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // 被系统停用了（回调太慢、用户输入）：重新启用
            if let tap = withLock({ self.tap }) {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return false
        case .keyDown, .keyUp:
            guard event.getIntegerValueField(.eventSourceUserData) != Self.marker else { return false }
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            let isDown = type == .keyDown
            let isQuit = isDown && Self.isQuitShortcut(event)
            // 别的按键：马上放过
            guard isQuit || keyCode == trackedKeyCode, let model else { return false }
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            return DispatchQueue.main.sync {
                MainActor.assumeIsolated {
                    model.decide(isDown: isDown, keyCode: keyCode, isRepeat: isRepeat, isQuitShortcut: isQuit)
                }
            }
        case .flagsChanged:
            if !event.flags.contains(.maskCommand), trackedKeyCode != nil, let model {
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { model.releaseCommand() }
                }
            }
            return false
        default:
            return false
        }
    }

    /// 只按着 ⌘ 的 Q（⇧⌘Q 是退出登录、⌃⌘Q 是锁屏，不管）。按打出来的字符认，换了键盘布局也对；
    /// 拿不到字符，或者是俄文这类非拉丁键盘时（App 还是按美式键盘的位置认 ⌘Q），按键的位置认
    static func isQuitShortcut(_ event: CGEvent) -> Bool {
        let flags = event.flags
        guard flags.contains(.maskCommand), flags.isDisjoint(with: [.maskShift, .maskControl, .maskAlternate]) else { return false }
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(maxStringLength: characters.count, actualStringLength: &length, unicodeString: &characters)
        let text = String(utf16CodeUnits: characters, count: min(length, characters.count)).lowercased()
        guard !text.isEmpty, text.unicodeScalars.allSatisfy(\.isASCII) else {
            return keyCode == Int64(kVK_ANSI_Q)
        }
        return text == "q"
    }
}

/// 拦截线程的 run loop，线程里写、主线程上读（读之前等线程发信号）
private final class RunLoopBox: @unchecked Sendable {
    var runLoop: CFRunLoop?
}

/// CGEventTap 的回调（C 函数），在拦截的线程上
private func quitKeyTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                                userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<QuitKeyTap>.fromOpaque(userInfo).takeUnretainedValue()
    return tap.shouldSwallow(type: type, event: event) ? nil : Unmanaged.passUnretained(event)
}
