import AppKit
import QuartzCore
import ScreenCaptureKit
@testable import Pop

/// 屏幕放大：演示、录教程时把指针附近放大，看清小字。先拍下指针所在的那块屏幕，再用一个窗口盖住它，显示放大的画面。
/// 指针挪到哪里就看哪里：指针下面一直是放大前它下面的内容，挪到屏幕边上就看到边上。
/// 滚轮、触控板捏合、↑↓ 或 +− 调倍数，点一下、Esc 或者再用一次回到正常。
/// 窗口在普通窗口、菜单栏和程序坞上面，在显示按键、摄像头小窗、指针光圈和 Pop 的圆盘下面（这些不拍进画面，一直是活的）；
/// 录屏时会一起录进去。
@MainActor
final class ScreenZoom {
    static let shared = ScreenZoom()
    /// 打开时放大的倍数
    nonisolated static let initialScale: CGFloat = 2
    /// 能调的倍数
    nonisolated static let scales: ClosedRange<CGFloat> = 1.25...8
    /// 按一下 ↑↓、滚轮转一格变多少
    nonisolated static let step: CGFloat = 1.25
    /// 窗口的层级：和屏幕画笔一样
    static let level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue - 1)

    private var window: ScreenZoomWindow?
    /// 开始前在前台的 App，结束后还给它
    private var previousApp: NSRunningApplication?
    private var closing = false

    var isActive: Bool { window != nil }

    /// 放大后的画面摆在哪（左下角为原点）：画面的左下角在「指针 × (1 − 倍数)」，
    /// 这样指针下面始终是放大前它下面的那一点，指针到了屏幕边上，画面的边也正好对齐屏幕的边
    nonisolated static func imageFrame(pointer: CGPoint, size: CGSize, scale: CGFloat) -> CGRect {
        let x = min(max(pointer.x, 0), size.width)
        let y = min(max(pointer.y, 0), size.height)
        return CGRect(x: x * (1 - scale), y: y * (1 - scale), width: size.width * scale, height: size.height * scale)
    }

    /// 调倍数时不超出能调的范围
    nonisolated static func clamped(_ scale: CGFloat) -> CGFloat {
        min(max(scale, scales.lowerBound), scales.upperBound)
    }

    /// 拍下 point 所在的屏幕放大显示；拍不了时返回原因
    func start(near point: CGPoint) async -> String? {
        guard !isActive else { return nil }
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }) ?? NSScreen.main,
              let displayID = screen.screenNumber else {
            return String(localized: "找不到要放大的屏幕")
        }
        let image: CGImage
        do {
            image = try await Self.capture(displayID: displayID)
        } catch {
            return CGPreflightScreenCaptureAccess() ? String(localized: "没能拍下屏幕：\(error.localizedDescription)") : ScreenRecording.permissionHint
        }
        // 拍的这一会儿又用了一次
        guard !isActive else { return nil }
        previousApp = NSWorkspace.shared.frontmostApplication
        let zoomWindow = present(image, on: screen, pointer: NSEvent.mouseLocation)
        NSApp.activate()
        zoomWindow.makeKeyAndOrderFront(nil)
        // 先按 1 倍盖上去（和屏幕一模一样），下一轮再放大，放大的过程才看得到
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.window === zoomWindow, !self.closing else { return }
                zoomWindow.zoomView.setScale(Self.initialScale, duration: Self.reduceMotion ? 0 : Motion.seconds(0.25))
            }
        }
        return nil
    }

    /// 回到正常：缩回原来的大小再收起
    func stop(animated: Bool = true) {
        guard let zoomWindow = window, !closing else { return }
        closing = true
        let duration = animated && !Self.reduceMotion ? Motion.seconds(0.18) : 0
        zoomWindow.zoomView.setScale(1, duration: duration)
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            MainActor.assumeIsolated {
                self?.finish(zoomWindow)
            }
        }
    }

    /// 演示用：把一张图当作屏幕放大，指针停在 pointer（这块屏幕上的坐标），不抢焦点
    func showForDemo(_ image: CGImage, on screen: NSScreen, pointer: CGPoint, scale: CGFloat) {
        if let current = self.window {
            finish(current)
        }
        let demoWindow = present(image, on: screen, pointer: CGPoint(x: screen.frame.minX + pointer.x, y: screen.frame.minY + pointer.y))
        demoWindow.zoomView.setScale(scale, duration: 0)
    }

    private func present(_ image: CGImage, on screen: NSScreen, pointer: CGPoint) -> ScreenZoomWindow {
        let zoomWindow = ScreenZoomWindow(screen: screen, image: image)
        zoomWindow.zoomView.pointer = CGPoint(x: pointer.x - screen.frame.minX, y: pointer.y - screen.frame.minY)
        zoomWindow.zoomView.onExit = { [weak self] in
            self?.stopSoon()
        }
        zoomWindow.zoomView.onKey = { [weak self] event in
            self?.handleKey(event) ?? false
        }
        self.window = zoomWindow
        closing = false
        zoomWindow.orderFrontRegardless()
        return zoomWindow
    }

    private func finish(_ zoomWindow: ScreenZoomWindow) {
        zoomWindow.orderOut(nil)
        guard self.window === zoomWindow else { return }
        self.window = nil
        closing = false
        if let previousApp, previousApp.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApp.activate()
        }
        previousApp = nil
    }

    /// 在按键、点击的处理过程中结束：等这一轮事件处理完再收起
    private func stopSoon() {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.stop()
            }
        }
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        guard let view = window?.zoomView else { return false }
        switch Int(event.keyCode) {
        case 53:
            stopSoon()
            return true
        case 126:
            view.zoom(by: Self.step, duration: Self.stepDuration)
            return true
        case 125:
            view.zoom(by: 1 / Self.step, duration: Self.stepDuration)
            return true
        default:
            break
        }
        switch event.charactersIgnoringModifiers {
        case "=", "+":
            view.zoom(by: Self.step, duration: Self.stepDuration)
            return true
        case "-", "_":
            view.zoom(by: 1 / Self.step, duration: Self.stepDuration)
            return true
        case "0":
            view.setScale(Self.initialScale, duration: Self.stepDuration)
            return true
        default:
            return false
        }
    }

    static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion && !Motion.ignoresReduceMotion
    }

    /// 一档一档调倍数时的动画
    static var stepDuration: Double {
        reduceMotion ? 0 : Motion.seconds(0.12)
    }

    /// 拍下整块屏幕（不带指针）。Pop 自己在这个窗口上面的那些（显示按键、摄像头小窗、指针光圈、圆盘）不拍，放大时它们还在上面
    private static func capture(displayID: CGDirectDisplayID) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.noDisplay
        }
        let pid = ProcessInfo.processInfo.processIdentifier
        let above = content.windows.filter { $0.owningApplication?.processID == pid && $0.windowLayer > level.rawValue }
        let filter = SCContentFilter(display: display, excludingWindows: above)
        let scale = CGFloat(filter.pointPixelScale)
        let configuration = SCStreamConfiguration()
        configuration.width = max(1, Int((CGFloat(display.width) * scale).rounded()))
        configuration.height = max(1, Int((CGFloat(display.height) * scale).rounded()))
        configuration.showsCursor = false
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }

    private enum CaptureError: LocalizedError {
        case noDisplay

        var errorDescription: String? {
            String(localized: "找不到要放大的屏幕")
        }
    }

    /// 演示用的「屏幕」：淡淡的渐变做底，示例截图放在 rect（这块屏幕上的坐标，左下角为原点）
    nonisolated static func demoSnapshot(size: CGSize, scale: CGFloat, sample: CGImage, in rect: CGRect) -> CGImage? {
        let width = max(1, Int((size.width * scale).rounded()))
        let height = max(1, Int((size.height * scale).rounded()))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.scaleBy(x: scale, y: scale)
        let colors = [CGColor(srgbRed: 0.84, green: 0.88, blue: 0.95, alpha: 1), CGColor(srgbRed: 0.74, green: 0.79, blue: 0.9, alpha: 1)]
        if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: [0, 1]) {
            context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size.height), end: CGPoint(x: size.width, y: 0), options: [])
        }
        context.draw(sample, in: rect)
        return context.makeImage()
    }
}

