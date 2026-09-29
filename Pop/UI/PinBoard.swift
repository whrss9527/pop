import AppKit
import SwiftUI

/// 贴在屏幕上的图片和文字：总在其他窗口前面，拖动移动，滚轮或双指捏合缩放（按住 ⌥ 滚动调透明度），
/// ⌘C 复制、⌘S 存到「下载」，双击或按 Esc 关闭，右键有更多操作。
@MainActor
final class PinBoard {
    static let shared = PinBoard()

    /// 在屏幕上某处显示一句提示
    var onToast: ((String, CGPoint) -> Void)?
    /// 识别出贴图里的文字后，在贴图旁边显示结果卡片
    var onRecognizedText: ((String, CGPoint) -> Void)?

    private var windows: [PinWindow] = []

    var count: Int { windows.count }

    /// 把图片贴在 point 附近（居中）；太大时缩小到屏幕的六成以内。
    @discardableResult
    func pin(imageData: Data, around point: CGPoint) -> Bool {
        guard let image = NSImage(data: imageData), image.size.width > 0, image.size.height > 0 else { return false }
        pin(image: image, around: point)
        return true
    }

    func pin(image: NSImage, around point: CGPoint) {
        let bounds = OverlayController.visibleFrame(containing: point)
        let size = ScreenGeometry.fitted(image.size, within: CGSize(width: bounds.width * 0.6, height: bounds.height * 0.6))
        let frame = ScreenGeometry.pinFrame(size: size, centeredAt: point, within: bounds)
        show(PinWindow(model: PinModel(content: .image(image)), baseSize: size, frame: frame))
    }

    /// 刚框选的截图：按原来的大小贴回框选的位置（松开鼠标时指针在框选区域的右下角）。
    func pin(capture: ScreenCapture.Capture, releasedAt point: CGPoint) {
        let screen = NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main
        let scale = max(screen?.backingScaleFactor ?? 2, 1)
        let size = CGSize(width: CGFloat(capture.image.width) / scale, height: CGFloat(capture.image.height) / scale)
        let bounds = screen?.frame ?? OverlayController.visibleFrame(containing: point)
        let fitted = ScreenGeometry.fitted(size, within: bounds.size)
        let frame = ScreenGeometry.pinFrame(size: fitted, bottomRightAt: point, within: bounds)
        let image = NSImage(cgImage: capture.image, size: fitted)
        show(PinWindow(model: PinModel(content: .image(image), png: capture.png), baseSize: fitted, frame: frame))
    }

    /// 把文字贴在 point 附近。太长的文字只显示开头，复制时仍然是全文。
    func pin(text: String, around point: CGPoint) {
        let model = PinModel(content: .text(text))
        let window = PinWindow(model: model, textAt: point)
        show(window)
    }

    func closeAll() {
        for window in windows {
            window.dismiss(animated: true)
        }
        windows.removeAll()
    }

    private func show(_ window: PinWindow) {
        window.onClose = { [weak self] closed in
            self?.windows.removeAll { $0 === closed }
        }
        windows.append(window)
        window.present()
    }
}

/// 一张贴图的内容和缩放比例
@MainActor
final class PinModel: ObservableObject {
    enum Content {
        case image(NSImage)
        case text(String)
    }

    let content: Content
    /// 截图时保存的原始 PNG，复制、存储时直接用
    private let originalPNG: Data?
    /// 1 表示刚贴上时的大小
    @Published var scale: CGFloat = 1

    init(content: Content, png: Data? = nil) {
        self.content = content
        originalPNG = png
    }

    var isImage: Bool {
        if case .image = content { return true }
        return false
    }

    var png: Data? {
        if let originalPNG { return originalPNG }
        guard case .image(let image) = content, let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    /// 文字贴图显示的内容
    static func displayedText(_ text: String) -> String {
        text.count > PinWindow.maxTextLength ? String(text.prefix(PinWindow.maxTextLength)) + "…" : text
    }
}

struct PinView: View {
    @ObservedObject var model: PinModel
    /// 文字贴图在原始大小下的排版宽度
    var textWidth: CGFloat = 0

