import AppKit
import Carbon.HIToolbox

/// 屏幕标尺：把指针所在的屏幕定格，指针处自动量出到上下左右边缘的距离；按住拖动量一块区域的宽高。
/// 单击复制量到的尺寸，Esc 或右键退出。
@MainActor
final class ScreenRuler {
    private static var current: ScreenRuler?

    private let window: RulerWindow

    /// 开始量；截不到屏幕时返回原因
    static func start() async -> String? {
        current?.close()
        let point = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }) ?? NSScreen.main else {
            return "找不到屏幕"
        }
        guard let image = await capture(screen), let finder = EdgeFinder(image: image) else {
            return "截不到屏幕。请在「系统设置 → 隐私与安全性 → 录屏与系统录音」里允许 Pop。"
        }
        let ruler = ScreenRuler(screen: screen, image: image, finder: finder)
        current = ruler
        ruler.window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        return nil
    }

    private init(screen: NSScreen, image: CGImage, finder: EdgeFinder) {
        let view = RulerView(image: image, finder: finder, frame: CGRect(origin: .zero, size: screen.frame.size))
        window = RulerWindow(screen: screen, view: view)
        view.onFinish = { [weak self] measured in
            self?.finish(copying: measured)
        }
    }

    private func finish(copying measured: String?) {
        let point = NSEvent.mouseLocation
        close()
        guard let measured else { return }
        PasteboardWriter.copy(measured)
        PinBoard.shared.onToast?("已复制 \(measured)", point)
    }

    private func close() {
        window.orderOut(nil)
        if Self.current === self {
            Self.current = nil
        }
    }

    /// 用系统的 screencapture 截下整块屏幕（点坐标，左上角为原点），得到原始像素的图
    private static func capture(_ screen: NSScreen) async -> CGImage? {
        if !CGPreflightScreenCaptureAccess() {
            _ = CGRequestScreenCaptureAccess()
        }
        let frame = screen.frame
        let top = OverlayController.primaryScreenHeight - frame.maxY
        let rect = "\(Int(frame.minX)),\(Int(top)),\(Int(frame.width)),\(Int(frame.height))"
        let url = FileManager.default.temporaryDirectory.appending(path: "pop-ruler-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }
        let result = await ProcessRunner.run(URL(fileURLWithPath: "/usr/sbin/screencapture"),
                                             arguments: ["-x", "-R", rect, url.path(percentEncoded: false)],
                                             stdin: nil, environment: [:], timeout: 30)
        guard case .success = result, let data = try? Data(contentsOf: url) else { return nil }
        return TextRecognizer.cgImage(from: data)
    }
}

