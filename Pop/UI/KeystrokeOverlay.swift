import AppKit
import SwiftUI

/// 在屏幕上显示按下的组合键：一个半透明的胶囊，停一会儿淡出。
/// 录屏时钉在录的区域下边（会被一起录进去），单独打开时放在指针所在那块屏幕的下方正中，换屏幕时跟过去。
@MainActor
final class KeystrokeOverlay {
    static let shared = KeystrokeOverlay()
    /// 显示多久以后淡出
    static let holdTime: TimeInterval = 1.6
    /// 面板固定这么宽，胶囊在里面居中（字变了不用重新算大小）
    nonisolated static let width: CGFloat = 640

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var panel: NSPanel?
    private let model = KeystrokeModel()
    private var display: Keystrokes.Display?
    private var hideWork: DispatchWorkItem?
    /// 录屏时钉在录的区域下边（全局坐标）；没钉的时候跟着指针所在的屏幕
    private var pinnedArea: CGRect?

    var isActive: Bool { tap != nil }

    /// 开始显示；没有辅助功能权限时返回原因
    func start() -> String? {
        guard tap == nil else { return nil }
        let types: [CGEventType] = [.keyDown]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << CGEventMask($1.rawValue)) }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: keystrokeCallback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            return String(localized: "要先在「系统设置 → 隐私与安全性 → 辅助功能」里允许 Pop，才能显示按键")
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        runLoopSource = source
        return nil
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
        hideWork?.cancel()
        hideWork = nil
        panel?.orderOut(nil)
        panel = nil
        display = nil
        pinnedArea = nil
    }

    /// 钉在 area 下边显示（录屏时用）
    func pin(to area: CGRect) {
        pinnedArea = area
        if let panel {
            place(panel)
        }
    }

    /// 不再钉住，回到跟着指针所在的屏幕
    func unpin() {
        pinnedArea = nil
        if let panel {
            place(panel)
        }
    }

    /// 演示用：直接显示一个组合，不拦按键
    func showForDemo(_ label: String, in area: CGRect) {
        pinnedArea = area
        model.label = label
        present()
    }

    /// 现在该显示在哪块区域的下边：钉住的区域，或者指针所在屏幕去掉菜单栏、程序坞以后的部分
    private var area: CGRect {
        if let pinnedArea { return pinnedArea }
        let point = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main
        return screen?.visibleFrame ?? .zero
    }

    fileprivate func reenable() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    fileprivate func handle(keyCode: Int, flags: CGEventFlags, isRepeat: Bool) {
        // 按住不放的重复按键只让它多显示一会儿，不重复计数
        if isRepeat {
            if display != nil { scheduleHide() }
            return
        }
        guard let text = Keystrokes.text(keyCode: keyCode, flags: flags, character: Keystrokes.baseCharacter(keyCode: keyCode)) else { return }
        let next = Keystrokes.next(after: display, text: text, at: ProcessInfo.processInfo.systemUptime)
        display = next
        model.label = next.label
        present()
    }

    private func present() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        place(panel)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        scheduleHide()
    }

    /// 放在 area 下边正中，离底边留一点空
    private func place(_ panel: NSPanel) {
        guard let content = panel.contentView else { return }
        let size = CGSize(width: Self.width, height: content.fittingSize.height)
        let origin = CGPoint(x: (area.midX - size.width / 2).rounded(), y: (area.minY + 28).rounded())
        panel.setFrame(CGRect(origin: origin, size: size), display: true)
    }

    private func scheduleHide() {
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.fadeOut()
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.holdTime, execute: work)
    }

    private func fadeOut() {
        guard let panel else { return }
        display = nil
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Motion.seconds(0.25)
            panel.animator().alphaValue = 0
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 10, height: 10), styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: KeystrokeView(model: model))
        return panel
    }
}

private func keystrokeCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                               userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let overlay = Unmanaged<KeystrokeOverlay>.fromOpaque(userInfo).takeUnretainedValue()
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        // Tap 的 RunLoop source 挂在主线程上，所以这里一定在主线程
        MainActor.assumeIsolated {
            overlay.reenable()
        }
        return Unmanaged.passUnretained(event)
    }
    // Pop 自己模拟的按键（读选中内容时的 ⌘C、替换原文时的 ⌘V）不显示
    guard type == .keyDown, event.getIntegerValueField(.eventSourceUnixProcessID) != Int64(getpid()) else {
        return Unmanaged.passUnretained(event)
    }
    let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
    let flags = event.flags
    let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
    MainActor.assumeIsolated {
        overlay.handle(keyCode: keyCode, flags: flags, isRepeat: isRepeat)
    }
    return Unmanaged.passUnretained(event)
}

@MainActor
private final class KeystrokeModel: ObservableObject {
    @Published var label = ""
}

private struct KeystrokeView: View {
    @ObservedObject var model: KeystrokeModel

    var body: some View {
        Text(model.label)
            .font(.system(size: 30, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 22)
            .padding(.vertical, 10)
            .background(Capsule().fill(Color.black.opacity(0.72)))
            // 深色背景上也看得出胶囊的边
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
            .fixedSize()
            .frame(width: KeystrokeOverlay.width)
    }
}
