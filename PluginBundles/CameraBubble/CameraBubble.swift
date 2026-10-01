import AppKit
import AVFoundation
@testable import Pop

/// 摄像头小窗：屏幕角落一个圆形的小窗口，显示摄像头拍到的画面（像照镜子一样左右翻过来）。
/// 录教程、演示时把人也放进画面里：录屏会一起录进去。拖动换位置，滚动或双击换大小，右键换形状、换摄像头；再用一次关闭。
@MainActor
final class CameraBubble {
    static let shared = CameraBubble()
    /// 双击在这几种大小（点）之间切换，滚动可以停在中间任意大小
    nonisolated static let sizes: [CGFloat] = [140, 200, 280]
    nonisolated static let sizeRange: ClosedRange<CGFloat> = 110...420
    static let sizeKey = "pop.cameraBubble.size"
    static let shapeKey = "pop.cameraBubble.shape"

    enum Shape: String, CaseIterable {
        case circle, roundedSquare

        var title: String {
            switch self {
            case .circle: return String(localized: "圆形")
            case .roundedSquare: return String(localized: "圆角方形")
            }
        }
    }

    private var window: CameraBubbleWindow?
    private var session: AVCaptureSession?
    private var device: AVCaptureDevice?
    /// 开关摄像头会卡一下，放到后台做
    private let sessionQueue = DispatchQueue(label: "pop.camera-bubble")

    var isActive: Bool { window != nil }

    /// 默认放在屏幕右下角，离边缘留一点空
    nonisolated static func defaultFrame(size: CGFloat, in visible: CGRect) -> CGRect {
        CGRect(x: visible.maxX - size - 24, y: visible.minY + 24, width: size, height: size)
    }

    /// 换大小时中心不动，超出屏幕的挪回来
    nonisolated static func resized(_ frame: CGRect, to size: CGFloat, within visible: CGRect) -> CGRect {
        var result = CGRect(x: frame.midX - size / 2, y: frame.midY - size / 2, width: size, height: size)
        result.origin.x = min(max(result.minX, visible.minX), visible.maxX - size)
        result.origin.y = min(max(result.minY, visible.minY), visible.maxY - size)
        return result
    }

    /// 双击：换到下一档大小，最大的下一档回到最小
    nonisolated static func nextSize(after size: CGFloat) -> CGFloat {
        sizes.first { $0 > size + 1 } ?? sizes[0]
    }

    /// 滚动：往上滚变大、往下滚变小
    nonisolated static func scrolled(_ size: CGFloat, by delta: CGFloat) -> CGFloat {
        min(max(size + delta, sizeRange.lowerBound), sizeRange.upperBound)
    }

