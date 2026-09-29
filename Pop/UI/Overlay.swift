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

/// 一次浮窗展示的进场、退场状态，视图根据它做动画。
@MainActor
final class OverlayPresentation: ObservableObject {
    enum Phase: Equatable {
        /// 刚放进窗口，先按「进场前」的样子画第一帧
        case entering
        case shown
        /// 正在退场（已经挪到退场窗口里）
        case leaving
    }

    @Published fileprivate(set) var phase: Phase = .entering
}

/// 卡片和提示的进场、退场：从指针所在的那个角弹出来，收起时淡出。
struct OverlayStage<Content: View>: View {
    enum Style {
        /// 卡片从 anchor 这个角（指针所在的一侧）长出来
        case card(UnitPoint)
        case toast
    }

    @ObservedObject var presentation: OverlayPresentation
    let style: Style
    let content: Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(presentation: OverlayPresentation, style: Style, @ViewBuilder content: () -> Content) {
        self.presentation = presentation
        self.style = style
        self.content = content()
    }

    var body: some View {
        let phase = presentation.phase
        content
            .scaleEffect(scale(phase), anchor: anchor)
            .opacity(phase == .shown ? 1 : 0)
            .animation(phase == .shown ? openAnimation : Motion.exit, value: phase)
    }

    private var anchor: UnitPoint {
        switch style {
        case .card(let anchor): return anchor
        case .toast: return .center
        }
    }

    private var openAnimation: Animation {
        switch style {
        case .card: return Motion.cardOpen
        case .toast: return Motion.toastOpen
        }
    }

    private func scale(_ phase: OverlayPresentation.Phase) -> CGFloat {
        guard !reduceMotion else { return 1 }
        switch (phase, style) {
        case (.shown, _): return 1
        case (.entering, .card): return 0.9
        case (.entering, .toast): return 0.8
        case (.leaving, .card): return 0.96
        case (.leaving, .toast): return 0.9
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
    /// 当前内容的进场、退场状态
    private var presentation = OverlayPresentation()
    /// 正在播放退场动画的窗口：旧内容挪到这里淡出，主窗口马上可以显示下一个内容
    private var leavingPanels: [Int: OverlayPanel] = [:]
    private var leavingCounter = 0
    private var cardAnchor: CGPoint = .zero
    /// 卡片模式下的按键处理（列表的上下选择、回车等），返回 true 表示已处理
    private var cardKeyHandler: ((NSEvent) -> Bool)?
    private var globalClickMonitor: Any?
    private var localClickMonitor: Any?
    private var keyMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var toastTimer: Timer?

    /// 给圆盘阴影和弹开时的回弹留的边距
    static let ringPadding: CGFloat = 22

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
        let presentation = OverlayPresentation()
        present(RingMenuView(model: model, presentation: presentation), frame: frame, mode: .ring, presentation: presentation)
        ringCenter = CGPoint(x: frame.midX, y: frame.midY)
    }

    /// keyHandler 在输入框之前拿到按键，列表类的卡片（剪贴板历史、全部功能）用它处理上下选择和回车。
    func showCard<Content: View>(_ content: Content, anchor: CGPoint, keyHandler: ((NSEvent) -> Bool)? = nil) {
        cardAnchor = anchor
        let initial = CGSize(width: 404, height: 160)
        let frame = ScreenGeometry.cardFrame(anchor: anchor, size: initial, within: Self.visibleFrame(containing: anchor),
                                             gap: Self.cardGap)
        let presentation = OverlayPresentation()
        let hosted = OverlayStage(presentation: presentation, style: .card(Self.growAnchor(frame: frame, from: anchor))) {
            content
        }
        .fixedSize()
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { [weak self, weak presentation] size in
            guard let presentation else { return }
            self?.resizeCard(to: size, for: presentation)
        }
        present(hosted, frame: frame, mode: .card, presentation: presentation)
        cardKeyHandler = keyHandler
    }

    /// 卡片四周留了阴影的边距，窗口离指针近一点，看起来卡片和指针的距离才合适
    private static let cardGap: CGFloat = 6

    /// 卡片从离指针最近的那个角长出来
    static func growAnchor(frame: CGRect, from anchor: CGPoint) -> UnitPoint {
        let fromLeft = frame.midX >= anchor.x
        // AppKit 坐标 y 向上：卡片在指针下面时，从卡片的上边长出来
        let fromTop = frame.midY <= anchor.y
        switch (fromLeft, fromTop) {
        case (true, true): return .topLeading
        case (false, true): return .topTrailing
        case (true, false): return .bottomLeading
        case (false, false): return .bottomTrailing
        }
    }

    /// 屏幕上的点（AppKit 坐标）是否落在浮窗上
    func contains(_ point: CGPoint) -> Bool {
        mode != .hidden && panel.frame.contains(point)
    }

    func showToast(_ message: String, anchor: CGPoint) {
        // 四周留出阴影的位置
        let size = CGSize(width: max(140, CGFloat(message.count) * 14 + 76), height: 72)
        let frame = ScreenGeometry.cardFrame(anchor: anchor, size: size, within: Self.visibleFrame(containing: anchor),
                                             gap: 0)
        let presentation = OverlayPresentation()
        present(OverlayStage(presentation: presentation, style: .toast) { ToastView(message: message) },
                frame: frame, mode: .toast, presentation: presentation)
        toastTimer = Timer.scheduledTimer(withTimeInterval: Motion.toastDuration, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.mode == .toast else { return }
                self.hide()
            }
        }
    }

