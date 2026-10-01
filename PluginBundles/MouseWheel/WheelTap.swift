import CoreGraphics
import Foundation
@testable import Pop

/// 拦滚动事件的 CGEventTap，跑在自己的线程上：每一下滚动（触控板的也是）都要经过回调，
/// 放在主线程上的话 Pop 一忙全系统的滚动都会卡。设置用锁保护，主线程上改
final class WheelTap: @unchecked Sendable {
    private let lock = NSLock()
    private var current = WheelOptions()
    private var tap: CFMachPort?
    private var runLoop: CFRunLoop?
    /// tap 建着的时候留住自己：回调里拿的是这个指针
    private var retained: Unmanaged<WheelTap>?

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    /// 按什么设置改
    var options: WheelOptions {
        get { withLock { current } }
        set { withLock { current = newValue } }
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
        let mask = CGEventMask(1) << CGEventMask(CGEventType.scrollWheel.rawValue)
        let retained = Unmanaged.passRetained(self)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: wheelTapCallback, userInfo: retained.toOpaque()) else {
            retained.release()
            return false
        }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            retained.release()
            return false
        }
        let box = WheelRunLoopBox()
        let started = DispatchSemaphore(value: 0)
        let thread = Thread {
            box.runLoop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            started.signal()
            // tap 失效（stop 里 invalidate）以后没有源了，CFRunLoopRun 就返回，线程结束
            CFRunLoopRun()
        }
        thread.name = "Pop.MouseWheel"
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
        let (tap, runLoop, retained) = withLock { () -> (CFMachPort?, CFRunLoop?, Unmanaged<WheelTap>?) in
            let values = (self.tap, self.runLoop, self.retained)
            self.tap = nil
            self.runLoop = nil
            self.retained = nil
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

    /// 拦截的线程上：改滚动事件；被系统停用了（回调太慢、用户输入）就重新启用
    fileprivate func handle(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = withLock({ self.tap }) {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return
        }
        WheelAdjust.apply(options, to: event)
    }
}

/// 拦截线程的 run loop，线程里写、主线程上读（读之前等线程发信号）
private final class WheelRunLoopBox: @unchecked Sendable {
    var runLoop: CFRunLoop?
}

/// CGEventTap 的回调（C 函数），在拦截的线程上
private func wheelTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                              userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if let userInfo {
        Unmanaged<WheelTap>.fromOpaque(userInfo).takeUnretainedValue().handle(type: type, event: event)
    }
    return Unmanaged.passUnretained(event)
}
