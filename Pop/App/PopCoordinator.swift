import AppKit
import os

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
        /// 松开鼠标键时关闭圆盘（长按右键唤起、没打开「保持圆盘打开」时）
        var closesOnRelease = false
        /// 内容还在读取时就在这一格上松开了：读到后执行它
        var pendingSlot: Int?
        /// 按住鼠标键拖动时，事件拦截送来的最新指针位置（AppKit 屏幕坐标）
        var dragPoint: CGPoint?
        /// 这次按住期间收到的拖动事件数（写进日志，排查手势问题用）
        var dragCount = 0
        var content: ClassifiedContent?
        var ring: RingViewModel?
        /// 当前显示的列表面板
        var panel: Panel?
    }

    private var session: Session?
    private var pointerTimer: Timer?
    /// 手势日志：「控制台」里按子系统 io.github.whrss9527.pop、类别 gesture 过滤
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Pop", category: "gesture")
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
        let anchor = Self.appKitPoint(location)
        Self.log.notice("唤起：按下点 \(Int(anchor.x), privacy: .public), \(Int(anchor.y), privacy: .public)")
        begin(at: anchor, buttonHeld: true, closesOnRelease: settingsStore.settings.trigger.closesRingOnRelease)
    }

    func mouseTriggerDidDrag(to location: CGPoint) {
        guard session?.buttonHeld == true else { return }
        session?.dragPoint = Self.appKitPoint(location)
        session?.dragCount += 1
        updateHeldHover()
    }

    func mouseTriggerDidRelease(at location: CGPoint) {
        guard let current = session else { return }
        if current.buttonHeld {
            // 按松开的位置最后算一次指向哪一格
            session?.dragPoint = Self.appKitPoint(location)
            updateHeldHover()
        }
        session?.buttonHeld = false
        lastPointer = nil
        // 圆盘还没出来（内容还在读）或者已经换成了结果卡片：等内容读到后再决定（见 route）
        guard overlay.mode == .ring, let ring = current.ring else { return }
        let action = RingReleaseAction.decide(hovered: ring.pluginSlot(ring.hovered),
                                              selectable: ring.selectablePlugin(at: ring.hovered)?.id,
                                              isLoading: ring.isLoading,
                                              closesOnRelease: current.closesOnRelease)
        let dragCount = session?.dragCount ?? 0
        let offset = session?.dragPoint.map { "\(Int($0.x - current.anchor.x)), \(Int($0.y - current.anchor.y))" } ?? "没有拖动"
        let hovered = ring.hovered.map { "\($0)" } ?? "无"
        Self.log.notice("松开：拖动事件 \(dragCount, privacy: .public) 个，偏移 \(offset, privacy: .public)，指向第 \(hovered, privacy: .public) 格，\(String(describing: action), privacy: .public)")
        switch action {
        case .run(let pluginID):
            if let slot = ring.hovered {
                ring.commit(slot)
            }
            run(pluginID)
        case .runWhenLoaded(let slot):
            // 高亮停在这一格上，内容读到后执行
            stopPointerTracking()
            ring.setHovered(slot)
            session?.pendingSlot = slot
        case .close:
            if ring.isLoading {
                // 先收起圆盘；读到的内容命中直达规则（比如选中了外文）的话仍然直接出结果
                stopPointerTracking()
                overlay.hide()
            } else {
                endSession()
            }
        case .keepOpen:
            // 保持圆盘打开，改用点击选择
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

    /// 在 point 处显示一句提示（贴图上的复制、存储等）
    func showToast(_ message: String, at point: CGPoint) {
        endSession()
        overlay.showToast(message, anchor: point)
    }

    /// 在 point 处显示识别出的文字（贴图上的「识别文字」），可以接着复制、翻译
    func showRecognizedText(_ text: String, at point: CGPoint) {
        endSession()
        session = Session(anchor: point, pid: nil, sourceAppName: nil, buttonHeld: false, content: .empty)
        present(.card(TextRecognizer.card(title: "识别文字", text: text)))
    }

    // MARK: - 流程

    private func begin(at anchor: CGPoint, buttonHeld: Bool, closesOnRelease: Bool = false) {
        endSession()
        let app = NSWorkspace.shared.frontmostApplication
        let pid = app?.processIdentifier
        let newSession = Session(anchor: anchor, pid: pid, sourceAppName: app?.localizedName, buttonHeld: buttonHeld,
                                 closesOnRelease: closesOnRelease)
        session = newSession
        let sessionID = newSession.id

        // 读取比较慢（比如什么都没选中，要等剪贴板超时）时先亮出圆盘，给即时反馈；
        // 内容很快读到的话就直接进入下一步，不会闪一下圆盘。已经松开了右键、松开就关闭的话不用再亮出来。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let current = self.session, current.id == sessionID,
                      current.content == nil, current.ring == nil,
                      current.buttonHeld || !current.closesOnRelease else { return }
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
        guard let current = session else { return }
        // 读取期间就在某一格上松开了：那一格能处理读到的内容就直接执行
        if let slot = current.pendingSlot, let ring = current.ring {
            session?.pendingSlot = nil
            ring.update(content: content)
            if let plugin = ring.selectablePlugin(at: slot) {
                ring.commit(slot)
                run(plugin.id)
                return
            }
        }
        switch Router.decide(content, settings: settingsStore.settings, catalog: registry.catalog) {
        case .direct(let pluginID):
            run(pluginID)
        case .ring:
            if !current.buttonHeld && current.closesOnRelease {
                // 右键已经松开了：不再弹出圆盘
                endSession()
            } else if let ring = current.ring {
                ring.update(content: content)
                if !current.buttonHeld {
                    // 点击模式：高亮跟着指针
                    lastPointer = nil
                    startPointerTracking()
                    updatePointer()
                }
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
        // 圆盘出来之前可能已经拖动过了
        updateHeldHover()
        updatePointer()
    }

    private func run(_ pluginID: String) {
        guard let current = session, let plugin = registry.plugin(id: pluginID) else { return }
        let content = current.content ?? .empty
        guard plugin.info.canHandle(content) else { return }
        stopPointerTracking()
        if plugin.info.hidesOverlay {
            // 截图、取色要看清屏幕：立刻收起浮窗（不播放收起动画），结果出来后再显示在原来的位置
            overlay.hide(animated: false)
        }
        let context = PluginContext(settings: settingsStore.settings,
                                    openSettings: { [weak self] in self?.openSettings(nil) },
                                    sourceAppName: current.sourceAppName,
                                    anchor: current.anchor)
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
            let target = translationTarget(text: text, content: current.content, language: language)
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
        case .saveImage(let png, let name):
            do {
                _ = try ImageFiles.saveToDownloads(png, name: name)
                finish(toast: "已存到「下载」")
            } catch {
                present(.failure("存储失败：\(error.localizedDescription)"))
            }
        case .pinImage(let png):
            let anchor = session?.anchor ?? NSEvent.mouseLocation
            endSession()
            PinBoard.shared.pin(imageData: png, around: anchor)
        case .pinText(let text):
            let anchor = session?.anchor ?? NSEvent.mouseLocation
            endSession()
            PinBoard.shared.pin(text: text, around: anchor)
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

    /// 中文译成「中文译为」的语言，其他译成「外文译为」的语言。
    /// 优先看这段文字识别出的语种：截图翻译的文字和唤起时选中的内容不是同一段。
    private func translationTarget(text: String, content: ClassifiedContent?, language: String?) -> String {
        let settings = settingsStore.settings.translation
        let isChinese: Bool
        if let language {
            isChinese = language.hasPrefix("zh")
        } else if content?.text == text {
            isChinese = content?.kinds.contains(.chineseText) == true
        } else {
            isChinese = ScriptProfile(text).isChinese
        }
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

    /// 按住鼠标键时指向哪一格：看拖动位置相对按下点的方向（marking menu），圆盘因为靠近屏幕边缘被挪开也不受影响。
    /// 位置只用事件拦截送来的：拖动事件被 Pop 吞掉了，系统报告的指针位置（NSEvent.mouseLocation）不会跟着更新。
    private func updateHeldHover() {
        guard let current = session, current.buttonHeld, let ring = current.ring, overlay.mode == .ring,
              let point = current.dragPoint else { return }
        ring.updateHover(offset: CGVector(dx: point.x - current.anchor.x, dy: point.y - current.anchor.y))
    }

    /// 松开鼠标键之后（点击模式）：看指针在圆盘上的位置。按住时由 updateHeldHover 处理。
    private func updatePointer() {
        guard let current = session, !current.buttonHeld, let ring = current.ring, overlay.mode == .ring else { return }
        let mouse = NSEvent.mouseLocation
        // 指针没动就不覆盖键盘选择
        guard mouse != lastPointer else { return }
        lastPointer = mouse
        let center = overlay.ringCenter ?? current.anchor
        let offset = CGVector(dx: mouse.x - center.x, dy: mouse.y - center.y)
        let inside = (offset.dx * offset.dx + offset.dy * offset.dy).squareRoot() <= ring.geometry.outerRadius
        ring.updateHover(offset: inside ? offset : nil)
    }

    /// 事件拦截给的 Quartz 坐标（主屏左上角为原点）换成 AppKit 屏幕坐标
    private static func appKitPoint(_ location: CGPoint) -> CGPoint {
        ScreenGeometry.appKitPoint(fromQuartz: location, primaryScreenHeight: OverlayController.primaryScreenHeight)
    }

    private func handleRingClick() {
        lastPointer = nil
        updatePointer()
        guard let ring = session?.ring else { return }
        if let slot = ring.hovered, let plugin = ring.selectablePlugin(at: slot) {
            ring.commit(slot)
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
            if let slot = ring.hovered, let plugin = ring.selectablePlugin(at: slot) {
                ring.commit(slot)
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
                ring.commit(index)
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

/// 按住鼠标键唤起圆盘后松开时怎么办。纯逻辑，便于测试。
enum RingReleaseAction: Equatable {
    /// 执行指向的那一格
    case run(String)
    /// 内容还在读取时就指向了某一格：读到后执行这一格
    case runWhenLoaded(Int)
    /// 关闭圆盘
    case close
    /// 保持圆盘打开，改用点击选择
    case keepOpen

    /// hovered：指向的、放了插件的格子；selectable：那一格现在能执行的话是它的插件 ID
    static func decide(hovered: Int?, selectable: String?, isLoading: Bool, closesOnRelease: Bool) -> RingReleaseAction {
        if let selectable {
            return .run(selectable)
        }
        if isLoading, let hovered {
            return .runWhenLoaded(hovered)
        }
        return closesOnRelease ? .close : .keepOpen
    }
}
