import AppKit
import SwiftUI
@testable import Pop

/// 提词器窗口：放在屏幕上方正中（靠近摄像头），深色半透明的底，大字的稿子慢慢往上滚，对着摄像头读。
/// 点一下窗口以后：空格暂停或继续，↑↓ 调速度，← → 往回、往前挪一点，⌘+ ⌘- 调字号，R 从头开始，Esc 关掉。
/// 不抢前台 App 的焦点；Pop 自己录屏时不会把它录进去。
@MainActor
final class Teleprompter {
    static let shared = Teleprompter()

    private var panel: TeleprompterPanel?
    private var model: TeleprompterModel?
    private var timer: Timer?
    private var monitor: Any?
    private var lastTick: TimeInterval = 0

    var isActive: Bool { panel != nil }

    /// Pop 录屏时要排除的窗口
    var windowNumber: Int? { panel?.windowNumber }

    func show(_ text: String, near point: CGPoint) {
        close()
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }) ?? NSScreen.main else { return }
        let defaults = UserDefaults.standard
        let model = TeleprompterModel(text: text,
                                      speed: defaults.object(forKey: TeleprompterModel.speedKey) as? Double ?? TeleprompterModel.defaultSpeed,
                                      fontSize: defaults.object(forKey: TeleprompterModel.fontSizeKey) as? Double ?? TeleprompterModel.defaultFontSize)
        self.model = model
        let panel = TeleprompterPanel(frame: Self.frame(in: screen.visibleFrame), model: model) { [weak self] in
            self?.closeSoon()
        }
        self.panel = panel
        panel.orderFrontRegardless()
        panel.makeKey()
        installKeys(for: panel, model: model)
        lastTick = ProcessInfo.processInfo.systemUptime
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
    }

    func close() {
        timer?.invalidate()
        timer = nil
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        if let model {
            UserDefaults.standard.set(model.speed, forKey: TeleprompterModel.speedKey)
            UserDefaults.standard.set(model.fontSize, forKey: TeleprompterModel.fontSizeKey)
        }
        panel?.orderOut(nil)
        panel = nil
        model = nil
    }

    /// 演示用：停在开头不滚动；返回窗口的位置
    func showForDemo(_ text: String, on screen: NSScreen) -> CGRect {
        close()
        let model = TeleprompterModel(text: text)
        self.model = model
        let panel = TeleprompterPanel(frame: Self.frame(in: screen.visibleFrame), model: model) {}
        panel.sharingType = .readOnly
        self.panel = panel
        panel.orderFrontRegardless()
        model.togglePause()
        return panel.frame
    }

    /// 屏幕上方正中，宽度跟着屏幕走
    nonisolated static func frame(in visible: CGRect) -> CGRect {
        let width = min(max(visible.width * 0.5, 560), 860).rounded()
        let height: CGFloat = 270
        return CGRect(x: (visible.midX - width / 2).rounded(), y: (visible.maxY - height - 8).rounded(), width: width, height: height)
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        // 卡了一下（比如电脑睡眠）也只往前滚一小段
        let elapsed = min(now - lastTick, 0.1)
        lastTick = now
        model?.advance(by: elapsed)
    }

    /// 在按键、按钮的处理过程中关掉：等这一轮事件处理完再收起窗口
    private func closeSoon() {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.close()
            }
        }
    }

    private func installKeys(for panel: NSPanel, model: TeleprompterModel) {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak panel] event in
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let self, let panel, event.window === panel else { return false }
                return self.handle(event, model: model)
            }
            return handled ? nil : event
        }
    }

    private func handle(_ event: NSEvent, model: TeleprompterModel) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .control, .option])
        if flags == .command {
            switch event.charactersIgnoringModifiers ?? "" {
            case "=", "+": model.bigger()
            case "-": model.smaller()
            default: return false
            }
            return true
        }
        guard flags.isEmpty else { return false }
        switch Int(event.keyCode) {
        case 53: closeSoon()
        case 49: model.togglePause()
        case 126: model.faster()
        case 125: model.slower()
        case 123: model.scroll(by: -model.fontSize * 2)
        case 124: model.scroll(by: model.fontSize * 2)
        case 15: model.restart()
        default: return false
        }
        return true
    }
}

/// 提词器的窗口：在普通窗口上面，可以拖动；点它不会把 Pop 带到前台
private final class TeleprompterPanel: NSPanel {
    private let model: TeleprompterModel

    init(frame: CGRect, model: TeleprompterModel, onClose: @escaping () -> Void) {
        self.model = model
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isFloatingPanel = true
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        // 共享屏幕、别的 App 录屏时尽量不让它出现
        sharingType = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        contentView = NSHostingView(rootView: TeleprompterView(model: model, onClose: onClose))
        setFrame(frame, display: false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var canBecomeKey: Bool { true }

    /// 滚轮：手动往回、往前挪
    override func scrollWheel(with event: NSEvent) {
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 10
        model.scroll(by: -delta)
    }
}

private struct TeleprompterView: View {
    @ObservedObject var model: TeleprompterModel
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                Text(model.text)
                    .font(.system(size: model.fontSize, weight: .semibold))
                    .lineSpacing(model.fontSize * 0.3)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .frame(width: max(geometry.size.width - 56, 100))
                    .fixedSize(horizontal: false, vertical: true)
                    // 第一行从上三分之一处（读的位置）开始
                    .padding(.top, geometry.size.height / 3)
                    .background(GeometryReader { text in
                        Color.clear
                            .onAppear { model.contentHeight = text.size.height }
                            .onChange(of: text.size.height) { _, height in model.contentHeight = height }
                    })
                    .offset(y: -model.offset)
                    .frame(width: geometry.size.width, alignment: .top)
                    .onAppear { model.viewportHeight = geometry.size.height }
                    .onChange(of: geometry.size.height) { _, height in model.viewportHeight = height }
            }
            .clipped()
            // 上下边缘淡出，读的那一行最清楚
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.18),
                                         .init(color: .black, location: 0.78), .init(color: .clear, location: 1)],
                                 startPoint: .top, endPoint: .bottom))
            controls
        }
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.black.opacity(0.9)))
        .environment(\.colorScheme, .dark)
    }

    private var controls: some View {
        HStack(spacing: 4) {
            iconButton(model.paused ? "play.fill" : "pause.fill", help: "暂停或继续（空格）") { model.togglePause() }
            iconButton("arrow.counterclockwise", help: "从头开始（R）") { model.restart() }
            Spacer(minLength: 8)
            iconButton("tortoise", help: "慢一点（↓）") { model.slower() }
            Text("每分钟约 \(TeleprompterModel.linesPerMinute(speed: model.speed, fontSize: model.fontSize)) 行")
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.7))
                .frame(minWidth: 96)
            iconButton("hare", help: "快一点（↑）") { model.faster() }
            Spacer(minLength: 8)
            iconButton("textformat.size.smaller", help: "字小一点（⌘-）") { model.smaller() }
            iconButton("textformat.size.larger", help: "字大一点（⌘+）") { model.bigger() }
            iconButton("xmark", help: "关闭（Esc）", action: onClose)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .foregroundStyle(.white)
    }

    private func iconButton(_ symbol: String, help: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 28, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