    /// 收起浮窗。animated 为 false 时立刻消失（截图、取色前不能让浮窗留在屏幕上）。
    func hide(animated: Bool = true) {
        toastTimer?.invalidate()
        toastTimer = nil
        cardKeyHandler = nil
        removeMonitors()
        retireContent(animated: animated)
        mode = .hidden
        ringCenter = nil
        panel.orderOut(nil)
        panel.contentView = nil
    }

    // MARK: - 内部

    private func present<Content: View>(_ content: Content, frame: CGRect, mode: Mode, presentation: OverlayPresentation) {
        toastTimer?.invalidate()
        toastTimer = nil
        ringCenter = nil
        cardKeyHandler = nil
        // 正在显示的内容挪去退场，和新内容的进场同时进行
        retireContent(animated: true)
        let hosting = NSHostingView(rootView: content)
        hosting.sizingOptions = []
        panel.contentView = hosting
        panel.setFrame(frame, display: true)
        self.mode = mode
        self.presentation = presentation
        // 先按「进场前」的样子画出第一帧，下一轮再切到显示状态，视图才有动画可做
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                if presentation.phase == .entering {
                    presentation.phase = .shown
                }
            }
        }
        if mode == .toast {
            removeMonitors()
            panel.ignoresMouseEvents = true
            // 提示不需要键盘：先收起面板交还键盘焦点，再不抢焦点地显示出来。
            if panel.isKeyWindow {
                panel.orderOut(nil)
            }
            panel.orderFrontRegardless()
        } else {
            panel.ignoresMouseEvents = false
            installMonitors()
            panel.makeKeyAndOrderFront(nil)
        }
    }

    /// 把正在显示的内容挪到一个只用来播放退场动画的窗口里：主窗口马上空出来，
    /// 新内容的进场和旧内容的退场可以同时进行。退场窗口不接收鼠标，也不会成为键盘焦点。
    private func retireContent(animated: Bool) {
        guard mode != .hidden, let view = panel.contentView else { return }
        let frame = panel.frame
        let leaving = presentation
        panel.contentView = nil
        guard animated else { return }
        let ghost = OverlayPanel()
        ghost.ignoresMouseEvents = true
        ghost.setFrame(frame, display: false)
        ghost.contentView = view
        ghost.orderFrontRegardless()
        leavingCounter += 1
        let token = leavingCounter
        leavingPanels[token] = ghost
        leaving.phase = .leaving
        DispatchQueue.main.asyncAfter(deadline: .now() + Motion.exitDuration + 0.05) { [weak self] in
            MainActor.assumeIsolated {
                self?.finishLeaving(token)
            }
        }
    }

    private func finishLeaving(_ token: Int) {
        guard let ghost = leavingPanels.removeValue(forKey: token) else { return }
        ghost.orderOut(nil)
        ghost.contentView = nil
    }

    /// 卡片内容的大小变了（比如翻译结果出来了）就跟着改窗口大小。已经退场的卡片不管。
    private func resizeCard(to size: CGSize, for owner: OverlayPresentation) {
        guard mode == .card, owner === presentation, size.width > 0, size.height > 0 else { return }
        let frame = ScreenGeometry.cardFrame(anchor: cardAnchor, size: size, within: Self.visibleFrame(containing: cardAnchor),
                                             gap: Self.cardGap)
        guard frame != panel.frame else { return }
        // 在 SwiftUI 布局回调里直接改窗口大小会重入布局，放到下一轮 RunLoop。
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.mode == .card, owner === self.presentation else { return }
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
        // 卡片里的输入框会先拿到按键：Esc 会被当成「补全」，上下键会移动光标，所以在这里先拦下来
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let self, self.mode == .card, event.window === self.panel else { return false }
                if event.keyCode == 53 { // Esc
                    self.dismissByUser()
                    return true
                }
                return self.cardKeyHandler?(event) ?? false
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
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        globalClickMonitor = nil
        localClickMonitor = nil
        keyMonitor = nil
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
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .glassSurface(Capsule())
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
