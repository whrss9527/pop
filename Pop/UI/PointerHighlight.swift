import AppKit

/// 突出显示指针：指针周围一圈半透明的黄色光圈，按下鼠标时泛起一圈波纹，让人一眼看到指针在哪。
/// 光圈是一个跟着指针走、不接鼠标的小窗口，录屏时会一起录进去。
@MainActor
final class PointerHighlight {
    static let shared = PointerHighlight()
    /// 光圈的直径（点）
    nonisolated static let diameter: CGFloat = 60
    /// 波纹最大放到光圈的几倍
    nonisolated static let rippleScale: CGFloat = 1.7

    private var panel: NSPanel?
    private var halo: PointerHaloView?
    private var monitors: [Any] = []

    var isActive: Bool { panel != nil }

    /// 窗口要够放下放大后的波纹
    nonisolated static var panelSize: CGFloat { (diameter * rippleScale).rounded(.up) + 4 }

    /// 光圈中心对准指针时，窗口的位置
    nonisolated static func frame(around point: CGPoint) -> CGRect {
        let size = panelSize
        return CGRect(x: (point.x - size / 2).rounded(), y: (point.y - size / 2).rounded(), width: size, height: size)
    }

    func start() {
        guard panel == nil else { return }
        let halo = PointerHaloView(frame: CGRect(x: 0, y: 0, width: Self.panelSize, height: Self.panelSize))
        let panel = makePanel(content: halo)
        self.panel = panel
        self.halo = halo
        panel.setFrame(Self.frame(around: NSEvent.mouseLocation), display: false)
        panel.orderFrontRegardless()
        let moves: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        let presses: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        // 别的 App 里的移动和点击
        if let global = NSEvent.addGlobalMonitorForEvents(matching: moves.union(presses), handler: { [weak self] event in
            let pressed = presses.contains(NSEvent.EventTypeMask(rawValue: 1 << event.type.rawValue))
            MainActor.assumeIsolated {
                self?.follow(pressed: pressed)
            }
        }) {
            monitors.append(global)
        }
        // Pop 自己的窗口里的
        if let local = NSEvent.addLocalMonitorForEvents(matching: moves.union(presses), handler: { [weak self] event in
            let pressed = presses.contains(NSEvent.EventTypeMask(rawValue: 1 << event.type.rawValue))
            MainActor.assumeIsolated {
                self?.follow(pressed: pressed)
            }
            return event
        }) {
            monitors.append(local)
        }
    }

    func stop() {
        for monitor in monitors {
            NSEvent.removeMonitor(monitor)
        }
        monitors = []
        panel?.orderOut(nil)
        panel = nil
        halo = nil
    }

    /// 演示用：光圈停在 point，泛起一圈波纹
    func showForDemo(at point: CGPoint) {
        stop()
        let halo = PointerHaloView(frame: CGRect(x: 0, y: 0, width: Self.panelSize, height: Self.panelSize))
        let panel = makePanel(content: halo)
        self.panel = panel
        self.halo = halo
        panel.setFrame(Self.frame(around: point), display: false)
        panel.orderFrontRegardless()
        halo.ripple()
    }

    private func follow(pressed: Bool) {
        guard let panel else { return }
        // 用当前的指针位置，不用事件里的：全局事件的坐标是相对别的窗口的
        panel.setFrameOrigin(Self.frame(around: NSEvent.mouseLocation).origin)
        if pressed {
            halo?.ripple()
        }
    }

    private func makePanel(content: NSView) -> NSPanel {
        let panel = NSPanel(contentRect: content.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        // 在屏幕画笔、按键显示上面
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = content
        return panel
    }
}

/// 光圈和波纹
private final class PointerHaloView: NSView {
    private let fill = CAShapeLayer()
    private let wave = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        wantsLayer = true
        let yellow = NSColor(srgbRed: 1, green: 0.84, blue: 0.04, alpha: 1)
        let circle = CGRect(x: (frame.width - PointerHighlight.diameter) / 2, y: (frame.height - PointerHighlight.diameter) / 2,
                            width: PointerHighlight.diameter, height: PointerHighlight.diameter)
        for shape in [fill, wave] {
            shape.frame = CGRect(origin: .zero, size: frame.size)
            shape.path = CGPath(ellipseIn: circle, transform: nil)
            layer?.addSublayer(shape)
        }
        fill.fillColor = yellow.withAlphaComponent(0.28).cgColor
        fill.strokeColor = yellow.withAlphaComponent(0.75).cgColor
        fill.lineWidth = 2
        wave.fillColor = nil
        wave.strokeColor = yellow.cgColor
        wave.lineWidth = 3
        wave.opacity = 0
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 按下鼠标：光圈缩一下，一圈波纹往外扩散后消失；系统打开了「减弱动态效果」时波纹只淡出，不放大、不缩
    func ripple() {
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion && !Motion.ignoresReduceMotion
        let duration = Motion.seconds(0.45)
        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = reduceMotion ? 1 : 0.7
        grow.toValue = reduceMotion ? 1 : PointerHighlight.rippleScale
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [grow, fade]
        group.duration = duration
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        wave.add(group, forKey: "ripple")

        guard !reduceMotion else { return }
        let press = CABasicAnimation(keyPath: "transform.scale")
        press.fromValue = 0.82
        press.toValue = 1
        press.duration = Motion.seconds(0.25)
        press.timingFunction = CAMediaTimingFunction(name: .easeOut)
        fill.add(press, forKey: "press")
    }
}
