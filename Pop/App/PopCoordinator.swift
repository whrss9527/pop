import AppKit

/// 一次唤起的完整流程：读取选中内容 → 分类 → 命中直达规则就直接执行，否则弹出圆盘 → 执行插件 → 展示结果。
@MainActor
final class PopCoordinator: MouseTriggerDelegate {
    var openSettings: (SettingsTab?) -> Void = { _ in }
    var isPaused = false

    private let settingsStore: SettingsStore
    private let registry: PluginRegistry
    private let overlay: OverlayController
    private let downloads: TranslationDownloadRequest
    private let clipboard: ClipboardService
    private let reader = SelectionReader()

    private enum Panel {
        case chooser
        case clipboard
    }

    private struct Session {
        let id = UUID()
        /// 唤起点（AppKit 屏幕坐标）
        let anchor: CGPoint
        let pid: pid_t?
        /// 唤起时前台 App 的名字（收集箱记录来源用）
        let sourceAppName: String?
        /// 鼠标键是否还按着：按着时用「划一下再松开」选择，松开后改为点击选择
        var buttonHeld: Bool
        var content: ClassifiedContent?
        var ring: RingViewModel?
        /// 当前显示的列表面板
        var panel: Panel?
    }

    private var session: Session?
    private var pointerTimer: Timer?
    private var lastPointer: CGPoint?

    init(settingsStore: SettingsStore, registry: PluginRegistry, overlay: OverlayController,
         downloads: TranslationDownloadRequest, clipboard: ClipboardService) {
        self.settingsStore = settingsStore
        self.registry = registry
        self.overlay = overlay
        self.downloads = downloads
        self.clipboard = clipboard
        overlay.onDismiss = { [weak self] in
            self?.endSession()
        }
        overlay.onRingKey = { [weak self] event in
            self?.handleRingKey(event) ?? false
        }
        overlay.onRingClick = { [weak self] in
            self?.handleRingClick()
        }
    }

    // MARK: - 唤起入口

    func mouseTriggerShouldBegin() -> Bool {
        // 在卡片上点右键：交给卡片自己处理（比如剪贴板历史的右键菜单）
        if overlay.mode == .card, overlay.contains(NSEvent.mouseLocation) {
            return false
        }
        if overlay.isVisible || session != nil {
            endSession()
        }
        guard !isPaused else { return false }
        if let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
           settingsStore.settings.trigger.excludedBundleIDs.contains(bundleID) {
            return false
        }
        return true
    }

    func mouseTriggerDidActivate(at location: CGPoint) {
        let anchor = ScreenGeometry.appKitPoint(fromQuartz: location, primaryScreenHeight: OverlayController.primaryScreenHeight)
        begin(at: anchor, buttonHeld: true)
    }

    func mouseTriggerDidDrag(to location: CGPoint) {
        updatePointer()
    }

    func mouseTriggerDidRelease(at location: CGPoint) {
        guard session != nil else { return }
        session?.buttonHeld = false
        lastPointer = nil
        // 还在读取内容时松开：等圆盘出来后直接进入点击模式
        guard overlay.mode == .ring, let ring = session?.ring else { return }
        if let plugin = ring.selectablePlugin(at: ring.hovered) {
            run(plugin.id)
        } else {
            // 在圆心附近或不可用的格子上松开：保持圆盘打开，改用点击选择
            ring.setHovered(nil)
            updatePointer()
        }
    }

    /// 键盘快捷键唤起：再按一次关闭
    func activateFromHotKey() {
        if overlay.isVisible || session != nil {
            endSession()
            return
        }
        guard !isPaused else { return }
        begin(at: NSEvent.mouseLocation, buttonHeld: false)
    }

    /// 剪贴板历史快捷键：不读取选中内容，直接打开历史面板；再按一次关闭
    func showClipboardHistoryFromHotKey() {
        if overlay.isVisible || session != nil {
            let wasShowingHistory = session?.panel == .clipboard
            endSession()
            if wasShowingHistory { return }
        }
        guard !isPaused else { return }
        let app = NSWorkspace.shared.frontmostApplication
        session = Session(anchor: NSEvent.mouseLocation, pid: app?.processIdentifier, sourceAppName: app?.localizedName,
                          buttonHeld: false, content: .empty)
        presentClipboardHistory()
    }

    func endSession() {
        stopPointerTracking()
        session = nil
        if overlay.isVisible {
            overlay.hide()
        }
    }

    // MARK: - 流程

