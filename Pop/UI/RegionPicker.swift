import AppKit
import Carbon.HIToolbox
import SwiftUI

/// 录屏前选要录的地方：拖出一块区域，单击录指针下面的窗口（没有窗口就录整个屏幕），回车录整个屏幕，Esc 或右键取消。
/// 屏幕上方的提示条里可以勾选「录上电脑里的声音」「显示鼠标点击」，下次还记得。
@MainActor
final class RegionPicker {
    struct Selection {
        let screen: NSScreen
        /// 全局坐标，左下角为原点
        let rect: CGRect
        let options: ScreenRecording.Options
    }

    private static var current: RegionPicker?

    private let screen: NSScreen
    private let window: PickerWindow
    private let model: PickerOptionsModel
    private let previousApp: NSRunningApplication?
    private var continuation: CheckedContinuation<Selection?, Never>?

    /// 在指针所在的屏幕上选；选好了返回选中的地方，取消了返回 nil
    static func pick() async -> Selection? {
        current?.finish(nil)
        let point = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }) ?? NSScreen.main else {
            return nil
        }
        let picker = RegionPicker(screen: screen)
        current = picker
        return await withCheckedContinuation { (continuation: CheckedContinuation<Selection?, Never>) in
            picker.continuation = continuation
            picker.window.makeKeyAndOrderFront(nil)
            NSApp.activate()
        }
    }

    /// 收起正在选的界面，当作取消
    static func cancel() {
        current?.finish(nil)
    }

    private init(screen: NSScreen) {
        self.screen = screen
        previousApp = NSWorkspace.shared.frontmostApplication
        model = PickerOptionsModel(options: .saved())
        let view = PickerView(frame: CGRect(origin: .zero, size: screen.frame.size), screenFrame: screen.frame)
        window = PickerWindow(screen: screen, view: view)

        // 提示条放在屏幕上方居中，菜单栏下面
        let hud = NSHostingView(rootView: PickerHUD(model: model))
        let size = hud.fittingSize
        let top = max(screen.safeAreaInsets.top, NSStatusBar.system.thickness) + 24
        hud.frame = CGRect(x: ((view.bounds.width - size.width) / 2).rounded(), y: (view.bounds.height - top - size.height).rounded(),
                           width: size.width, height: size.height)
        view.addSubview(hud)

        view.onFinish = { [weak self] rect in
            self?.finish(rect)
        }
    }

    private func finish(_ rect: CGRect?) {
        window.orderOut(nil)
        if Self.current === self {
            Self.current = nil
        }
        model.options.save()
        // 键盘还给原来的 App，录的时候接着在里面操作
        if let previousApp, previousApp.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApp.activate()
        }
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: rect.map { Selection(screen: screen, rect: $0, options: model.options) })
    }
}

@MainActor
private final class PickerOptionsModel: ObservableObject {
    @Published var options: ScreenRecording.Options

    init(options: ScreenRecording.Options) {
        self.options = options
    }
}

/// 屏幕上方的操作提示和两个勾选项
private struct PickerHUD: View {
    @ObservedObject var model: PickerOptionsModel

    var body: some View {
        VStack(spacing: 7) {
            Text("拖出要录的区域 · 单击录窗口 · 回车录整个屏幕 · Esc 取消")
                .font(.system(size: 12, weight: .medium))
            HStack(spacing: 16) {
                Toggle("录上电脑里的声音", isOn: $model.options.systemAudio)
                Toggle("显示鼠标点击", isOn: $model.options.showClicks)
            }
            .toggleStyle(.checkbox)
            .font(.system(size: 12))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.black.opacity(0.78)))
        .environment(\.colorScheme, .dark)
        .fixedSize()
    }
}

private final class PickerWindow: NSWindow {
    init(screen: NSScreen, view: NSView) {
        super.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        // 透明的地方也要接住鼠标，不能点到下面的窗口
        ignoresMouseEvents = false
        hasShadow = false
        acceptsMouseMovedEvents = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = view
        setFrame(screen.frame, display: false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// 盖在屏幕上的一层：选中的地方亮着，其余变暗
private final class PickerView: NSView {
    /// 选好的地方（全局坐标）；取消时为 nil
    var onFinish: (CGRect?) -> Void = { _ in }

    private let screenFrame: CGRect
    /// 选区域的窗口出来之前屏幕上的窗口，从前到后
    private let windows: [ScreenRecording.WindowInfo]
    /// 按下鼠标的位置
    private var pressLocation: CGPoint?
    /// 正在拖出来的区域
    private var dragRect: CGRect?
    /// 指针下面的窗口；没有窗口时是整个屏幕
    private var hovered: CGRect?
    private var hoveringWindow = false

    init(frame: CGRect, screenFrame: CGRect) {
        self.screenFrame = screenFrame
        windows = PickerView.onScreenWindows()
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect, .cursorUpdate],
                                       owner: self, userInfo: nil))
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.crosshair.set()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
        if let window {
            updateHover(convert(window.mouseLocationOutsideOfEventStream, from: nil))
        }
    }

