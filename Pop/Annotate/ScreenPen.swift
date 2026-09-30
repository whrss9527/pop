import AppKit
import Combine
import SwiftUI

/// 屏幕画笔：演示、录教程时直接在屏幕上画。盖住指针所在的那块屏幕，上方一条工具栏；
/// 可以让鼠标穿过去操作下面的窗口（画好的留着），也可以让笔迹几秒后自动消失。Esc 或者再用一次结束。
/// 画布是普通的窗口，录屏时会一起录进去；工具栏不录。
@MainActor
final class ScreenPen {
    static let shared = ScreenPen()

    private let model = ScreenPenModel()
    private var window: ScreenPenWindow?
    private var toolbar: ScreenPenToolbarPanel?
    private var fadeTimer: Timer?
    private var passThroughObservation: AnyCancellable?
    /// 开始前在前台的 App，结束后还给它
    private var previousApp: NSRunningApplication?

    var isActive: Bool { window != nil }

    /// 在 point 所在的屏幕上开始画
    func start(near point: CGPoint) {
        guard !isActive,
              let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }) ?? NSScreen.main else { return }
        model.reset()
        previousApp = NSWorkspace.shared.frontmostApplication
        present(on: screen)
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func stop() {
        fadeTimer?.invalidate()
        fadeTimer = nil
        passThroughObservation = nil
        window?.orderOut(nil)
        window = nil
        toolbar?.orderOut(nil)
        toolbar = nil
        model.reset()
        if let previousApp, previousApp.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApp.activate()
        }
        previousApp = nil
    }

    /// 演示用：摆出画布、工具栏和几笔示例，不抢焦点；返回工具栏的位置
    func showForDemo(on screen: NSScreen, strokes: [(tool: ScreenPenTool, color: AnnotationColor, points: [CGPoint])]) -> CGRect? {
        stop()
        present(on: screen)
        for stroke in strokes {
            model.draw(stroke.tool, color: stroke.color, through: stroke.points, at: ProcessInfo.processInfo.systemUptime)
        }
        model.tool = .arrow
        toolbar?.sharingType = .readOnly
        return toolbar?.frame
    }

    private func present(on screen: NSScreen) {
        let window = ScreenPenWindow(screen: screen, model: model) { [weak self] event in
            self?.handleKey(event) ?? false
        }
        self.window = window
        let toolbar = ScreenPenToolbarPanel(model: model, screen: screen, actions: ScreenPenToolbarActions(
            choose: { [weak self] tool in self?.choose(tool) },
            togglePassThrough: { [weak self] in self?.togglePassThrough() },
            toggleFades: { [weak self] in
                guard let self else { return }
                self.model.setFades(!self.model.fades, now: ProcessInfo.processInfo.systemUptime)
            },
            undo: { [weak self] in self?.model.undo() },
            clear: { [weak self] in self?.model.clear() },
            done: { [weak self] in self?.stopSoon() }))
        self.toolbar = toolbar
        window.orderFrontRegardless()
        toolbar.orderFrontRegardless()
        passThroughObservation = model.$passThrough.sink { [weak window] through in
            window?.ignoresMouseEvents = through
        }
        fadeTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
    }

    /// 在按键、按钮的处理过程中结束：等这一轮事件处理完再收起窗口
    private func stopSoon() {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.stop()
            }
        }
    }

    /// 自动消失时一直重画，淡没了的去掉
    private func tick() {
        guard model.fades, !model.strokes.isEmpty else { return }
        model.removeFaded(now: ProcessInfo.processInfo.systemUptime)
        window?.canvas.needsDisplay = true
    }

    /// 选了一支笔：回到画画，画布接住鼠标和键盘
    private func choose(_ tool: ScreenPenTool) {
        model.tool = tool
        if model.passThrough {
            model.passThrough = false
            NSApp.activate()
            window?.makeKeyAndOrderFront(nil)
        }
    }

    /// 鼠标穿过画布去操作下面的窗口；再点一次回来接着画
    private func togglePassThrough() {
        if model.passThrough {
            choose(model.tool)
        } else {
            model.passThrough = true
            previousApp?.activate()
        }
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch Int(event.keyCode) {
        case 53:
            stopSoon()
            return true
        case 51, 117:
            model.clear()
            return true
        default:
            break
        }
        guard let key = event.charactersIgnoringModifiers?.lowercased().first else { return false }
        if flags == .command, key == "z" {
            model.undo()
            return true
        }
        guard flags.subtracting([.shift, .capsLock, .numericPad, .function]).isEmpty else { return false }
        if let tool = ScreenPenTool.allCases.first(where: { $0.key == key }) {
            choose(tool)
            return true
        }
        if let number = key.wholeNumberValue, (1...ScreenPenModel.colors.count).contains(number) {
            model.color = ScreenPenModel.colors[number - 1]
            return true
        }
        return false
    }
}

/// 盖住一整块屏幕的透明窗口，放在菜单栏、程序坞上面，录屏的边框和面板下面
private final class ScreenPenWindow: NSWindow {
    let canvas: ScreenPenCanvas

