import AppKit
import SwiftUI

/// 圆盘、结果卡片和提示共用的浮动面板：无边框、透明、不激活 App。
/// 不激活很关键：原来的 App 一直在前台，选区不会丢，模拟的 ⌘C 也不会发到我们自己身上。
final class OverlayPanel: NSPanel {
    /// 返回 true 表示已处理
    var keyHandler: ((NSEvent) -> Bool)?
    var cancelHandler: (() -> Void)?

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: true)
        isFloatingPanel = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        if keyHandler?(event) == true { return }
        super.keyDown(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        if let cancelHandler {
            cancelHandler()
        } else {
            super.cancelOperation(sender)
        }
    }
}

@MainActor
final class OverlayController {
    enum Mode: Equatable {
        case hidden
        case ring
        case card
        case toast
    }

    private(set) var mode: Mode = .hidden
    var isVisible: Bool { mode != .hidden }

    /// 用户主动关闭（Esc、点击外面、切到别的 App）
    var onDismiss: (() -> Void)?
    /// 圆盘模式下的按键（数字选择、回车确认等），返回 true 表示已处理
    var onRingKey: ((NSEvent) -> Bool)?
    /// 圆盘模式下点击了面板
    var onRingClick: (() -> Void)?

    /// 圆盘实际显示的圆心（靠近屏幕边缘时会和唤起点不同）
    private(set) var ringCenter: CGPoint?

    private let panel = OverlayPanel()
    private var cardAnchor: CGPoint = .zero
    private var globalClickMonitor: Any?
    private var localClickMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var toastTimer: Timer?

    /// 给圆盘阴影留的边距
    static let ringPadding: CGFloat = 16

    init() {
        panel.keyHandler = { [weak self] event in
            MainActor.assumeIsolated {
                self?.handleKey(event) ?? false
            }
        }
        panel.cancelHandler = { [weak self] in
            MainActor.assumeIsolated {
                self?.dismissByUser()
            }
        }
        resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification,
                                                                object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.mode == .ring || self.mode == .card else { return }
                self.dismissByUser()
            }
        }
    }

    // MARK: - 显示

    func showRing(_ model: RingViewModel, center: CGPoint) {
        let size = model.geometry.diameter + Self.ringPadding * 2
        let frame = ScreenGeometry.ringFrame(center: center, diameter: size, within: Self.visibleFrame(containing: center))
        present(RingMenuView(model: model), frame: frame, mode: .ring)
        ringCenter = CGPoint(x: frame.midX, y: frame.midY)
    }

    func showCard<Content: View>(_ content: Content, anchor: CGPoint) {
        cardAnchor = anchor
        let hosted = content
            .fixedSize()
            .onGeometryChange(for: CGSize.self) { proxy in
                proxy.size
            } action: { [weak self] size in
                self?.resizeCard(to: size)
            }
        let initial = CGSize(width: 404, height: 160)
        let frame = ScreenGeometry.cardFrame(anchor: anchor, size: initial, within: Self.visibleFrame(containing: anchor))
        present(hosted, frame: frame, mode: .card)
    }

    func showToast(_ message: String, anchor: CGPoint) {
        let size = CGSize(width: max(120, CGFloat(message.count) * 14 + 48), height: 44)
        let frame = ScreenGeometry.cardFrame(anchor: anchor, size: size, within: Self.visibleFrame(containing: anchor))
        present(ToastView(message: message), frame: frame, mode: .toast)
        toastTimer = Timer.scheduledTimer(withTimeInterval: 1.1, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.mode == .toast else { return }
                self.hide()
            }
        }
    }

    func hide() {
        toastTimer?.invalidate()
        toastTimer = nil
        removeMonitors()
        mode = .hidden
        ringCenter = nil
        panel.orderOut(nil)
        panel.contentView = nil
    }

    // MARK: - 内部

    private func present<Content: View>(_ content: Content, frame: CGRect, mode: Mode) {
        toastTimer?.invalidate()
        toastTimer = nil
        ringCenter = nil
        let hosting = NSHostingView(rootView: content)
        hosting.sizingOptions = []
        panel.contentView = hosting
        panel.setFrame(frame, display: true)
        self.mode = mode
        if mode == .toast {
            removeMonitors()
            panel.ignoresMouseEvents = true
            panel.orderFrontRegardless()
        } else {
            panel.ignoresMouseEvents = false
            installMonitors()
            panel.makeKeyAndOrderFront(nil)
        }
    }

    private func resizeCard(to size: CGSize) {
        guard mode == .card, size.width > 0, size.height > 0 else { return }
        let frame = ScreenGeometry.cardFrame(anchor: cardAnchor, size: size, within: Self.visibleFrame(containing: cardAnchor))
        guard frame != panel.frame else { return }
        // 在 SwiftUI 布局回调里直接改窗口大小会重入布局，放到下一轮 RunLoop。
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.mode == .card else { return }
                self.panel.setFrame(frame, display: true)
            }
        }
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        if event.keyCode == 53 { // Esc
            dismissByUser()
            return true
        }
        if mode == .ring {
            return onRingKey?(event) ?? false
        }
        return false
    }

    private func dismissByUser() {
        guard mode != .hidden else { return }
        hide()
        onDismiss?()
    }

    private func installMonitors() {
        guard globalClickMonitor == nil else { return }
        // 点到其他 App 上：关闭
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.dismissByUser()
            }
        }
        // 点到面板上：圆盘模式由我们自己处理，不依赖 SwiftUI 手势在非激活窗口里的表现
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let self, self.mode == .ring, event.window === self.panel else { return false }
                self.onRingClick?()
                return true
            }
            return handled ? nil : event
        }
    }

    private func removeMonitors() {
        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
        }
        if let localClickMonitor {
            NSEvent.removeMonitor(localClickMonitor)
        }
        globalClickMonitor = nil
        localClickMonitor = nil
    }

    static func visibleFrame(containing point: CGPoint) -> CGRect {
        let screen = NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens.first
        return screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
    }

    static var primaryScreenHeight: CGFloat {
        NSScreen.screens.first?.frame.height ?? 0
    }
}

struct ToastView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(Capsule().fill(.regularMaterial))
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