    private func begin(at anchor: CGPoint, buttonHeld: Bool) {
        endSession()
        let app = NSWorkspace.shared.frontmostApplication
        let pid = app?.processIdentifier
        let newSession = Session(anchor: anchor, pid: pid, sourceAppName: app?.localizedName, buttonHeld: buttonHeld)
        session = newSession
        let sessionID = newSession.id

        // 读取比较慢（比如什么都没选中，要等剪贴板超时）时先亮出圆盘，给即时反馈；
        // 内容很快读到的话就直接进入下一步，不会闪一下圆盘。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let current = self.session, current.id == sessionID,
                      current.content == nil, current.ring == nil else { return }
                self.showRing(content: nil)
            }
        }

        Task { [weak self] in
            guard let self else { return }
            let raw = await self.reader.read(pid: pid)
            guard self.session?.id == sessionID else { return }
            let content = ContentClassifier.classify(raw)
            self.session?.content = content
            self.route(content)
        }
    }

    private func route(_ content: ClassifiedContent) {
        switch Router.decide(content, settings: settingsStore.settings, catalog: registry.catalog) {
        case .direct(let pluginID):
            run(pluginID)
        case .ring:
            if let ring = session?.ring {
                ring.update(content: content)
            } else {
                showRing(content: content)
            }
        }
    }

    private func showRing(content: ClassifiedContent?) {
        guard let current = session else { return }
        let settings = settingsStore.settings
        let ring = RingViewModel(layout: settings.ring, catalog: registry.catalog,
                                 installed: Set(settings.installedPlugins), content: content)
        session?.ring = ring
        session?.panel = nil
        overlay.showRing(ring, center: current.anchor)
        lastPointer = nil
        startPointerTracking()
        updatePointer()
    }

    private func run(_ pluginID: String) {
        guard let current = session, let plugin = registry.plugin(id: pluginID) else { return }
        let content = current.content ?? .empty
        guard plugin.info.canHandle(content) else { return }
        stopPointerTracking()
        if plugin.info.hidesOverlay {
            // 截图、取色要看清屏幕：先收起浮窗，结果出来后再显示在原来的位置
            overlay.hide()
        }
        let context = PluginContext(settings: settingsStore.settings,
                                    openSettings: { [weak self] in self?.openSettings(nil) },
                                    sourceAppName: current.sourceAppName)
        let sessionID = current.id
        Task { [weak self] in
            let outcome = await plugin.run(content, context: context)
            guard let self, self.session?.id == sessionID else { return }
            self.present(outcome)
        }
    }

    private func present(_ outcome: PluginOutcome) {
        guard let current = session else { return }
        session?.panel = nil
        switch outcome {
        case .done(let toast):
            session = nil
            if let toast {
                overlay.showToast(toast, anchor: current.anchor)
            } else {
                overlay.hide()
            }
        case .card(let card):
            overlay.showCard(ResultCardView(card: card,
                                            onAction: { [weak self] action in self?.perform(action) },
                                            onMore: moreAction(for: current),
                                            onClose: { [weak self] in self?.endSession() }),
                             anchor: current.anchor)
        case .translate(let text, let language):
            let target = translationTarget(content: current.content, language: language)
            let model = TranslationModel(text: text, sourceLanguage: language, targetLanguage: target)
            overlay.showCard(TranslationCardView(model: model,
                                                 canReplace: Self.isTextSelection(current.content) && current.content?.text == text,
                                                 onAction: { [weak self] action in self?.perform(action) },
                                                 onMore: moreAction(for: current),
                                                 onDownload: { [weak self] in self?.downloadLanguagePack(source: language, target: target) },
                                                 onClose: { [weak self] in self?.endSession() }),
                             anchor: current.anchor)
        case .replace(let text):
            replaceSelection(with: text)
        case .showAllPlugins:
            presentChooser()
        case .showClipboardHistory:
            presentClipboardHistory()
        case .failure(let message):
            overlay.showCard(ResultCardView(card: ResultCard(title: "没能完成", body: message),
                                            onAction: { [weak self] action in self?.perform(action) },
                                            onMore: moreAction(for: current),
                                            onClose: { [weak self] in self?.endSession() }),
                             anchor: current.anchor)
        }
    }

    /// 结果卡片上的按钮
    private func perform(_ action: CardAction) {
        switch action {
        case .copy(let text):
            copy(text)
        case .replace(let text):
            replaceSelection(with: text)
        case .open(let url):
            endSession()
            NSWorkspace.shared.open(url)
        case .reveal(let url):
            endSession()
            NSWorkspace.shared.activateFileViewerSelecting([url])
        case .copyImage(let png):
            PasteboardWriter.copy(png: png)
            finish(toast: "已复制图片")
        case .translate(let text):
            present(.translate(text: text, language: ContentClassifier.dominantLanguage(text)))
        }
    }

    /// 「全部功能」：列出所有能处理当前内容的已安装功能
    private func presentChooser() {
        guard let current = session else { return }
        stopPointerTracking()
        let content = current.content ?? .empty
        let settings = settingsStore.settings
        let plugins = registry.catalog.filter { info in
            info.id != BuiltinPluginID.allPlugins && settings.isInstalled(info.id) && info.canHandle(content)
        }
        let model = PluginChooserModel(plugins: plugins)
        model.onRun = { [weak self] info in
            self?.run(info.id)
        }
        session?.panel = .chooser
        overlay.showCard(PluginChooserView(model: model, onClose: { [weak self] in self?.endSession() }),
                         anchor: current.anchor,
                         keyHandler: { event in model.handleKey(event) })
    }

    private func presentClipboardHistory() {
        guard let current = session else { return }
        stopPointerTracking()
        let model = ClipboardHistoryModel(service: clipboard)
        model.onPaste = { [weak self] item in
            self?.pasteFromHistory(item)
        }
        model.onOpenSettings = { [weak self] in
            self?.endSession()
            self?.openSettings(.clipboard)
        }
        session?.panel = .clipboard
        overlay.showCard(ClipboardHistoryView(model: model, onClose: { [weak self] in self?.endSession() }),
                         anchor: current.anchor,
                         keyHandler: { event in model.handleKey(event) })
    }

    private func pasteFromHistory(_ item: ClipboardItem) {
        // 先收起浮窗，键盘焦点回到原来的 App，再粘贴
        endSession()
        clipboard.paste(item)
    }

    private func replaceSelection(with text: String) {
        endSession()
        Paster.replaceSelection(with: text)
    }

    /// 结果卡片上的「更多功能」：切回圆盘，对同一份内容换个功能处理。
    private func moreAction(for current: Session) -> (() -> Void)? {
        guard current.content?.isEmpty == false else { return nil }
        return { [weak self] in
            guard let self, self.session != nil else { return }
            self.session?.buttonHeld = false
            self.showRing(content: self.session?.content)
        }
    }

    private static func isTextSelection(_ content: ClassifiedContent?) -> Bool {
        if case .text = content?.selection {
            return true
        }
        return false
    }

    private func translationTarget(content: ClassifiedContent?, language: String?) -> String {
        let settings = settingsStore.settings.translation
        let isChinese = content?.kinds.contains(.chineseText) == true || language?.hasPrefix("zh") == true
        return isChinese ? settings.chineseTarget : settings.foreignTarget
    }

    private func copy(_ text: String) {
        PasteboardWriter.copy(text)
        finish(toast: "已复制")
    }

    /// 结束这次唤起，在原来的位置显示一句提示
    private func finish(toast: String) {
        let anchor = session?.anchor ?? NSEvent.mouseLocation
        stopPointerTracking()
        session = nil
        overlay.showToast(toast, anchor: anchor)
    }

    private func downloadLanguagePack(source: String?, target: String) {
        downloads.request(source: source, target: target)
        endSession()
        openSettings(.translation)
    }

    // MARK: - 圆盘交互

    private func startPointerTracking() {
        guard pointerTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updatePointer()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pointerTimer = timer
    }

    private func stopPointerTracking() {
        pointerTimer?.invalidate()
        pointerTimer = nil
        lastPointer = nil
    }

    private func updatePointer() {
        guard let current = session, let ring = current.ring, overlay.mode == .ring else { return }
        let mouse = NSEvent.mouseLocation
        // 指针没动就不覆盖键盘选择
        guard mouse != lastPointer else { return }
        lastPointer = mouse
        if current.buttonHeld {
            // 按住拖动：看相对按下点的方向（marking menu），圆盘因为靠近屏幕边缘被挪开也不受影响
            ring.updateHover(offset: CGVector(dx: mouse.x - current.anchor.x, dy: mouse.y - current.anchor.y))
        } else {
            // 点击模式：看指针在圆盘上的位置
            let center = overlay.ringCenter ?? current.anchor
            let offset = CGVector(dx: mouse.x - center.x, dy: mouse.y - center.y)
            let inside = (offset.dx * offset.dx + offset.dy * offset.dy).squareRoot() <= ring.geometry.outerRadius
            ring.updateHover(offset: inside ? offset : nil)
        }
    }

    private func handleRingClick() {
        lastPointer = nil
        updatePointer()
        guard let ring = session?.ring else { return }
        if let plugin = ring.selectablePlugin(at: ring.hovered) {
            run(plugin.id)
        } else if ring.hovered == nil {
            // 点在圆心：关闭
            endSession()
        }
    }

    /// 数字键 1-9、0 直接选对应格子；方向键移动高亮；回车执行。
    private func handleRingKey(_ event: NSEvent) -> Bool {
        guard let ring = session?.ring else { return false }
        switch event.keyCode {
        case 36, 76: // Return / Enter
            if let plugin = ring.selectablePlugin(at: ring.hovered) {
                run(plugin.id)
            }
            return true
        case 123, 126: // ← ↑：逆时针
            ring.setHovered(step(ring, by: -1))
            return true
        case 124, 125: // → ↓：顺时针
            ring.setHovered(step(ring, by: 1))
            return true
        default:
            break
        }
        if let characters = event.charactersIgnoringModifiers, characters.count == 1, let digit = Int(characters) {
            let index = digit == 0 ? 9 : digit - 1
            if let plugin = ring.selectablePlugin(at: index) {
                run(plugin.id)
            }
            return true
        }
        return false
    }

    private func step(_ ring: RingViewModel, by delta: Int) -> Int {
        let count = max(ring.slots.count, 1)
        let start = ring.hovered ?? (delta > 0 ? -1 : 0)
        return ((start + delta) % count + count) % count
    }
}