/// 盖住一整块屏幕的窗口
private final class ScreenZoomWindow: NSWindow {
    let zoomView: ScreenZoomView

    init(screen: NSScreen, image: CGImage) {
        zoomView = ScreenZoomView(frame: CGRect(origin: .zero, size: screen.frame.size), image: image)
        super.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        level = ScreenZoom.level
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        contentView = zoomView
        setFrame(screen.frame, display: false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var canBecomeKey: Bool { true }
}

/// 放大的画面：截图放在一个子图层里，按倍数放大、跟着指针挪
private final class ScreenZoomView: NSView {
    private let imageLayer = CALayer()
    private(set) var scale: CGFloat = 1
    /// 指针在这块屏幕上的位置（左下角为原点）
    var pointer: CGPoint = .zero {
        didSet { place(duration: 0) }
    }
    var onExit: () -> Void = {}
    var onKey: (NSEvent) -> Bool = { _ in false }

    init(frame: CGRect, image: CGImage) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.masksToBounds = true
        imageLayer.contents = image
        imageLayer.contentsGravity = .resize
        imageLayer.magnificationFilter = .linear
        imageLayer.minificationFilter = .trilinear
        layer?.addSublayer(imageLayer)
        place(duration: 0)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.activeAlways, .inVisibleRect, .mouseMoved], owner: self, userInfo: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        pointer = convert(event.locationInWindow, from: nil)
    }

    override func mouseDown(with event: NSEvent) {
        onExit()
    }

    override func rightMouseDown(with event: NSEvent) {
        onExit()
    }

    /// 滚轮一格一档；触控板按滑动的距离连续调
    override func scrollWheel(with event: NSEvent) {
        let delta = event.scrollingDeltaY
        guard delta != 0 else { return }
        if event.hasPreciseScrollingDeltas {
            zoom(by: pow(ScreenZoom.step, delta / 40), duration: 0)
        } else {
            zoom(by: delta > 0 ? ScreenZoom.step : 1 / ScreenZoom.step, duration: ScreenZoom.stepDuration)
        }
    }

    /// 触控板双指捏合
    override func magnify(with event: NSEvent) {
        zoom(by: 1 + event.magnification, duration: 0)
    }

    override func keyDown(with event: NSEvent) {
        if !onKey(event) {
            super.keyDown(with: event)
        }
    }

    func zoom(by factor: CGFloat, duration: Double) {
        setScale(ScreenZoom.clamped(scale * factor), duration: duration)
    }

    /// 打开、收起时从 1 倍开始、回到 1 倍，所以这里不限制下限
    func setScale(_ value: CGFloat, duration: Double) {
        scale = min(max(value, 1), ScreenZoom.scales.upperBound)
        place(duration: duration)
    }

    private func place(duration: Double) {
        CATransaction.begin()
        if duration > 0 {
            CATransaction.setAnimationDuration(duration)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        } else {
            CATransaction.setDisableActions(true)
        }
        imageLayer.frame = ScreenZoom.imageFrame(pointer: pointer, size: bounds.size, scale: scale)
        CATransaction.commit()
    }
}
