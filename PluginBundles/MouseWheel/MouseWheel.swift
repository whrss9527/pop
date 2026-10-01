import AppKit
import CoreGraphics
@testable import Pop

/// 鼠标滚轮：用 CGEventTap 拦下滚动事件，按设置把一格一格的鼠标滚轮反过来、加快；触控板、妙控鼠标照旧。
/// 设置都记住，Pop 启动时（插件包装载时）接着生效；要辅助功能权限（Pop 唤起圆盘本来就要）
@MainActor
final class MouseWheel: ObservableObject {
    static let shared = MouseWheel()

    static let reverseKey = "pop.mouseWheel.reverse"
    static let horizontalKey = "pop.mouseWheel.reverseHorizontal"
    static let speedKey = "pop.mouseWheel.speed"
    static let defaultsKeys = [reverseKey, horizontalKey, speedKey]
    /// 滚动速度：系统的、两倍、三倍
    static let speeds = [1, 2, 3]

    @Published private(set) var options: WheelOptions
    /// 正在拦滚动事件
    @Published private(set) var isRunning = false
    /// 要改，但还没有辅助功能权限
    @Published private(set) var needsPermission = false

    private let defaults: UserDefaults
    /// 测试、演示时不拦真的事件
    private let isLive: Bool
    private let isTrusted: () -> Bool
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    /// 没有权限时每隔几秒看一次，给了就开始
    private var permissionTimer: Timer?

    init(defaults: UserDefaults = .standard, isLive: Bool = true, isTrusted: @escaping () -> Bool = { Permissions.isAccessibilityTrusted }) {
        self.defaults = defaults
        self.isLive = isLive
        self.isTrusted = isTrusted
        options = Self.savedOptions(defaults)
    }

    private static func savedOptions(_ defaults: UserDefaults) -> WheelOptions {
        let speed = defaults.object(forKey: speedKey) as? Int ?? 1
        return WheelOptions(reverseVertical: defaults.bool(forKey: reverseKey), reverseHorizontal: defaults.bool(forKey: horizontalKey),
                            speed: speeds.contains(speed) ? speed : 1)
    }

    // MARK: - 设置

    func setReverse(_ on: Bool) {
        options.reverseVertical = on
        defaults.set(on, forKey: Self.reverseKey)
        update()
    }

    func setReverseHorizontal(_ on: Bool) {
        options.reverseHorizontal = on
        defaults.set(on, forKey: Self.horizontalKey)
        update()
    }

    func setSpeed(_ speed: Int) {
        guard Self.speeds.contains(speed) else { return }
        options.speed = speed
        defaults.set(speed, forKey: Self.speedKey)
        update()
    }

    /// 插件包装载时：按存着的设置来（卸载时可能一起删掉了），要改的话开始拦
    func startIfNeeded() {
        options = Self.savedOptions(defaults)
        update()
    }

    /// 卸载插件包的时候
    func shutDown() {
        stopTap()
        permissionTimer?.invalidate()
        permissionTimer = nil
        needsPermission = false
    }

    /// 按现在的设置开、关拦截
    private func update() {
        guard options.isActive else {
            shutDown()
            return
        }
        guard isTrusted() else {
            stopTap()
            needsPermission = true
            watchPermission()
            return
        }
        needsPermission = false
        permissionTimer?.invalidate()
        permissionTimer = nil
        startTap()
    }

    private func watchPermission() {
        guard isLive, permissionTimer == nil else { return }
        let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isTrusted() else { return }
                self.update()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        permissionTimer = timer
    }

    // MARK: - 拦滚动事件

    private func startTap() {
        guard isLive else {
            isRunning = true
            return
        }
        guard tap == nil else { return }
        let mask = CGEventMask(1) << CGEventMask(CGEventType.scrollWheel.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: mouseWheelCallback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            needsPermission = true
            watchPermission()
            return
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        isRunning = true
    }

    private func stopTap() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        tap = nil
        source = nil
        isRunning = false
    }

    /// 回调里调：改滚动事件；被系统停用了（回调太慢、用户输入）就重新启用
    fileprivate func handle(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return
        }
        WheelAdjust.apply(options, to: event)
    }

    // MARK: - 卡片上的字

    /// 「正在把鼠标滚轮反过来，速度两倍」「没开」
    var statusText: String {
        if needsPermission {
            return String(localized: "要先在「系统设置 → 隐私与安全性 → 辅助功能」里允许 Pop，才能调整鼠标滚轮")
        }
        guard options.isActive else {
            return String(localized: "没开：鼠标滚轮按系统设置滚动")
        }
        var parts: [String] = []
        if options.reverseVertical && options.reverseHorizontal {
            parts.append(String(localized: "上下、左右都反过来"))
        } else if options.reverseVertical {
            parts.append(String(localized: "上下反过来"))
        } else if options.reverseHorizontal {
            parts.append(String(localized: "左右反过来"))
        }
        if options.speed > 1 {
            parts.append(Self.speedTitle(options.speed))
        }
        return String(localized: "正在调整鼠标滚轮：\(parts.joined(separator: String(localized: "，")))")
    }

    /// 系统现在的滚动方向，说明打开以后会怎样
    var directionHint: String {
        WheelAdjust.naturalScrolling(defaults)
            ? String(localized: "系统开着「自然滚动」：滚轮往下滚，页面往上翻（和 Windows 相反）。反过来以后，鼠标滚轮和 Windows 上一样，触控板还是自然滚动")
            : String(localized: "系统关着「自然滚动」：滚轮往下滚，页面往下翻。反过来以后，鼠标滚轮往下滚时页面往上翻，和触控板相反")
    }

    nonisolated static func speedTitle(_ speed: Int) -> String {
        speed <= 1 ? String(localized: "系统的速度") : String(localized: "\(speed) 倍速")
    }

    // MARK: - 演示

    /// 演示用：上下反过来、两倍速，不拦真的事件
    static func demo() -> MouseWheel {
        let suite = "PopMouseWheelDemo"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        let wheel = MouseWheel(defaults: defaults, isLive: false, isTrusted: { true })
        wheel.setReverse(true)
        wheel.setSpeed(2)
        return wheel
    }
}

/// CGEventTap 的回调（C 函数）。Tap 的 RunLoop source 挂在主线程上，所以这里一定在主线程
private func mouseWheelCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                                userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let wheel = Unmanaged<MouseWheel>.fromOpaque(userInfo).takeUnretainedValue()
    MainActor.assumeIsolated {
        wheel.handle(type: type, event: event)
    }
    return Unmanaged.passUnretained(event)
}