    /// 打开；没有权限、没有摄像头时返回原因
    func start(near point: CGPoint) async -> String? {
        guard !isActive else { return nil }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else { return Self.permissionHint }
        default:
            return Self.permissionHint
        }
        guard let device = AVCaptureDevice.default(for: .video) ?? Self.cameras().first else {
            return String(localized: "没有找到摄像头")
        }
        let session = AVCaptureSession()
        do {
            try Self.use(device, in: session)
        } catch {
            return String(localized: "摄像头打不开：\(error.localizedDescription)")
        }
        guard !isActive else { return nil }
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        self.session = session
        self.device = device
        present(content: preview, mirrored: true, near: point)
        sessionQueue.async {
            session.startRunning()
        }
        return nil
    }

    func stop() {
        if let session {
            sessionQueue.async {
                session.stopRunning()
            }
        }
        session = nil
        device = nil
        window?.orderOut(nil)
        window = nil
    }

    /// 演示用：不开摄像头，拿一张图当作画面；返回小窗的位置
    func showForDemo(image: CGImage, on screen: NSScreen) -> CGRect {
        stop()
        let layer = CALayer()
        layer.contents = image
        layer.contentsGravity = .resizeAspectFill
        present(content: layer, mirrored: false, near: CGPoint(x: screen.frame.midX, y: screen.frame.midY))
        window?.sharingType = .readOnly
        return window?.frame ?? .zero
    }

    static var permissionHint: String {
        String(localized: "要先在「系统设置 → 隐私与安全性 → 摄像头」里允许 Pop，才能打开摄像头小窗")
    }

    /// 这台 Mac 能用的摄像头：自带的、外接的、连续互通的 iPhone
    static func cameras() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
                                         mediaType: .video, position: .unspecified).devices
    }

    /// 在后台队列上也会调用，不能绑在主线程上
    nonisolated private static func use(_ device: AVCaptureDevice, in session: AVCaptureSession) throws {
        let input = try AVCaptureDeviceInput(device: device)
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        for old in session.inputs {
            session.removeInput(old)
        }
        if session.canSetSessionPreset(.high) {
            session.sessionPreset = .high
        }
        guard session.canAddInput(input) else {
            throw CocoaError(.featureUnsupported)
        }
        session.addInput(input)
    }

    private func present(content: CALayer, mirrored: Bool, near point: CGPoint) {
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }) ?? NSScreen.main else { return }
        let defaults = UserDefaults.standard
        let savedSize = CGFloat(defaults.double(forKey: Self.sizeKey))
        let size = Self.sizeRange.contains(savedSize) ? savedSize : Self.sizes[1]
        let shape = defaults.string(forKey: Self.shapeKey).flatMap(Shape.init(rawValue:)) ?? .circle
        let view = CameraBubbleView(content: content, mirrored: mirrored, shape: shape)
        let window = CameraBubbleWindow(frame: Self.defaultFrame(size: size, in: screen.visibleFrame), view: view)
        view.onDoubleClick = { [weak self] in
            guard let self, let window = self.window else { return }
            self.resize(to: Self.nextSize(after: window.frame.width), animated: true)
        }
        view.onScroll = { [weak self] delta in
            guard let self, let window = self.window else { return }
            self.resize(to: Self.scrolled(window.frame.width, by: delta), animated: false)
        }
        view.menuProvider = { [weak self] in
            self?.menu() ?? NSMenu()
        }
        self.window = window
        window.orderFrontRegardless()
    }

    private func resize(to size: CGFloat, animated: Bool) {
        guard let window else { return }
        let visible = (window.screen ?? NSScreen.main)?.visibleFrame ?? window.frame
        let frame = Self.resized(window.frame, to: size, within: visible)
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Motion.seconds(0.2)
                window.animator().setFrame(frame, display: true)
            }
        } else {
            window.setFrame(frame, display: true)
        }
        UserDefaults.standard.set(Double(size), forKey: Self.sizeKey)
    }

    /// 右键菜单：大小、形状、换摄像头、关闭
    private func menu() -> NSMenu {
        let menu = NSMenu()
        let current = window?.frame.width ?? 0
        for (size, title) in zip(Self.sizes, [String(localized: "小"), String(localized: "中"), String(localized: "大")]) {
            let item = MenuAction.item(title) { [weak self] in self?.resize(to: size, animated: true) }
            item.state = abs(current - size) < 1 ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let shape = window?.bubble.shape ?? .circle
        for option in Shape.allCases {
            let item = MenuAction.item(option.title) { [weak self] in
                self?.window?.bubble.shape = option
                UserDefaults.standard.set(option.rawValue, forKey: Self.shapeKey)
            }
            item.state = option == shape ? .on : .off
            menu.addItem(item)
        }
        let cameras = Self.cameras()
        if cameras.count > 1 {
            menu.addItem(.separator())
            for camera in cameras {
                let item = MenuAction.item(camera.localizedName) { [weak self] in self?.switchTo(camera) }
                item.state = camera.uniqueID == device?.uniqueID ? .on : .off
                menu.addItem(item)
            }
        }
        menu.addItem(.separator())
        menu.addItem(MenuAction.item(String(localized: "关闭摄像头小窗")) { [weak self] in self?.stop() })
        return menu
    }

    private func switchTo(_ camera: AVCaptureDevice) {
        guard let session, camera.uniqueID != device?.uniqueID else { return }
        device = camera
        sessionQueue.async {
            try? Self.use(camera, in: session)
        }
    }
}

/// NSMenuItem 的动作写成闭包
@MainActor
private final class MenuAction: NSObject {
    private let action: () -> Void

    private init(_ action: @escaping () -> Void) {
        self.action = action
    }

    @objc private func run() {
        action()
    }

    static func item(_ title: String, action: @escaping () -> Void) -> NSMenuItem {
        let target = MenuAction(action)
        let item = NSMenuItem(title: title, action: #selector(run), keyEquivalent: "")
        item.target = target
        // 菜单项只弱引用 target，挂在 representedObject 上让它活着
        item.representedObject = target
        return item
    }
}

/// 放小窗的面板：在普通窗口上面，不抢焦点，可以拖动
private final class CameraBubbleWindow: NSPanel {
    let bubble: CameraBubbleView

    init(frame: CGRect, view: CameraBubbleView) {
        bubble = view
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .statusBar
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isFloatingPanel = true
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        contentView = view
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var canBecomeKey: Bool { false }
}

/// 小窗里的画面：裁成圆形或圆角方形，外面一圈白边
private final class CameraBubbleView: NSView {
    private let content: CALayer
    private let mirrored: Bool
    var onDoubleClick: () -> Void = {}
    var onScroll: (CGFloat) -> Void = { _ in }
    var menuProvider: () -> NSMenu = { NSMenu() }

    var shape: CameraBubble.Shape {
        didSet { needsLayout = true }
    }

    init(content: CALayer, mirrored: Bool, shape: CameraBubble.Shape) {
        self.content = content
        self.mirrored = mirrored
        self.shape = shape
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.borderWidth = 3
        layer?.borderColor = NSColor.white.withAlphaComponent(0.92).cgColor
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.addSublayer(content)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.cornerRadius = shape == .circle ? bounds.width / 2 : bounds.width * 0.16
        // 画面左右翻过来，像照镜子：用 bounds 和 position 摆，transform 不影响位置
        content.bounds = bounds
        content.position = CGPoint(x: bounds.midX, y: bounds.midY)
        content.setAffineTransform(mirrored ? CGAffineTransform(scaleX: -1, y: 1) : .identity)
        CATransaction.commit()
        // 窗口的阴影跟着形状走
        window?.invalidateShadow()
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onDoubleClick()
        } else {
            window?.performDrag(with: event)
        }
    }

    override func scrollWheel(with event: NSEvent) {
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 8
        onScroll(delta)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        menuProvider()
    }
}