    /// 屏幕上正在显示的窗口，从前到后
    private static func onScreenWindows() -> [ScreenRecording.WindowInfo] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return list.compactMap { info in
            guard let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return nil }
            return ScreenRecording.WindowInfo(frame: frame,
                                              layer: (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0,
                                              ownerPID: pid_t((info[kCGWindowOwnerPID as String] as? NSNumber)?.intValue ?? 0),
                                              alpha: (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1)
        }
    }

    // MARK: - 鼠标和键盘

    private func updateHover(_ point: CGPoint) {
        let global = CGPoint(x: point.x + screenFrame.minX, y: point.y + screenFrame.minY)
        let frame = ScreenRecording.window(at: global, in: windows, ownPID: ProcessInfo.processInfo.processIdentifier,
                                           primaryHeight: OverlayController.primaryScreenHeight, screenFrame: screenFrame)
        hoveringWindow = frame != nil
        hovered = (frame ?? screenFrame).offsetBy(dx: -screenFrame.minX, dy: -screenFrame.minY)
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        updateHover(convert(event.locationInWindow, from: nil))
    }

    override func mouseDown(with event: NSEvent) {
        pressLocation = convert(event.locationInWindow, from: nil)
        dragRect = nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = pressLocation else { return }
        let rect = ScreenRecording.region(from: start, to: convert(event.locationInWindow, from: nil), in: bounds)
        // 拖出一点距离才算开始选区域
        if dragRect != nil || rect.width >= 4 || rect.height >= 4 {
            dragRect = rect
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        pressLocation = nil
        if let rect = dragRect {
            dragRect = nil
            if rect.width >= ScreenRecording.minimumSide, rect.height >= ScreenRecording.minimumSide {
                finish(rect)
            } else {
                // 拖得太小，当作没拖
                updateHover(convert(event.locationInWindow, from: nil))
            }
            return
        }
        // 单击：录指针下面的窗口，没有窗口就录整个屏幕
        updateHover(convert(event.locationInWindow, from: nil))
        finish(hovered ?? bounds)
    }

    override func rightMouseDown(with event: NSEvent) {
        onFinish(nil)
    }

    override func keyDown(with event: NSEvent) {
        switch Int(event.keyCode) {
        case kVK_Escape:
            onFinish(nil)
        case kVK_Return, kVK_ANSI_KeypadEnter:
            finish(bounds)
        default:
            super.keyDown(with: event)
        }
    }

    /// 视图里的区域换成全局坐标交出去
    private func finish(_ rect: CGRect) {
        onFinish(rect.offsetBy(dx: screenFrame.minX, dy: screenFrame.minY))
    }

    // MARK: - 画

    override func draw(_ dirtyRect: NSRect) {
        let hole = dragRect ?? (pressLocation == nil ? hovered : nil) ?? .zero
        let dim = NSBezierPath(rect: bounds)
        if !hole.isEmpty {
            dim.appendRect(hole)
            dim.windingRule = .evenOdd
        }
        NSColor.black.withAlphaComponent(0.35).setFill()
        dim.fill()
        guard !hole.isEmpty else { return }
        // 亮着的地方也铺一层几乎看不出来的颜色，保证点得到这个窗口
        NSColor.black.withAlphaComponent(0.004).setFill()
        NSBezierPath(rect: hole).fill()

        NSColor.systemRed.setStroke()
        let border = NSBezierPath(rect: hole.insetBy(dx: 1, dy: 1))
        border.lineWidth = 2
        if dragRect == nil {
            border.setLineDash([6, 4], count: 2, phase: 0)
        }
        border.stroke()

        let size = "\(Int(hole.width)) × \(Int(hole.height))"
        let label: String
        if dragRect != nil {
            label = size
        } else if hoveringWindow {
            label = String(localized: "单击录这个窗口 · \(size)")
        } else {
            label = String(localized: "单击或按回车录整个屏幕")
        }
        drawLabel(label, below: hole)
    }

    /// 标签放在区域左下角的下面，放不下就放进区域里
    private func drawLabel(_ text: String, below rect: CGRect) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let string = NSAttributedString(string: text, attributes: attributes)
        let size = string.size()
        var box = CGRect(x: rect.minX, y: rect.minY - size.height - 14, width: size.width + 14, height: size.height + 8)
        if box.minY < bounds.minY + 4 {
            box.origin.y = rect.minY + 8
            box.origin.x = rect.minX + 8
        }
        box.origin.x = min(max(box.origin.x, bounds.minX + 4), bounds.maxX - box.width - 4)
        NSColor.black.withAlphaComponent(0.78).setFill()
        NSBezierPath(roundedRect: box, xRadius: 6, yRadius: 6).fill()
        string.draw(at: CGPoint(x: box.minX + 7, y: box.minY + 4))
    }
}
