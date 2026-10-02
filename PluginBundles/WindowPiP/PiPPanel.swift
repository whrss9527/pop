import AppKit
@testable import Pop

/// 放小窗的面板：在普通窗口上面，切到别的桌面、全屏的 App 里也在；不抢焦点，可以拖动
final class PiPPanel: NSPanel {
    let item: PiPWindows.Item
    let pip: PiPView
    /// 正在抓的画面（演示时没有）
    var stream: PiPStream?
    /// 换大小以后，等一会儿再按新的大小抓
    var resizeTask: Task<Void, Never>?

    init(item: PiPWindows.Item, frame: CGRect) {
        self.item = item
        pip = PiPView(title: item.displayTitle)
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
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        contentView = pip
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var canBecomeKey: Bool { false }
}

/// 小窗里的画面：圆角，指针移上来时左上角「回到窗口」、右上角「关闭」，下面写着是哪个窗口
final class PiPView: NSView {
    /// 抓到的画面放在这一层上（按原来窗口的比例铺满）
    let contentLayer = CALayer()
    var onDoubleClick: () -> Void = {}
    var onClose: () -> Void = {}
    var onBack: () -> Void = {}
    var onScroll: (CGFloat) -> Void = { _ in }
    var menuProvider: () -> NSMenu = { NSMenu() }
    /// 演示时一直显示按钮
    var showsControls = false {
        didSet { setControlsVisible(showsControls, animated: false) }
    }

    private let closeButton: NSButton
    private let backButton: NSButton
    private let titleLabel: NSTextField
    private let titleBackground = CAGradientLayer()
    private let endedLabel: NSTextField

    init(title: String) {
        closeButton = PiPView.makeButton(symbol: "xmark", help: String(localized: "关闭小窗"))
        backButton = PiPView.makeButton(symbol: "arrow.up.forward.app", help: String(localized: "回到窗口"))
        titleLabel = NSTextField(labelWithString: title)
        endedLabel = NSTextField(labelWithString: String(localized: "原来的窗口关掉了"))
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.85).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
        contentLayer.contentsGravity = .resizeAspect
        layer?.addSublayer(contentLayer)
        titleBackground.colors = [NSColor.black.withAlphaComponent(0).cgColor, NSColor.black.withAlphaComponent(0.6).cgColor]
        titleBackground.startPoint = CGPoint(x: 0.5, y: 1)
        titleBackground.endPoint = CGPoint(x: 0.5, y: 0)
        layer?.addSublayer(titleBackground)

        titleLabel.font = .systemFont(ofSize: 11, weight: .medium)
        titleLabel.textColor = .white
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        endedLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        endedLabel.textColor = .white
        endedLabel.alignment = .center
        endedLabel.isHidden = true
        for view in [titleLabel, endedLabel, backButton, closeButton] {
            addSubview(view)
        }
        closeButton.target = self
        closeButton.action = #selector(closeClicked)
        backButton.target = self
        backButton.action = #selector(backClicked)
        setControlsVisible(false, animated: false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static func makeButton(symbol: String, help: String) -> NSButton {
        let button = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: help) ?? NSImage(), target: nil, action: nil)
        button.isBordered = false
        button.imageScaling = .scaleProportionallyDown
        button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 10, weight: .bold)
        button.contentTintColor = .white
        button.toolTip = help
        button.wantsLayer = true
        button.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        button.layer?.cornerRadius = 11
        return button
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        contentLayer.frame = bounds
        titleBackground.frame = CGRect(x: 0, y: 0, width: bounds.width, height: 30)
        CATransaction.commit()
        backButton.frame = CGRect(x: 8, y: bounds.height - 30, width: 22, height: 22)
        closeButton.frame = CGRect(x: bounds.width - 30, y: bounds.height - 30, width: 22, height: 22)
        titleLabel.frame = CGRect(x: 10, y: 7, width: max(0, bounds.width - 20), height: 15)
        endedLabel.frame = CGRect(x: 8, y: bounds.midY - 10, width: max(0, bounds.width - 16), height: 20)
        // 窗口的阴影跟着圆角走
        window?.invalidateShadow()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        setControlsVisible(true, animated: true)
    }

    override func mouseExited(with event: NSEvent) {
        setControlsVisible(showsControls, animated: true)
    }

    private func setControlsVisible(_ visible: Bool, animated: Bool) {
        let alpha: CGFloat = visible ? 1 : 0
        let views: [NSView] = [backButton, closeButton, titleLabel]
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Motion.seconds(0.15)
                views.forEach { $0.animator().alphaValue = alpha }
            }
        } else {
            views.forEach { $0.alphaValue = alpha }
        }
        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        titleBackground.opacity = Float(alpha)
        CATransaction.commit()
    }

    /// 原来的窗口没了（或者抓画面被停了）：画面暗下去，中间写一句
    func showEnded(_ text: String) {
        contentLayer.opacity = 0.35
        endedLabel.stringValue = text
        endedLabel.isHidden = false
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

    @objc private func closeClicked() {
        onClose()
    }

    @objc private func backClicked() {
        onBack()
    }
}