    var body: some View {
        switch model.content {
        case .image(let image):
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(Rectangle().strokeBorder(Color.primary.opacity(0.22), lineWidth: 1))
        case .text(let text):
            let scale = model.scale
            Text(PinModel.displayedText(text))
                .font(.system(size: PinWindow.textFontSize * scale))
                .foregroundStyle(.primary)
                .frame(width: textWidth * scale, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(PinWindow.textPadding * scale)
                .glassSurface(RoundedRectangle(cornerRadius: 12 * scale, style: .continuous))
                .padding(PinWindow.shadowMargin)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// 贴图窗口：不激活 App（原来的 App 保持在前台），浮在普通窗口上面，所有桌面空间都能看到。
final class PinWindow: NSPanel {
    static let textFontSize: CGFloat = 14
    static let textPadding: CGFloat = 12
    static let maxTextWidth: CGFloat = 360
    static let maxTextLength = 1500
    /// 文字贴图四周给玻璃的阴影留的边距（不随缩放变化）
    static let shadowMargin: CGFloat = 16

    let model: PinModel
    /// 缩放为 1 时内容的大小（不含阴影边距）
    private let baseSize: CGSize
    private var margin: CGFloat { model.isImage ? 0 : Self.shadowMargin }
    private var opacity: CGFloat = 1
    var onClose: ((PinWindow) -> Void)?

    init(model: PinModel, baseSize: CGSize, frame: CGRect) {
        self.model = model
        self.baseSize = baseSize
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        configure(textWidth: 0)
    }

    /// 文字贴图：先按原始大小排版，量出大小后放在 point 附近
    init(model: PinModel, textAt point: CGPoint) {
        self.model = model
        let text: String
        if case .text(let value) = model.content {
            text = PinModel.displayedText(value)
        } else {
            text = ""
        }
        let width = Self.textWidth(for: text)
        let measuring = NSHostingView(rootView: PinView(model: model, textWidth: width))
        let fitting = measuring.fittingSize
        let bounds = OverlayController.visibleFrame(containing: point)
        let size = CGSize(width: ceil(fitting.width), height: min(ceil(fitting.height), bounds.height))
        baseSize = CGSize(width: size.width - Self.shadowMargin * 2, height: size.height - Self.shadowMargin * 2)
        let frame = ScreenGeometry.pinFrame(size: size, centeredAt: point, within: bounds)
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        configure(textWidth: width)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 文字按系统字体排版时需要的宽度，最宽 maxTextWidth
    static func textWidth(for text: String) -> CGFloat {
        let font = NSFont.systemFont(ofSize: textFontSize)
        let rect = (text as NSString).boundingRect(with: CGSize(width: maxTextWidth, height: .greatestFiniteMagnitude),
                                                   options: [.usesLineFragmentOrigin, .usesFontLeading],
                                                   attributes: [.font: font])
        return min(max(ceil(rect.width) + 4, 40), maxTextWidth)
    }

    private func configure(textWidth: CGFloat) {
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        // 图片用窗口自己的阴影；文字的玻璃自带阴影
        hasShadow = model.isImage
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        let container = PinContainerView(frame: CGRect(origin: .zero, size: frame.size))
        container.pin = self
        let hosting = NSHostingView(rootView: PinView(model: model, textWidth: textWidth))
        hosting.sizingOptions = []
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)
        contentView = container
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // MARK: - 显示和关闭

    func present() {
        alphaValue = 0
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Motion.seconds(0.18)
            self.animator().alphaValue = opacity
        }
    }

    func dismiss(animated: Bool) {
        guard animated else {
            orderOut(nil)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Motion.seconds(0.12)
            self.animator().alphaValue = 0
        } completionHandler: {
            MainActor.assumeIsolated {
                self.orderOut(nil)
            }
        }
    }

    @objc func closePin() {
        dismiss(animated: true)
        onClose?(self)
    }

    @objc private func closeAllPins() {
        PinBoard.shared.closeAll()
    }

    // MARK: - 缩放和透明度

    /// 贴图的中心（屏幕坐标）
    private var midPoint: CGPoint { CGPoint(x: frame.midX, y: frame.midY) }

    func zoom(by factor: CGFloat, around point: CGPoint) {
        setScale(min(max(model.scale * factor, 0.1), 8), around: point)
    }

    private func setScale(_ scale: CGFloat, around point: CGPoint) {
        guard scale != model.scale else { return }
        model.scale = scale
        let size = CGSize(width: (baseSize.width * scale).rounded(.up) + margin * 2,
                          height: (baseSize.height * scale).rounded(.up) + margin * 2)
        setFrame(ScreenGeometry.resized(frame, to: size, keeping: point), display: true)
        invalidateShadow()
    }

    func handleScroll(_ event: NSEvent) {
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY * 0.01 : event.scrollingDeltaY * 0.1
        guard delta != 0 else { return }
        if event.modifierFlags.contains(.option) {
            setOpacity(opacity + delta)
        } else {
            zoom(by: 1 + delta, around: NSEvent.mouseLocation)
        }
    }

    private func setOpacity(_ value: CGFloat) {
        opacity = min(max(value, 0.2), 1)
        alphaValue = opacity
    }

    @objc private func resetScale() {
        setScale(1, around: midPoint)
    }

    @objc private func chooseOpacity(_ sender: NSMenuItem) {
        setOpacity(CGFloat(sender.tag) / 100)
    }

    // MARK: - 复制、存储、识别文字

    @objc private func copyContent() {
        switch model.content {
        case .image:
            guard let png = model.png else { return }
            PasteboardWriter.copy(png: png)
        case .text(let text):
            PasteboardWriter.copy(text)
        }
        PinBoard.shared.onToast?("已复制", midPoint)
    }

    @objc private func saveImage() {
        guard let png = model.png else { return }
        do {
            _ = try ImageFiles.saveToDownloads(png, name: ImageFiles.timestampedName("Pop 贴图"))
            PinBoard.shared.onToast?("已存到「下载」", midPoint)
        } catch {
            PinBoard.shared.onToast?("存储失败", midPoint)
        }
    }

    @objc private func recognizeText() {
        guard case .image(let image) = model.content,
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let point = midPoint
        Task { @MainActor in
            switch await TextRecognizer.recognize(cgImage) {
            case .success(let text) where !text.isEmpty:
                PinBoard.shared.onRecognizedText?(text, point)
            case .success:
                PinBoard.shared.onToast?("没有识别到文字", point)
            case .failure(let error):
                PinBoard.shared.onToast?(error.message, point)
            }
        }
    }

    // MARK: - 键盘

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Esc
            closePin()
            return
        }
        super.keyDown(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        closePin()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers.contains(.command), !modifiers.contains(.control), !modifiers.contains(.option),
              let key = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }
        switch key {
        case "c":
            copyContent()
        case "s" where model.isImage:
            saveImage()
        case "w":
            closePin()
        case "0":
            resetScale()
        case "=", "+":
            zoom(by: 1.25, around: midPoint)
        case "-":
            zoom(by: 0.8, around: midPoint)
        default:
            return super.performKeyEquivalent(with: event)
        }
        return true
    }

    // MARK: - 右键菜单

    func contextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        addItem(to: menu, "复制", #selector(copyContent), key: "c")
        if model.isImage {
            addItem(to: menu, "存到「下载」", #selector(saveImage), key: "s")
            addItem(to: menu, "识别文字", #selector(recognizeText))
        }
        menu.addItem(.separator())
        addItem(to: menu, "恢复大小", #selector(resetScale), key: "0")
        let opacityItem = NSMenuItem(title: "透明度", action: nil, keyEquivalent: "")
        let opacityMenu = NSMenu()
        for percent in [100, 80, 60, 40] {
            let item = NSMenuItem(title: "\(percent)%", action: #selector(chooseOpacity(_:)), keyEquivalent: "")
            item.target = self
            item.tag = percent
            item.state = Int((opacity * 100).rounded()) == percent ? .on : .off
            opacityMenu.addItem(item)
        }
        opacityItem.submenu = opacityMenu
        menu.addItem(opacityItem)
        menu.addItem(.separator())
        addItem(to: menu, "关闭", #selector(closePin), key: "w")
        if PinBoard.shared.count > 1 {
            addItem(to: menu, "关闭全部贴图", #selector(closeAllPins))
        }
        return menu
    }

    private func addItem(to menu: NSMenu, _ title: String, _ action: Selector, key: String = "") {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
    }
}

/// 贴图窗口的内容视图：鼠标事件都由它处理（拖动、双击关闭、缩放、右键菜单），不交给里面的 SwiftUI 视图。
final class PinContainerView: NSView {
    weak var pin: PinWindow?

    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point) == nil ? nil : self
    }

    /// Pop 不会成为前台 App，贴图收到的每一次点击都是「第一下」：直接开始拖动
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount >= 2 {
            pin?.closePin()
            return
        }
        pin?.makeKey()
        window?.performDrag(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        pin?.handleScroll(event)
    }

    override func magnify(with event: NSEvent) {
        pin?.zoom(by: 1 + event.magnification, around: NSEvent.mouseLocation)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        pin?.contextMenu()
    }
}
