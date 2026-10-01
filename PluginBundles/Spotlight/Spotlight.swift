import AppKit
import QuartzCore
@testable import Pop

/// 聚光灯：演示、录教程时把屏幕压暗，只留指针周围一圈亮着，边缘柔和，跟着指针走。
/// 每块屏幕铺一个不接鼠标的窗口，录屏时会一起录进去；指针不在这块屏幕上时整块压暗。
/// 窗口在普通窗口和菜单栏上面，在 Pop 的圆盘、卡片、显示按键、摄像头小窗和指针光圈下面。
@MainActor
final class Spotlight {
    static let shared = Spotlight()
    /// 亮着的那一圈的半径（点）
    nonisolated static let radius: CGFloat = 150
    /// 压暗的程度
    nonisolated static let dimming: CGFloat = 0.62

    private var panels: [NSPanel] = []
    private var monitors: [Any] = []
    private var screensObserver: NSObjectProtocol?

    var isActive: Bool { !panels.isEmpty }

    func start() {
        guard panels.isEmpty else { return }
        showPanels(pointer: NSEvent.mouseLocation)
        let moves: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        // 别的 App 里的移动
        if let global = NSEvent.addGlobalMonitorForEvents(matching: moves, handler: { [weak self] _ in
            MainActor.assumeIsolated {
                self?.follow()
            }
        }) {
            monitors.append(global)
        }
        // Pop 自己的窗口里的
        if let local = NSEvent.addLocalMonitorForEvents(matching: moves, handler: { [weak self] event in
            MainActor.assumeIsolated {
                self?.follow()
            }
            return event
        }) {
            monitors.append(local)
        }
        // 接上、拔掉显示器或者改了分辨率：按现在的屏幕重新铺一遍
        screensObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                                 object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isActive else { return }
                self.removePanels()
                self.showPanels(pointer: NSEvent.mouseLocation)
            }
        }
    }

    func stop() {
        for monitor in monitors {
            NSEvent.removeMonitor(monitor)
        }
        monitors = []
        if let screensObserver {
            NotificationCenter.default.removeObserver(screensObserver)
        }
        screensObserver = nil
        removePanels()
    }

    /// 演示用：亮着的那一圈停在 point，不跟着指针走
    func showForDemo(at point: CGPoint) {
        stop()
        showPanels(pointer: point)
    }

    private func showPanels(pointer: CGPoint) {
        for screen in NSScreen.screens {
            let panel = makePanel(frame: screen.frame)
            panels.append(panel)
            panel.orderFrontRegardless()
        }
        follow(to: pointer)
    }

    private func removePanels() {
        for panel in panels {
            panel.orderOut(nil)
        }
        panels = []
    }

    /// 用当前的指针位置，不用事件里的：全局事件的坐标是相对别的窗口的
    private func follow(to point: CGPoint = NSEvent.mouseLocation) {
        for panel in panels {
            (panel.contentView as? SpotlightView)?.center = CGPoint(x: point.x - panel.frame.minX, y: point.y - panel.frame.minY)
        }
    }

    private func makePanel(frame: CGRect) -> NSPanel {
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue - 1)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = SpotlightView(frame: CGRect(origin: .zero, size: frame.size))
        panel.setFrame(frame, display: false)
        return panel
    }
}

/// 压暗的一层，指针那里挖掉一个边缘柔和的圆：用径向渐变当遮罩，圆心附近透明，到半径处变成不透明
private final class SpotlightView: NSView {
    private let dim = CALayer()
    private let hole = CAGradientLayer()

    /// 圆心（这块屏幕上的坐标，左下角为原点）
    var center: CGPoint = .zero {
        didSet { moveHole() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        wantsLayer = true
        dim.frame = bounds
        dim.backgroundColor = NSColor.black.withAlphaComponent(Spotlight.dimming).cgColor
        hole.type = .radial
        hole.frame = bounds
        hole.colors = [NSColor.clear.cgColor, NSColor.clear.cgColor, NSColor.black.cgColor]
        hole.locations = [0, 0.7, 1]
        dim.mask = hole
        layer?.addSublayer(dim)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 径向渐变的起点是圆心，终点和起点在两个方向上各差一个半径（按图层的比例坐标）
    private func moveHole() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        hole.startPoint = CGPoint(x: center.x / bounds.width, y: center.y / bounds.height)
        hole.endPoint = CGPoint(x: (center.x + Spotlight.radius) / bounds.width, y: (center.y + Spotlight.radius) / bounds.height)
        CATransaction.commit()
    }
}
