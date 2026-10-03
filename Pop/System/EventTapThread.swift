import CoreGraphics
import Foundation

/// 跑在自己线程上的 CGEventTap：系统要等拦截的回调返回才把按键、鼠标事件交给 App，
/// 回调放在主线程上的话，Pop 的主线程一忙，整个系统的打字、点击都会跟着慢。
/// 这里的回调在自己的线程上马上返回；要更新界面就自己 DispatchQueue.main.async 过去，
/// 非要主线程拿主意时用 askMain，最多等 mainTimeout。
final class EventTapThread: @unchecked Sendable {
    /// 拦截的线程上调用：返回 true 是吞掉这个事件。系统停用 tap（回调太慢、用户输入）时先在这里重新打开，
    /// 再把通知交给 handler（返回值不管），扣着事件的可以趁这时候还回去
    typealias Handler = @Sendable (CGEventType, CGEvent) -> Bool

    /// 拦截的线程等主线程最多等这么久
    static let mainTimeout: TimeInterval = 0.1

    private let name: String
    private let handler: Handler
    private let lock = NSLock()
    private var tap: CFMachPort?
    private var runLoop: CFRunLoop?

    init(name: String, handler: @escaping Handler) {
        self.name = name
        self.handler = handler
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    var isRunning: Bool {
        withLock { tap != nil }
    }

    /// 建 tap、开线程；没有辅助功能权限时建不了，返回 false
    func start(events: [CGEventType], place: CGEventTapPlacement = .headInsertEventTap,
               options: CGEventTapOptions = .defaultTap) -> Bool {
        let mask = events.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << CGEventMask($1.rawValue)) }
        return start(mask: mask, place: place, options: options)
    }

    /// 按事件掩码建（CGEventType 里没有的事件，比如亮度、音量这些功能键的 NX_SYSDEFINED）
    func start(mask: CGEventMask, place: CGEventTapPlacement = .headInsertEventTap,
               options: CGEventTapOptions = .defaultTap) -> Bool {
        if isRunning {
            return true
        }
        // tap 建着的时候留住自己（回调里拿的是这个指针），线程结束时放开
        let retained = Unmanaged.passRetained(self)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: place, options: options,
                                          eventsOfInterest: mask, callback: eventTapThreadCallback, userInfo: retained.toOpaque()) else {
            retained.release()
            return false
        }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            retained.release()
            return false
        }
        let box = TapRunLoopBox()
        let started = DispatchSemaphore(value: 0)
        let thread = Thread {
            box.runLoop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            started.signal()
            // tap 失效（stop 里 invalidate）以后没有源了，CFRunLoopRun 就返回，线程结束。
            // 回调都在这个线程上，到这里一定没有正在跑的回调，这时才放开自己
            CFRunLoopRun()
            retained.release()
        }
        thread.name = name
        thread.qualityOfService = .userInteractive
        thread.start()
        started.wait()
        CGEvent.tapEnable(tap: tap, enable: true)
        withLock {
            self.tap = tap
            self.runLoop = box.runLoop
        }
        return true
    }

    func stop() {
        let (tap, runLoop) = withLock { () -> (CFMachPort?, CFRunLoop?) in
            let values = (self.tap, self.runLoop)
            self.tap = nil
            self.runLoop = nil
            return values
        }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoop {
            CFRunLoopStop(runLoop)
        }
    }

    /// 拦截的线程上
    fileprivate func handle(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = withLock({ self.tap }) {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            _ = handler(type, event)
            return false
        }
        return handler(type, event)
    }

    /// 拦截的线程上要主线程拿主意时用：最多等 timeout，主线程正忙、等不到就按 fallback 处理，
    /// 不让整个系统的键盘、鼠标跟着卡。主线程空下来以后照样会执行 decide，只是结果没人要了
    static func askMain(timeout: TimeInterval = EventTapThread.mainTimeout, fallback: Bool,
                        _ decide: @escaping @Sendable @MainActor () -> Bool) -> Bool {
        let answer = MainAnswer()
        DispatchQueue.main.async {
            answer.set(MainActor.assumeIsolated(decide))
        }
        return answer.wait(timeout: timeout) ?? fallback
    }
}

/// 拦截线程的 run loop，线程里写、调用 start 的线程上读（读之前等线程发信号）
private final class TapRunLoopBox: @unchecked Sendable {
    var runLoop: CFRunLoop?
}

/// 主线程交回来的决定：拦截的线程等它，等不到就算了
private final class MainAnswer: @unchecked Sendable {
    private let lock = NSLock()
    private let ready = DispatchSemaphore(value: 0)
    private var value: Bool?

    func set(_ value: Bool) {
        lock.lock()
        self.value = value
        lock.unlock()
        ready.signal()
    }

    func wait(timeout: TimeInterval) -> Bool? {
        guard ready.wait(timeout: .now() + timeout) == .success else { return nil }
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

/// CGEventTap 的回调（C 函数），在拦截的线程上
private func eventTapThreadCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                                    userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<EventTapThread>.fromOpaque(userInfo).takeUnretainedValue()
    return tap.handle(type: type, event: event) ? nil : Unmanaged.passUnretained(event)
}