private final class RulerWindow: NSWindow {
    init(screen: NSScreen, view: NSView) {
        super.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        level = .screenSaver
        isOpaque = true
        backgroundColor = .black
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

/// 定格的屏幕和量出来的线、尺寸
private final class RulerView: NSView {
    var onFinish: (String?) -> Void = { _ in }

    private let image: NSImage
    private let finder: EdgeFinder
    /// 截图的像素和视图的点的比例
    private let pixelsPerPoint: CGFloat
    private var pointer: CGPoint?
    /// 按下鼠标的位置
    private var pressLocation: CGPoint?
    /// 正在拖出来的区域
    private var dragRect: CGRect?
    /// 上一次拖出来的区域，一直显示到下一次拖动或者退出
    private var heldRect: CGRect?

    init(image: CGImage, finder: EdgeFinder, frame: CGRect) {
        self.image = NSImage(cgImage: image, size: frame.size)
        self.finder = finder
        pixelsPerPoint = CGFloat(image.width) / max(frame.width, 1)
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 左上角为原点，和截图的行一致
    override var isFlipped: Bool { true }
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
            pointer = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        }
    }

    // MARK: - 量

    /// 指针处上下左右到边的范围（点）
    private func crossRect(at point: CGPoint) -> CGRect? {
        let x = Int(point.x * pixelsPerPoint)
        let y = Int(point.y * pixelsPerPoint)
        guard let span = finder.span(atX: x, y: y) else { return nil }
        return CGRect(x: CGFloat(span.left) / pixelsPerPoint, y: CGFloat(span.top) / pixelsPerPoint,
                      width: CGFloat(span.width) / pixelsPerPoint, height: CGFloat(span.height) / pixelsPerPoint)
    }

    /// 现在显示的尺寸：拖出来的区域优先，否则是指针处的十字
    private var measurement: String? {
        if let rect = dragRect ?? heldRect {
            return Self.size(rect.size)
        }
        guard let pointer, let cross = crossRect(at: pointer) else { return nil }
        return Self.size(cross.size)
    }

    static func size(_ size: CGSize) -> String {
        "\(number(size.width)) × \(number(size.height))"
    }

    private static func number(_ value: CGFloat) -> String {
        abs(value - value.rounded()) < 0.05 ? "\(Int(value.rounded()))" : String(format: "%.1f", value)
    }

    // MARK: - 鼠标和键盘

    override func mouseMoved(with event: NSEvent) {
        pointer = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        pressLocation = convert(event.locationInWindow, from: nil)
        dragRect = nil
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        pointer = point
        guard let start = pressLocation else { return }
        let rect = CGRect(x: min(start.x, point.x), y: min(start.y, point.y),
                          width: abs(point.x - start.x), height: abs(point.y - start.y))
        // 拖出一点距离才算开始量区域
        if rect.width >= 2 || rect.height >= 2 {
            dragRect = rect
            heldRect = nil
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        pointer = convert(event.locationInWindow, from: nil)
        pressLocation = nil
        if let rect = dragRect {
            // 拖完先把这块区域留在屏幕上，再单击一下复制
            heldRect = rect
            dragRect = nil
            needsDisplay = true
            return
        }
        // 单击：复制现在显示的尺寸（留着的区域，或者指针处的十字）
        onFinish(measurement)
    }

    override func rightMouseDown(with event: NSEvent) {
        onFinish(nil)
    }

    override func keyDown(with event: NSEvent) {
        if Int(event.keyCode) == kVK_Escape {
            onFinish(nil)
        } else {
            super.keyDown(with: event)
        }
    }

    // MARK: - 画

    override func draw(_ dirtyRect: NSRect) {
        image.draw(in: bounds, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
        NSColor.black.withAlphaComponent(0.08).setFill()
        NSBezierPath(rect: bounds).fill()

        if let rect = dragRect ?? heldRect {
            drawArea(rect)
        } else if let pointer, let cross = crossRect(at: pointer) {
            drawCross(cross, at: pointer)
        }
        drawHint()
    }

    private func drawCross(_ cross: CGRect, at point: CGPoint) {
        let color = NSColor.systemPink
        color.setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1
        path.move(to: CGPoint(x: cross.minX, y: point.y))
        path.line(to: CGPoint(x: cross.maxX, y: point.y))
        path.move(to: CGPoint(x: point.x, y: cross.minY))
        path.line(to: CGPoint(x: point.x, y: cross.maxY))
        // 两头的短竖线
        for x in [cross.minX, cross.maxX] {
            path.move(to: CGPoint(x: x, y: point.y - 5))
            path.line(to: CGPoint(x: x, y: point.y + 5))
        }
        for y in [cross.minY, cross.maxY] {
            path.move(to: CGPoint(x: point.x - 5, y: y))
            path.line(to: CGPoint(x: point.x + 5, y: y))
        }
        path.stroke()
        drawLabel(Self.size(cross.size), near: point)
    }

    private func drawArea(_ rect: CGRect) {
        NSColor.systemPink.withAlphaComponent(0.15).setFill()
        NSBezierPath(rect: rect).fill()
        NSColor.systemPink.setStroke()
        let border = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = 1
        border.stroke()
        drawLabel(Self.size(rect.size), near: CGPoint(x: rect.maxX, y: rect.maxY))
    }

    /// 尺寸标签：放在 point 右下方，靠边时往里收
    private func drawLabel(_ text: String, near point: CGPoint) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let string = NSAttributedString(string: text, attributes: attributes)
        let size = string.size()
        var box = CGRect(x: point.x + 12, y: point.y + 12, width: size.width + 12, height: size.height + 6)
        box.origin.x = min(box.origin.x, bounds.maxX - box.width - 4)
        box.origin.y = min(box.origin.y, bounds.maxY - box.height - 4)
        NSColor.black.withAlphaComponent(0.78).setFill()
        NSBezierPath(roundedRect: box, xRadius: 5, yRadius: 5).fill()
        string.draw(at: CGPoint(x: box.minX + 6, y: box.minY + 3))
    }

    /// 屏幕上方居中的操作提示
    private func drawHint() {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let string = NSAttributedString(string: "单击复制尺寸 · 拖动量一块区域 · Esc 退出", attributes: attributes)
        let size = string.size()
        let box = CGRect(x: bounds.midX - size.width / 2 - 12, y: 44, width: size.width + 24, height: size.height + 10)
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: box, xRadius: box.height / 2, yRadius: box.height / 2).fill()
        string.draw(at: CGPoint(x: box.minX + 12, y: box.minY + 5))
    }
}
