import AppKit
import SwiftUI
@testable import Pop

/// 清洁键盘：一段时间里拦下所有按键（包括亮度、音量这些功能键），可以放心擦键盘；
/// 屏幕上盖一层提示和倒计时，用鼠标点「结束」或者时间到了就恢复。
@MainActor
final class KeyboardCleaner {
    static let shared = KeyboardCleaner()
    /// 锁多久
    static let duration: TimeInterval = 60

    /// 拦按键的线程：一律吞掉，不经过主线程。放在主线程上的话 Pop 一忙回调就慢，
    /// 系统嫌慢会停用拦截，按键就漏到前台的 App 里去了
    private var tap: EventTapThread?
    private var windows: [NSWindow] = []
    private var timer: Timer?
    private var endsAt: Date?
    private let model = KeyboardCleanerModel()
    /// 开始前在前台的 App，结束后还给它
    private var previousApp: NSRunningApplication?

    var isActive: Bool { tap != nil }

    /// 要拦下的事件：按下、松开、修饰键，还有亮度、音量、播放这些功能键（NX_SYSDEFINED）
    nonisolated static var eventMask: CGEventMask {
        let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged]
        let keys = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << CGEventMask($1.rawValue)) }
        return keys | (CGEventMask(1) << 14)
    }

    /// 还剩几秒：「0:45」
    nonisolated static func remainingText(_ seconds: TimeInterval) -> String {
        let whole = max(0, Int(seconds.rounded(.up)))
        return "\(whole / 60):" + String(format: "%02d", whole % 60)
    }

    /// 开始；没有辅助功能权限时返回原因
    func start() -> String? {
        guard !isActive else { return nil }
        // 按键一律拦下
        let tap = EventTapThread(name: "Pop.KeyboardCleaner") { _, _ in true }
        guard tap.start(mask: Self.eventMask) else {
            return String(localized: "要先在「系统设置 → 隐私与安全性 → 辅助功能」里允许 Pop，才能锁住键盘")
        }
        self.tap = tap
        previousApp = NSWorkspace.shared.frontmostApplication
        let endsAt = Date().addingTimeInterval(Self.duration)
        self.endsAt = endsAt
        model.remaining = Self.remainingText(Self.duration)
        showWindows()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
        return nil
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        tap?.stop()
        tap = nil
        endsAt = nil
        for window in windows {
            window.orderOut(nil)
        }
        windows = []
        if let previousApp, previousApp.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApp.activate()
        }
        previousApp = nil
    }

    private func tick() {
        guard let endsAt else { return }
        let remaining = endsAt.timeIntervalSinceNow
        if remaining <= 0 {
            stop()
        } else {
            model.remaining = Self.remainingText(remaining)
        }
    }

    /// 每块屏幕都盖一层，主屏幕上显示提示；Pop 到前台，第一下点「结束清洁」就管用
    private func showWindows() {
        let main = NSScreen.main
        NSApp.activate()
        for screen in NSScreen.screens {
            let showsMessage = screen == main || main == nil
            let window = KeyboardCleanerWindow(screen: screen, model: model, showsMessage: showsMessage) { [weak self] in
                self?.stop()
            }
            if showsMessage {
                window.makeKeyAndOrderFront(nil)
            } else {
                window.orderFrontRegardless()
            }
            windows.append(window)
        }
    }
}

@MainActor
private final class KeyboardCleanerModel: ObservableObject {
    @Published var remaining = ""
}

private struct KeyboardCleanerView: View {
    @ObservedObject var model: KeyboardCleanerModel
    let showsMessage: Bool
    let onStop: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
            if showsMessage {
                VStack(spacing: 14) {
                    Image(systemName: "keyboard")
                        .font(.system(size: 54, weight: .light))
                    Text("键盘已经锁住，可以放心擦了")
                        .font(.system(size: 26, weight: .semibold))
                    Text("按键、亮度和音量键都不起作用；\(model.remaining) 后自动恢复")
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.75))
                        .monospacedDigit()
                    Button(action: onStop) {
                        Text("结束清洁")
                            .font(.system(size: 15, weight: .semibold))
                            .padding(.horizontal, 22)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(Color.white.opacity(0.18)))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 6)
                }
                .foregroundStyle(.white)
            }
        }
        .ignoresSafeArea()
    }
}

/// 盖住一块屏幕的窗口：鼠标还能用，点「结束清洁」就恢复
private final class KeyboardCleanerWindow: NSWindow {
    init(screen: NSScreen, model: KeyboardCleanerModel, showsMessage: Bool, onStop: @escaping () -> Void) {
        super.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        contentView = NSHostingView(rootView: KeyboardCleanerView(model: model, showsMessage: showsMessage, onStop: onStop))
        setFrame(screen.frame, display: false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var canBecomeKey: Bool { true }
}
