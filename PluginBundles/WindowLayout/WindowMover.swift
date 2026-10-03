import AppKit
import ApplicationServices
@testable import Pop

/// 用辅助功能接口移动、缩放其他 App 的窗口（Pop 已经有辅助功能权限）。
/// 辅助功能接口的坐标以主屏左上角为原点、y 向下；这里对外都用 AppKit 坐标。
/// 辅助功能调用是跨进程的同步调用，对方 App 卡住时每次都要等到超时，所以放在后台做，Pop 不跟着卡
enum WindowMover {
    /// 各块屏幕的位置（AppKit 坐标），在主线程上读好交给后台
    struct Screens {
        var frames: [CGRect]
        var visibleFrames: [CGRect]

        @MainActor static var current: Screens {
            let screens = NSScreen.screens
            return Screens(frames: screens.map(\.frame), visibleFrames: screens.map(\.visibleFrame))
        }

        /// 主屏幕的高度：两种坐标互换时用
        var primaryHeight: CGFloat { frames.first?.height ?? 0 }
    }

    /// 把 pid 这个 App 当前的窗口放到 layout 指定的位置；失败时返回给用户看的原因。
    @MainActor static func apply(_ layout: WindowLayout, pid: pid_t) async -> String? {
        let screens = Screens.current
        return await runInBackground {
            move(layout, pid: pid, screens: screens)
        }
    }

    /// 在后台线程上挪
    static func move(_ layout: WindowLayout, pid: pid_t, screens: Screens) -> String? {
        let app = AXUIElementCreateApplication(pid)
        guard let window = focusedWindow(of: app) else { return String(localized: "没有找到可以移动的窗口") }
        guard let quartzFrame = frame(of: window) else { return String(localized: "读取不到窗口的位置") }
        let current = convert(quartzFrame, primaryHeight: screens.primaryHeight)
        guard !screens.frames.isEmpty else { return String(localized: "找不到显示器") }
        let index = WindowLayout.screenIndex(for: current, among: screens.frames) ?? 0
        let visible = screens.visibleFrames[index]
        let target: CGRect
        if layout == .nextDisplay {
            guard screens.frames.count > 1 else { return String(localized: "只接了一个显示器") }
            target = WindowLayout.moved(current, from: visible, to: screens.visibleFrames[(index + 1) % screens.frames.count])
        } else {
            target = layout.frame(for: current, in: visible)
        }
        let quartzTarget = convert(target, primaryHeight: screens.primaryHeight)
        // 先挪位置再改大小，最后再挪一次：有的 App 改大小时以左上角为准，或者限制了最小尺寸
        guard setPosition(quartzTarget.origin, of: window) else { return String(localized: "这个窗口不能移动") }
        setSize(quartzTarget.size, of: window)
        setPosition(quartzTarget.origin, of: window)
        return nil
    }

    /// AppKit 坐标和辅助功能坐标互换（y 轴翻转，两个方向是同一个公式）
    private static func convert(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    private static func focusedWindow(of app: AXUIElement) -> AXUIElement? {
        for attribute in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(app, attribute as CFString, &value) == .success, let value,
               CFGetTypeID(value) == AXUIElementGetTypeID() {
                return (value as! AXUIElement)
            }
        }
        var windows: CFTypeRef?
        if AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windows) == .success,
           let list = windows as? [AXUIElement], let first = list.first {
            return first
        }
        return nil
    }

    private static func frame(of window: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(), CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: position, size: size)
    }

    @discardableResult
    private static func setPosition(_ point: CGPoint, of window: AXUIElement) -> Bool {
        var point = point
        guard let value = AXValueCreate(.cgPoint, &point) else { return false }
        return AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value) == .success
    }

    @discardableResult
    private static func setSize(_ size: CGSize, of window: AXUIElement) -> Bool {
        var size = size
        guard let value = AXValueCreate(.cgSize, &size) else { return false }
        return AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value) == .success
    }
}