    init(screen: NSScreen, model: ScreenPenModel, onKey: @escaping (NSEvent) -> Bool) {
        canvas = ScreenPenCanvas(frame: CGRect(origin: .zero, size: screen.frame.size), model: model, onKey: onKey)
        super.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue - 1)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        // 透明的地方也要接住鼠标（不设的话点在没画的地方会点到下面的窗口）
        ignoresMouseEvents = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        contentView = canvas
        setFrame(screen.frame, display: false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var canBecomeKey: Bool { true }
}

/// 画布：拖动鼠标画，按住 ⇧ 画直线、正方形、正圆和 45° 的箭头
private final class ScreenPenCanvas: NSView {
    private let model: ScreenPenModel
    private let onKey: (NSEvent) -> Bool
    private var observation: AnyCancellable?

    init(frame: CGRect, model: ScreenPenModel, onKey: @escaping (NSEvent) -> Bool) {
        self.model = model
        self.onKey = onKey
        super.init(frame: frame)
        // objectWillChange 在改之前发出；这里只是标记要重画，真正画的时候已经改好了
        observation = model.objectWillChange.sink { [weak self] _ in
            self?.needsDisplay = true
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 左上角为原点，和笔迹的坐标一致
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.activeAlways, .inVisibleRect, .cursorUpdate], owner: self, userInfo: nil))
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.crosshair.set()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func mouseDown(with event: NSEvent) {
        model.begin(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseDragged(with event: NSEvent) {
        model.drag(to: convert(event.locationInWindow, from: nil), constrained: event.modifierFlags.contains(.shift))
    }

    override func mouseUp(with event: NSEvent) {
        model.end(at: ProcessInfo.processInfo.systemUptime)
    }

    override func keyDown(with event: NSEvent) {
        if !onKey(event) {
            super.keyDown(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let now = ProcessInfo.processInfo.systemUptime
        for stroke in model.visibleStrokes {
            let alpha = model.fades ? ScreenPenModel.fade(finishedAt: stroke.finishedAt, now: now) : 1
            guard alpha > 0, let path = stroke.annotation.strokePath else { continue }
            context.saveGState()
            // 浅色、深色的背景上都看得清：除了荧光笔，都带一圈淡淡的阴影
            if stroke.tool != .highlighter {
                context.setShadow(offset: CGSize(width: 0, height: -1), blur: 4, color: NSColor.black.withAlphaComponent(0.35 * alpha).cgColor)
            }
            context.addPath(path.cgPath)
            context.setStrokeColor(stroke.annotation.color.nsColor.withAlphaComponent(stroke.tool.opacity * alpha).cgColor)
            context.setLineWidth(stroke.annotation.lineWidth)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.strokePath()
            context.restoreGState()
        }
    }
}

struct ScreenPenToolbarActions {
    var choose: (ScreenPenTool) -> Void
    var togglePassThrough: () -> Void
    var toggleFades: () -> Void
    var undo: () -> Void
    var clear: () -> Void
    var done: () -> Void
}

/// 屏幕上方正中的工具栏；可以拖开
private final class ScreenPenToolbarPanel: NSPanel {
    init(model: ScreenPenModel, screen: NSScreen, actions: ScreenPenToolbarActions) {
        let content = NSHostingView(rootView: ScreenPenToolbar(model: model, actions: actions))
        let size = content.fittingSize
        let bounds = screen.visibleFrame
        let origin = CGPoint(x: (bounds.midX - size.width / 2).rounded(), y: (bounds.maxY - size.height - 10).rounded())
        super.init(contentRect: CGRect(origin: origin, size: size), styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        level = .statusBar
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isFloatingPanel = true
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        sharingType = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        contentView = content
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var canBecomeKey: Bool { false }
}

private struct ScreenPenToolbar: View {
    @ObservedObject var model: ScreenPenModel
    let actions: ScreenPenToolbarActions

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 2) {
                ForEach(ScreenPenTool.allCases) { tool in
                    iconButton(tool.symbol, selected: !model.passThrough && model.tool == tool) { actions.choose(tool) }
                        .help("\(tool.title)（\(String(tool.key).uppercased())）")
                }
            }
            HStack(spacing: 5) {
                ForEach(Array(ScreenPenModel.colors.enumerated()), id: \.element) { index, color in
                    Button {
                        model.color = color
                    } label: {
                        Circle()
                            .fill(color.color)
                            .overlay(Circle().strokeBorder(Color.white.opacity(model.color == color ? 0.95 : 0.25),
                                                           lineWidth: model.color == color ? 2 : 1))
                            .frame(width: 16, height: 16)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("颜色（\(index + 1)）")
                }
            }
            Divider()
                .frame(height: 18)
                .overlay(Color.white.opacity(0.25))
            HStack(spacing: 2) {
                iconButton("cursorarrow", selected: model.passThrough, action: actions.togglePassThrough)
                    .help("鼠标穿过去操作下面的窗口，画好的留着；再点一次接着画")
                iconButton("timer", selected: model.fades, action: actions.toggleFades)
                    .help("笔迹几秒后自动消失")
                iconButton("arrow.uturn.backward", selected: false, action: actions.undo)
                    .help("撤销（⌘Z）")
                    .disabled(model.strokes.isEmpty)
                iconButton("trash", selected: false, action: actions.clear)
                    .help("全部擦掉（⌫）")
                    .disabled(model.strokes.isEmpty)
            }
            Button("完成", action: actions.done)
                .controlSize(.small)
                .help("结束屏幕画笔（Esc）")
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.black.opacity(0.8)))
        .environment(\.colorScheme, .dark)
        .fixedSize()
    }

    private func iconButton(_ symbol: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 28, height: 24)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.white.opacity(selected ? 0.24 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
