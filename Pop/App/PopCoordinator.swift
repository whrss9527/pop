import AppKit
import Combine
import os

/// 一次唤起的完整流程：读取选中内容 → 分类 → 命中直达规则就直接执行，否则弹出圆盘 → 执行插件 → 展示结果。
@MainActor
final class PopCoordinator: MouseTriggerDelegate {
    var openSettings: (SettingsTab?) -> Void = { _ in }
    /// 打开设置里的插件库（演示截图用）
    var openPluginLibrary: () -> Void = {}
    /// 插件包的安装和卸载（「全部功能」里装没装的插件用）
    weak var pluginManager: PluginManager?
    /// 「全部功能」里正在装的插件包：装好时还开着「全部功能」就直接用
    private var chooserInstall: AnyCancellable?
    var isPaused = false

    private let settingsStore: SettingsStore
    private let registry: PluginRegistry
    private let overlay: OverlayController
    private let downloads: TranslationDownloadRequest
    private let clipboard: ClipboardService
    private let reader = SelectionReader()
    /// 选中文字后弹出的工具条
    private let toolbar = SelectionToolbarController()
    /// 选完文字到读出选区之间又有新的操作时作废
    private var toolbarGeneration = 0
    /// 工具条对应的选区；点工具条上的功能时用它
    private var toolbarContext: ToolbarContext?
    /// 上一次弹出工具条的选区：读不到选区位置时，同一段文字不再弹（比如拖的是窗口，选区还是之前那一段）
    private var lastToolbarSelection: (pid: pid_t, text: String)?

    private struct ToolbarContext {
        let content: ClassifiedContent
        let pid: pid_t
        let appName: String?
        let bundleID: String?
        /// 结果卡片从这里弹出来
        let anchor: CGPoint
    }

    private enum Panel {
        case chooser
        case clipboard
    }

    private struct Session {
        let id = UUID()
        /// 唤起点（AppKit 屏幕坐标）；圆盘靠边挪开时改成圆盘中心（见 followRingWithPointer）
        var anchor: CGPoint
        let pid: pid_t?
        /// 唤起时前台 App 的名字（收集箱记录来源用）
        let sourceAppName: String?
        /// 唤起时前台 App 的 Bundle ID（选用这个 App 专用的圆盘布局）
        var bundleID: String? = nil
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
        /// 内容是 pop:// 链接带来的，不是在前台 App 里选中的：没有原文可以替换
        var fromLink = false
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
        toolbar.onRun = { [weak self] pluginID in
            self?.runFromToolbar(pluginID)
        }
        toolbar.onMore = { [weak self] in
            self?.showRingFromToolbar()
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

    /// 功能的快捷键：读取选中的内容后直接执行这个功能，不弹圆盘。
    /// 不需要选中内容的功能（截图翻译、屏幕取色……）不读取，马上执行。
    func runFromHotKey(pluginID: String) {
        if overlay.isVisible || session != nil {
            endSession()
        }
        guard settingsStore.settings.isInstalled(pluginID) else { return }
        runReadingSelection(pluginID)
    }

    /// pop:// 链接执行功能：带了文字或文件就处理它们，没带就和功能快捷键一样处理当前选中的内容。
    /// 链接点名要用的功能，关掉了（不在圆盘上）的也照样执行。
    func runFromLink(pluginID: String, text: String?, files: [URL]) {
        if overlay.isVisible || session != nil {
            endSession()
        }
        let anchor = NSEvent.mouseLocation
        guard !isPaused else {
            overlay.showToast(String(localized: "Pop 已暂停"), anchor: anchor)
            return
        }
        guard let plugin = registry.plugin(id: pluginID) else {
            overlay.showToast(String(localized: "没有「\(pluginID)」这个功能"), anchor: anchor)
            return
        }
        guard text != nil || !files.isEmpty else {
            runReadingSelection(pluginID)
            return
        }
        let raw: SelectionContent = files.isEmpty ? .text(text ?? "") : .files(files)
        let content = ContentClassifier.classify(raw)
        guard plugin.info.canHandle(content) else {
            overlay.showToast(String(localized: "「\(plugin.info.name)」处理不了链接里的内容"), anchor: anchor)
            return
        }
        // 问之前先记下前台 App：弹出确认框时 Pop 会到前台
        let app = NSWorkspace.shared.frontmostApplication
        // 链接可能来自网页：用户自己写的 Shell 脚本、快捷指令插件先问一下再处理链接里的内容
        if let manifestPlugin = plugin as? ManifestPlugin,
           [.shell, .shortcut].contains(manifestPlugin.manifest.action.type),
           !Self.confirmLinkRun(plugin.info.name, content: text ?? files.map { $0.path(percentEncoded: false) }.joined(separator: "\n")) {
            return
        }
        session = Session(anchor: anchor, pid: app?.processIdentifier, sourceAppName: app?.localizedName,
                          bundleID: app?.bundleIdentifier, buttonHeld: false, content: content, fromLink: true)
        run(pluginID)
    }

    private static func confirmLinkRun(_ name: String, content: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = String(localized: "用「\(name)」处理链接里的内容？")
        let excerpt = content.count > 300 ? String(content.prefix(300)) + "…" : content
        alert.informativeText = String(localized: "一个 pop:// 链接要用这个插件处理下面的内容。它会运行你写的脚本或快捷指令，不认识这个链接的话点「取消」。\n\n\(excerpt)")
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "运行"))
        alert.addButton(withTitle: String(localized: "取消"))
        NSApp.activate()
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// 读取选中的内容后执行（功能快捷键、不带内容的链接）
    private func runReadingSelection(_ pluginID: String) {
        guard !isPaused, let plugin = registry.plugin(id: pluginID) else { return }
        let app = NSWorkspace.shared.frontmostApplication
        let pid = app?.processIdentifier
        let newSession = Session(anchor: NSEvent.mouseLocation, pid: pid, sourceAppName: app?.localizedName,
                                 bundleID: app?.bundleIdentifier, buttonHeld: false)
        session = newSession
        if plugin.info.accepts.isEmpty && !plugin.info.optionalContent {
            session?.content = .empty
            run(pluginID)
            return
        }
        let sessionID = newSession.id
        Task { [weak self] in
            guard let self else { return }
            let raw = await self.reader.read(pid: pid)
            guard self.session?.id == sessionID else { return }
            if self.askForFolderAccessIfNeeded(raw) { return }
            let content = await ContentClassifier.classifyOffMain(raw, catalog: self.registry.catalog)
            guard self.session?.id == sessionID else { return }
            self.session?.content = content
            if plugin.info.canHandle(content) {
                self.run(pluginID)
            } else {
                self.finish(toast: content.isEmpty ? String(localized: "没有选中内容") : String(localized: "「\(plugin.info.name)」处理不了选中的内容"))
            }
        }
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
        hideToolbar()
        session = nil
        if overlay.isVisible {
            overlay.hide()
        }
    }

    // MARK: - 选中文字后的工具条

    /// 拖着选了一段、双击或三击之后（point 是鼠标抬起的地方，AppKit 坐标）：读到选中的文字就在旁边弹出工具条
    func selectionMade(at point: CGPoint, clickCount: Int) {
        let settings = settingsStore.settings
        guard settings.toolbar.enabled, !isPaused, session == nil,
              let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        if let bundleID = app.bundleIdentifier,
           settings.toolbar.excludedBundleIDs.contains(bundleID) || settings.trigger.excludedBundleIDs.contains(bundleID) {
            return
        }
        hideToolbar()
        let generation = toolbarGeneration
        let pid = app.processIdentifier
        Task { [weak self] in
            // 等 App 把选区更新好
            try? await Task.sleep(nanoseconds: 60_000_000)
            guard let self, generation == self.toolbarGeneration else { return }
            guard let selection = await self.reader.readAccessible(pid: pid),
                  generation == self.toolbarGeneration, self.session == nil else { return }
            let bounds = selection.bounds.map {
                SelectionToolbarLogic.appKitRect(fromQuartz: $0, primaryScreenHeight: OverlayController.primaryScreenHeight)
            }
            if let bounds {
                guard SelectionToolbarLogic.selection(bounds, isNear: point) else { return }
            } else if clickCount < 2, let last = self.lastToolbarSelection, last.pid == pid, last.text == selection.text {
                return
            }
            let content = await ContentClassifier.classifyOffMain(.text(selection.text), catalog: self.registry.catalog)
            guard generation == self.toolbarGeneration, self.session == nil else { return }
            self.showToolbar(content: content, selection: bounds, pointer: point, pid: pid, appName: app.localizedName,
                             bundleID: app.bundleIdentifier)
        }
    }

    /// 按了键、点了别处、换了 App：收起工具条
    func hideToolbar() {
        toolbarGeneration += 1
        if toolbar.isVisible {
            toolbar.hide()
        }
    }

    private func showToolbar(content: ClassifiedContent, selection: CGRect?, pointer: CGPoint, pid: pid_t, appName: String?,
                             bundleID: String?) {
        let settings = settingsStore.settings
        let items = SelectionToolbarLogic.items(layout: settings.ring(for: bundleID), catalog: registry.catalog,
                                                installed: Set(settings.installedPlugins), content: content)
        guard !items.isEmpty, let text = content.text else { return }
        toolbar.show(items: items, selection: selection, pointer: pointer)
        let frame = toolbar.frame ?? CGRect(origin: pointer, size: .zero)
        toolbarContext = ToolbarContext(content: content, pid: pid, appName: appName, bundleID: bundleID,
                                        anchor: CGPoint(x: frame.midX, y: frame.minY + 8))
        lastToolbarSelection = (pid, text)
    }

    /// 点了工具条上的功能：用读到的选区执行，结果卡片从工具条那里弹出来
    private func runFromToolbar(_ pluginID: String) {
        guard let context = toolbarContext else { return }
        endSession()
        session = Session(anchor: context.anchor, pid: context.pid, sourceAppName: context.appName, bundleID: context.bundleID,
                          buttonHeld: false, content: context.content)
        run(pluginID)
    }

    /// 点了工具条上的「更多」：在这里打开完整的圆盘，点一下选
    private func showRingFromToolbar() {
        guard let context = toolbarContext else { return }
        endSession()
        session = Session(anchor: NSEvent.mouseLocation, pid: context.pid, sourceAppName: context.appName,
                          bundleID: context.bundleID, buttonHeld: false, content: context.content)
        showRing(content: context.content)
    }

    /// 演示截图用：假装在 selection 这里选中了 text
    func showToolbarForDemo(text: String, selection: CGRect) {
        endSession()
        showToolbar(content: ContentClassifier.classify(.text(text)), selection: selection,
                    pointer: CGPoint(x: selection.maxX, y: selection.midY), pid: 0, appName: nil, bundleID: nil)
    }

    /// 在 point 处显示一句提示（贴图上的复制、存储等）
    func showToast(_ message: String, at point: CGPoint) {
        endSession()
        overlay.showToast(message, anchor: point)
    }

    /// 录屏录好了：没在用 Pop 的话在指针旁边弹出卡片，可以接着转成 GIF、截取一段；正在用就只在访达里选中
    func recordingFinished(_ result: Result<ScreenRecording.Clip, ScreenRecording.Failure>) {
        switch result {
        case .failure(let failure):
            guard session == nil else { return }
            showToast(failure.message, at: NSEvent.mouseLocation)
        case .success(let clip):
            guard session == nil else {
                NSWorkspace.shared.activateFileViewerSelecting([clip.url])
                return
            }
            let point = NSEvent.mouseLocation
            session = Session(anchor: point, pid: nil, sourceAppName: nil, buttonHeld: false, content: .empty)
            present(.card(ScreenRecording.card(clip)))
        }
    }

    /// 滚动截图拼好了：在指针旁边弹出卡片（正在用 Pop 的话先收起）
    func scrollCaptureFinished(_ result: Result<ResultCard, ScrollCapture.Failure>) {
        let point = NSEvent.mouseLocation
        switch result {
        case .failure(let failure):
            showToast(failure.message, at: point)
        case .success(let card):
            endSession()
            session = Session(anchor: point, pid: nil, sourceAppName: nil, buttonHeld: false, content: .empty)
            present(.card(card))
        }
    }

    /// 在 point 处显示识别出的文字（贴图上的「识别文字」），可以接着复制、翻译
    func showRecognizedText(_ text: String, at point: CGPoint) {
        endSession()
        session = Session(anchor: point, pid: nil, sourceAppName: nil, buttonHeld: false, content: .empty)
        present(.card(TextRecognizer.card(title: String(localized: "识别文字"), text: text)))
    }

    // MARK: - 流程

    private func begin(at anchor: CGPoint, buttonHeld: Bool, closesOnRelease: Bool = false) {
        endSession()
        let app = NSWorkspace.shared.frontmostApplication
        let pid = app?.processIdentifier
        let newSession = Session(anchor: anchor, pid: pid, sourceAppName: app?.localizedName, bundleID: app?.bundleIdentifier,
                                 buttonHeld: buttonHeld, closesOnRelease: closesOnRelease)
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
            if self.askForFolderAccessIfNeeded(raw) { return }
            let content = await ContentClassifier.classifyOffMain(raw, catalog: self.registry.catalog)
            guard self.session?.id == sessionID else { return }
            self.session?.content = content
            self.route(content)
        }
    }

    /// App Store 版：选中的文件不在允许过的文件夹里时（见 FolderAccess），不往下走，弹一张卡片请用户允许访问文件夹
    private func askForFolderAccessIfNeeded(_ raw: SelectionContent) -> Bool {
        guard case .files(let urls) = raw, !FolderAccess.shared.needingAccess(urls).isEmpty else { return false }
        let card = ResultCard(title: String(localized: "先允许 Pop 访问文件所在的文件夹"),
                              body: String(localized: "App Store 版的 Pop 只能读写你允许过的文件夹。允许一次（一般选个人文件夹），之后在访达里选中文件再唤起 Pop 就能用了。"),
                              buttons: [CardButton(title: String(localized: "允许访问文件夹…"),
                                                   action: .custom(PluginCardAction { [weak self] _ in
                                                       self?.endSession()
                                                       FolderAccess.shared.requestAccess()
                                                   }))])
        present(.card(card))
        return true
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
        let ring = RingViewModel(layout: settings.ring(for: current.bundleID), catalog: registry.catalog,
                                 installed: Set(settings.installedPlugins), content: content)
        session?.ring = ring
        session?.panel = nil
        overlay.showRing(ring, center: current.anchor)
        followRingWithPointer()
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
        if pluginID != BuiltinPluginID.allPlugins {
            PluginUsage.shared.record(pluginID)
        }
        if plugin.info.hidesOverlay {
            // 截图、取色要看清屏幕：立刻收起浮窗（不播放收起动画），结果出来后再显示在原来的位置
            overlay.hide(animated: false)
        }
        let pid = current.pid
        let reader = self.reader
        // 链接带来的文字不是前台 App 里选中的，不去读那边的格式
        var readRich: (() async -> RichSelection?)? = nil
        if !current.fromLink {
            readRich = { await reader.readRich(pid: pid) }
        }
        let context = PluginContext(settings: settingsStore.settings,
                                    openSettings: { [weak self] in self?.openSettings(nil) },
                                    sourceAppName: current.sourceAppName,
                                    sourcePID: pid,
                                    anchor: current.anchor,
                                    readRichSelection: readRich)
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
        case .card(var card):
            if current.fromLink {
                // 链接带来的文字不在哪个 App 里，没有原文可以替换
                card.replaceText = nil
                card.rowsReplaceable = false
            }
            overlay.showCard(ResultCardView(card: card,
                                            onAction: { [weak self] action in self?.perform(action) },
                                            onMore: moreAction(for: current),
                                            onClose: { [weak self] in self?.endSession() }),
                             anchor: current.anchor)
        case .translate(let text, let language):
            let target = translationTarget(text: text, content: current.content, language: language)
            let settings = settingsStore.settings
            let model = TranslationModel(text: text, sourceLanguage: language, targetLanguage: target,
                                         engine: settings.translation.engine, services: .live(ai: settings.ai))
            overlay.showCard(TranslationCardView(model: model,
                                                 canReplace: Self.canReplace(current) && current.content?.text == text,
                                                 onAction: { [weak self] action in self?.perform(action) },
                                                 onMore: moreAction(for: current),
                                                 onDownload: { [weak self, weak model] in
                                                     // 卡片上可能换过目标语言
                                                     self?.downloadLanguagePack(source: language, target: model?.targetCode ?? target)
                                                 },
                                                 onOpenSettings: { [weak self] tab in
                                                     self?.endSession()
                                                     self?.openSettings(tab)
                                                 },
                                                 onClose: { [weak self] in self?.endSession() }),
                             anchor: current.anchor)
        case .replace(let text):
            if current.fromLink {
                copy(text)
            } else {
                replaceSelection(with: text)
            }
        case .showAllPlugins:
            presentChooser()
        case .showClipboardHistory:
            presentClipboardHistory()
        case .ai(let spec):
            presentAI(spec)
        case .showSnippets:
            presentSnippets()
        case .chooseApp(let request):
            presentOpenWith(request)
        case .showVocabulary:
            presentVocabulary()
        case .trimMedia(let file):
            presentTrim(file)
        case .idPhoto(let file):
            presentIDPhoto(file)
        case .present(let presentation):
            stopPointerTracking()
            presentation.run(pluginSession(current))
        case .failure(let message):
            overlay.showCard(ResultCardView(card: ResultCard(title: String(localized: "没能完成"), body: message),
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
        case .openAll(let urls):
            endSession()
            urls.forEach { NSWorkspace.shared.open($0) }
        case .reveal(let url):
            endSession()
            NSWorkspace.shared.activateFileViewerSelecting([url])
        case .copyImage(let png):
            PasteboardWriter.copy(png: png)
            finish(toast: String(localized: "已复制图片"))
        case .saveImage(let png, let name):
            do {
                _ = try ImageFiles.saveToDownloads(png, name: name)
                finish(toast: String(localized: "已存到「下载」"))
            } catch {
                present(.failure(String(localized: "存储失败：\(error.localizedDescription)")))
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
        case .addToVocabulary(let word, let translation, let source, let target):
            let isNew = VocabularyStore.shared.add(word: word, translation: translation, sourceLanguage: source, targetLanguage: target)
            finish(toast: isNew ? String(localized: "已加入生词本") : String(localized: "生词本里已经有了，换成了这次的释义"))
        case .convertImages(let files, let operation):
            convertImages(files, operation)
        case .stitchImages(let files, let direction):
            stitchImages(files, direction)
        case .convertVideos(let files, let operation):
            convertVideos(files, operation)
        case .exportPDFPages(let pdf):
            exportPDFPages(pdf)
        case .compressPDF(let pdf):
            compressPDF(pdf)
        case .pdfPages(let pdf):
            presentPDFPages(pdf)
        case .pdfPassword(let pdf):
            presentPDFPassword(pdf)
        case .animateImages(let files):
            animateImages(files)
        case .imageSizeLimit(let files):
            presentImageSizeLimit(files)
        case .trimMedia(let file):
            presentTrim(file)
        case .keepAwake(let minutes):
            let started = KeepAwake.shared.start(minutes: minutes)
            finish(toast: started ? (minutes.map { String(localized: "保持唤醒 \(KeepAwake.title(minutes: $0))") } ?? String(localized: "一直保持唤醒")) : String(localized: "没能保持唤醒"))
        case .stopKeepAwake:
            KeepAwake.shared.stop()
            finish(toast: String(localized: "已停止保持唤醒"))
        case .copyRichText(let markdown):
            guard let rich = MarkdownRichText.render(markdown) else {
                present(.failure(String(localized: "没能转换这段 Markdown")))
                return
            }
            MarkdownRichText.copy(rich)
            finish(toast: String(localized: "已复制为富文本"))
        case .expandLink(let url):
            expandLink(url)
        case .startTimer(let seconds):
            CountdownTimer.shared.start(seconds: seconds)
            finish(toast: String(localized: "开始计时 \(CountdownTimer.title(seconds: seconds))"))
        case .startPomodoro:
            CountdownTimer.shared.startPomodoro()
            finish(toast: String(localized: "番茄钟开始：先专注 \(CountdownTimer.Pomodoro.focusMinutes) 分钟"))
        case .cancelTimer:
            CountdownTimer.shared.cancel()
            finish(toast: String(localized: "已取消计时"))
        case .stopPhoneShare:
            PhoneShare.shared.stop()
            finish(toast: String(localized: "已停止传到手机"))
        case .transcribe(let file, let language):
            transcribe(file, language: language)
        case .captureWeb(let url, let format):
            captureWeb(url, format: format)
        case .cropImages(let files, let ratio):
            cropImages(files, ratio)
        case .redactImages(let files, let targets):
            redactImages(files, targets)
        case .system(let action):
            runSystemAction(action)
        case .textImage(let text, let style):
            // 在后台画；画好时还是这一次唤起才换上
            let id = session?.id
            Task { [weak self] in
                let outcome = await TextImage.outcomeInBackground(text, style: style)
                guard let self, self.session?.id == id else { return }
                self.present(outcome)
            }
        case .barcode(let text):
            if let png = QRCode.barcode(text) {
                present(.card(ResultCard(title: String(localized: "条形码"), body: text, detail: String(localized: "Code 128 条形码"), image: png,
                                         buttons: [CardButton(title: String(localized: "复制图片"), action: .copyImage(png)),
                                                   CardButton(title: String(localized: "存储"),
                                                              action: .saveImage(png, name: ImageFiles.timestampedName(String(localized: "Pop 条形码"))))])))
            } else {
                present(.failure(String(localized: "只有英文字母、数字和常见符号能生成条形码，最多 80 个字")))
            }
        case .custom(let action):
            if let current = session {
                action.run(pluginSession(current))
            }
        case .recognizeImageText(let png):
            recognizeImageText(png)
        }
    }

    /// 识别图片里的文字：先换成「正在识别」的卡片，识别好了换成文字卡片
    private func recognizeImageText(_ png: Data) {
        guard let current = session else { return }
        let sessionID = current.id
        present(.card(ResultCard(title: String(localized: "识别文字"), body: String(localized: "正在识别图片里的文字…"))))
        Task { [weak self] in
            let text = await runInBackground { () -> Result<String, Error> in
                Result { try ScrollStitcher.recognizeText(png) }
            }
            guard let self, self.session?.id == sessionID else { return }
            switch text {
            case .success(let text) where !text.isEmpty:
                self.present(.card(TextRecognizer.card(title: String(localized: "识别文字"), text: text)))
            case .success:
                self.present(.failure(String(localized: "图片里没有识别到文字")))
            case .failure(let error):
                self.present(.failure(String(localized: "识别文字失败：\(error.localizedDescription)")))
            }
        }
    }

    /// 跟着短链接跳转，卡片换成展开后的结果
    private func expandLink(_ url: URL) {
        guard let current = session else { return }
        let sessionID = current.id
        Task { [weak self] in
            let outcome: PluginOutcome
            do {
                let expansion = try await LinkExpander.expand(url)
                outcome = .card(LinkExpander.card(for: expansion))
            } catch {
                outcome = .failure(String(localized: "展开失败：\(LinkExpander.describe(error))"))
            }
            guard let self, self.session?.id == sessionID else { return }
            self.present(outcome)
        }
    }

    /// 在后台把 PDF 的每一页存成图片，完成后在访达里选中放图片的文件夹
    private func exportPDFPages(_ pdf: URL) {
        let anchor = session?.anchor ?? NSEvent.mouseLocation
        endSession()
        let folder = FileNames.available(in: pdf.deletingLastPathComponent(),
                                         base: pdf.deletingPathExtension().lastPathComponent + String(localized: " 的页面"))
        Task { [weak self] in
            let result = await runInBackground { () -> Result<[URL], PDFTools.Failure> in
                do {
                    return .success(try PDFTools.exportPages(of: pdf, to: folder))
                } catch let failure as PDFTools.Failure {
                    return .failure(failure)
                } catch {
                    return .failure(PDFTools.Failure(message: error.localizedDescription))
                }
            }
            guard let self else { return }
            switch result {
            case .success(let pages):
                NSWorkspace.shared.activateFileViewerSelecting([folder])
                self.showToast(String(localized: "已存成 \(pages.count) 张图片"), at: anchor)
            case .failure(let failure):
                self.showToast(failure.message, at: anchor)
            }
        }
    }

    /// PDF 页面：写上页码取出来，或者每页存成一个 PDF
    private func presentPDFPages(_ pdf: URL) {
        guard let current = session else { return }
        stopPointerTracking()
        guard let count = (try? PDFTools.open(pdf))?.pageCount, count > 0 else {
            present(.failure(String(localized: "读不了「\(pdf.lastPathComponent)」")))
            return
        }
        let model = PDFPagesModel(pdf: pdf, pageCount: count)
        overlay.showCard(PDFPagesView(model: model,
                                      onExtract: { [weak self] pages in self?.extractPDFPages(pdf, pages) },
                                      onSplit: { [weak self] in self?.splitPDF(pdf) },
                                      onClose: { [weak self] in self?.endSession() }),
                         anchor: current.anchor)
    }

    private func extractPDFPages(_ pdf: URL, _ pages: [Int]) {
        let anchor = session?.anchor ?? NSEvent.mouseLocation
        endSession()
        let base = pdf.deletingPathExtension().lastPathComponent
        // 页码写得很长时文件名只写页数
        let described = PDFTools.describe(pages)
        let label = described.count <= 30 ? described : String(localized: "中的 \(pages.count) 页")
        let destination = FileNames.available(in: pdf.deletingLastPathComponent(), base: "\(base) \(label)", extension: "pdf")
        Task { [weak self] in
            let failure = await runInBackground { () -> String? in
                do {
                    try PDFTools.extract(pdf, pages: pages, to: destination)
                    return nil
                } catch {
                    try? FileManager.default.removeItem(at: destination)
                    return (error as? PDFTools.Failure)?.message ?? error.localizedDescription
                }
            }
            guard let self else { return }
            if let failure {
                self.showToast(failure, at: anchor)
            } else {
                NSWorkspace.shared.activateFileViewerSelecting([destination])
                self.showToast(String(localized: "已取出 \(pages.count) 页"), at: anchor)
            }
        }
    }

    private func splitPDF(_ pdf: URL) {
        let anchor = session?.anchor ?? NSEvent.mouseLocation
        endSession()
        let folder = FileNames.available(in: pdf.deletingLastPathComponent(),
                                         base: pdf.deletingPathExtension().lastPathComponent + String(localized: " 的每一页"))
        Task { [weak self] in
            let result = await runInBackground { () -> Result<[URL], PDFTools.Failure> in
                do {
                    return .success(try PDFTools.split(pdf, to: folder))
                } catch let failure as PDFTools.Failure {
                    return .failure(failure)
                } catch {
                    return .failure(PDFTools.Failure(message: error.localizedDescription))
                }
            }
            guard let self else { return }
            switch result {
            case .success(let files):
                NSWorkspace.shared.activateFileViewerSelecting([folder])
                self.showToast(String(localized: "已拆成 \(files.count) 个 PDF"), at: anchor)
            case .failure(let failure):
                self.showToast(failure.message, at: anchor)
            }
        }
    }

    /// PDF 密码：没有密码的加上密码，有密码的输入密码去掉；另存一份，原文件不动
    private func presentPDFPassword(_ pdf: URL) {
        guard let current = session else { return }
        stopPointerTracking()
        let sessionID = current.id
        Task { [weak self] in
            // 打开 PDF 看有没有密码放在后台
            let locked = await runInBackground { PDFTools.isLocked(pdf) }
            guard let self, let current = self.session, current.id == sessionID else { return }
            let model = PDFPasswordModel(pdf: pdf, mode: locked ? .remove : .add)
            self.overlay.showCard(PDFPasswordView(model: model,
                                                  onSubmit: { [weak self] password in self?.savePDFPassword(model, password) },
                                                  onClose: { [weak self] in self?.endSession() }),
                                  anchor: current.anchor)
        }
    }

    private func savePDFPassword(_ model: PDFPasswordModel, _ password: String) {
        let pdf = model.pdf
        let adding = model.mode == .add
        let destination = FileNames.available(in: pdf.deletingLastPathComponent(),
                                              base: pdf.deletingPathExtension().lastPathComponent + (adding ? String(localized: " 加密") : String(localized: " 无密码")),
                                              extension: "pdf")
        Task { [weak self] in
            let failure = await runInBackground { () -> String? in
                do {
                    if adding {
                        try PDFTools.encrypt(pdf, password: password, to: destination)
                    } else {
                        try PDFTools.removePassword(pdf, password: password, to: destination)
                    }
                    return nil
                } catch {
                    try? FileManager.default.removeItem(at: destination)
                    return (error as? PDFTools.Failure)?.message ?? error.localizedDescription
                }
            }
            guard let self else { return }
            // 密码不对这类问题留在卡片上，改了再试
            if let failure {
                model.error = failure
                return
            }
            let anchor = self.session?.anchor ?? NSEvent.mouseLocation
            self.endSession()
            NSWorkspace.shared.activateFileViewerSelecting([destination])
            self.showToast(adding ? String(localized: "已另存一份加了密码的 PDF") : String(localized: "已另存一份没有密码的 PDF"), at: anchor)
        }
    }

    /// 在后台压缩 PDF；小了才留下，在访达里选中
    private func compressPDF(_ pdf: URL) {
        let anchor = session?.anchor ?? NSEvent.mouseLocation
        showToast(String(localized: "正在压缩 PDF…"), at: anchor)
        Task { [weak self] in
            let result = await runInBackground { () -> Result<PDFTools.Compression, PDFTools.Failure> in
                do {
                    return .success(try PDFTools.compress(pdf))
                } catch let failure as PDFTools.Failure {
                    return .failure(failure)
                } catch {
                    return .failure(PDFTools.Failure(message: error.localizedDescription))
                }
            }
            guard let self else { return }
            let message: String
            switch result {
            case .success(let compression) where compression.worthwhile:
                NSWorkspace.shared.activateFileViewerSelecting([compression.url])
                message = String(localized: "已压缩：\(FileInfo.shortSize(compression.before)) → \(FileInfo.shortSize(compression.after))")
            case .success(let compression):
                try? FileManager.default.removeItem(at: compression.url)
                message = String(localized: "这个 PDF 已经很小了，压缩不了多少")
            case .failure(let failure):
                message = failure.message
            }
            if self.session == nil {
                self.showToast(message, at: anchor)
            }
        }
    }

    /// 在后台转换图片，完成后在访达里选中新文件
    private func convertImages(_ files: [URL], _ operation: ImageConverter.Operation) {
        let anchor = session?.anchor ?? NSEvent.mouseLocation
        endSession()
        Task { [weak self] in
            let (outputs, failures) = await runInBackground { () -> ([URL], [String]) in
                var outputs: [URL] = []
                var failures: [String] = []
                for file in files {
                    do {
                        outputs.append(try ImageConverter.convert(file, operation))
                    } catch let failure as ImageConverter.Failure {
                        failures.append(failure.message)
                    } catch {
                        failures.append(error.localizedDescription)
                    }
                }
                return (outputs, failures)
            }
            guard let self else { return }
            if !outputs.isEmpty {
                NSWorkspace.shared.activateFileViewerSelecting(outputs)
            }
            let message: String
            if let failure = failures.first {
                message = outputs.isEmpty ? failure : String(localized: "转换了 \(outputs.count) 张，\(failures.count) 张失败：\(failure)")
            } else {
                message = outputs.count == 1 ? String(localized: "已存到原图旁边") : String(localized: "已转换 \(outputs.count) 张")
            }
            self.showToast(message, at: anchor)
        }
    }

    /// 网页存档：在后台打开网页，存好后在访达里选中；这期间又用起了 Pop 就不打断
    private func captureWeb(_ url: URL, format: WebCapture.Format) {
        let anchor = session?.anchor ?? NSEvent.mouseLocation
        showToast(String(localized: "正在打开网页…"), at: anchor)
        Task { [weak self] in
            let message: String
            do {
                let output = try await WebCapture.capture(url, format: format)
                NSWorkspace.shared.activateFileViewerSelecting([output])
                message = String(localized: "已存到「下载」：\(output.lastPathComponent)")
            } catch {
                message = (error as? WebCapture.Failure)?.message ?? error.localizedDescription
            }
            guard let self, self.session == nil else { return }
            self.showToast(message, at: NSEvent.mouseLocation)
        }
    }

    /// 系统操作：先收起浮窗（锁屏、熄屏前不留着卡片），做完需要的话提示一句
    private func runSystemAction(_ action: SystemAction) {
        let anchor = session?.anchor ?? NSEvent.mouseLocation
        endSession()
        Task { [weak self] in
            guard let message = await SystemActions.run(action) else { return }
            self?.showToast(message, at: anchor)
        }
    }

    /// 隐私打码：在后台逐张处理，完成后在访达里选中新文件
    private func redactImages(_ files: [URL], _ targets: Set<Redaction.Target>) {
        let anchor = session?.anchor ?? NSEvent.mouseLocation
        endSession()
        Task { [weak self] in
            let (outputs, failures) = await runInBackground { () -> ([URL], [String]) in
                var outputs: [URL] = []
                var failures: [String] = []
                for file in files {
                    do {
                        outputs.append(try Redaction.redact(file, targets: targets).output)
                    } catch let failure as Redaction.Failure {
                        failures.append(failure.message)
                    } catch {
                        failures.append(error.localizedDescription)
                    }
                }
                return (outputs, failures)
            }
            guard let self else { return }
            if !outputs.isEmpty {
                NSWorkspace.shared.activateFileViewerSelecting(outputs)
            }
            let message: String
            if let failure = failures.first {
                message = outputs.isEmpty ? failure : String(localized: "打好了 \(outputs.count) 张，\(failures.count) 张失败：\(failure)")
            } else {
                message = outputs.count == 1 ? String(localized: "已打码，另存在原图旁边") : String(localized: "已给 \(outputs.count) 张打码，各自另存在原图旁边")
            }
            self.showToast(message, at: anchor)
        }
    }

    /// 按比例裁剪：在后台逐张处理，完成后在访达里选中新文件
    private func cropImages(_ files: [URL], _ ratio: SmartCrop.Ratio) {
        let anchor = session?.anchor ?? NSEvent.mouseLocation
        endSession()
        Task { [weak self] in
            let (outputs, failures) = await runInBackground { () -> ([URL], [String]) in
                var outputs: [URL] = []
                var failures: [String] = []
                for file in files {
                    do {
                        outputs.append(try SmartCrop.crop(file, ratio: ratio))
                    } catch let failure as SmartCrop.Failure {
                        failures.append(failure.message)
                    } catch {
                        failures.append(error.localizedDescription)
                    }
                }
                return (outputs, failures)
            }
            guard let self else { return }
            if !outputs.isEmpty {
                NSWorkspace.shared.activateFileViewerSelecting(outputs)
            }
            let message: String
            if let failure = failures.first {
                message = outputs.isEmpty ? failure : String(localized: "裁好了 \(outputs.count) 张，\(failures.count) 张失败：\(failure)")
            } else {
                message = outputs.count == 1 ? String(localized: "已裁成 \(ratio.title)，存在原图旁边") : String(localized: "已把 \(outputs.count) 张裁成 \(ratio.title)")
            }
            self.showToast(message, at: anchor)
        }
    }

    /// 在后台拼接图片，完成后在访达里选中新文件
    private func stitchImages(_ files: [URL], _ direction: ImageStitcher.Direction) {
        let anchor = session?.anchor ?? NSEvent.mouseLocation
        endSession()
        Task { [weak self] in
            let result = await runInBackground { () -> Result<URL, ImageStitcher.Failure> in
                do {
                    return .success(try ImageStitcher.stitch(files, direction: direction))
                } catch let failure as ImageStitcher.Failure {
                    return .failure(failure)
                } catch {
                    return .failure(ImageStitcher.Failure(message: error.localizedDescription))
                }
            }
            guard let self else { return }
            switch result {
            case .success(let output):
                NSWorkspace.shared.activateFileViewerSelecting([output])
                self.showToast(String(localized: "已拼成一张，存在第一张旁边"), at: anchor)
            case .failure(let failure):
                self.showToast(failure.message, at: anchor)
            }
        }
    }

    /// 几张图片合成动图，存在第一张旁边
    private func animateImages(_ files: [URL]) {
        let anchor = session?.anchor ?? NSEvent.mouseLocation
        endSession()
        Task { [weak self] in
            let result = await runInBackground { () -> Result<URL, ImageStitcher.Failure> in
                do {
                    return .success(try ImageStitcher.animate(files))
                } catch let failure as ImageStitcher.Failure {
                    return .failure(failure)
                } catch {
                    return .failure(ImageStitcher.Failure(message: error.localizedDescription))
                }
            }
            guard let self else { return }
            switch result {
            case .success(let output):
                NSWorkspace.shared.activateFileViewerSelecting([output])
                self.showToast(String(localized: "已合成动图，存在第一张旁边"), at: anchor)
            case .failure(let failure):
                self.showToast(failure.message, at: anchor)
            }
        }
    }

    /// 截取片段：先读出时长，写好时间后在后台截取，好了在访达里选中新文件
    private func presentTrim(_ file: URL) {
        guard let current = session else { return }
        stopPointerTracking()
        Task { [weak self] in
            let duration = await MediaTrim.duration(of: file)
            guard let self, self.session?.id == current.id else { return }
            guard let duration else {
                self.present(.failure(String(localized: "读不到「\(file.lastPathComponent)」的时长")))
                return
            }
            let model = MediaTrimModel(file: file, duration: duration)
            self.overlay.showCard(MediaTrimView(model: model,
                                                onTrim: { [weak self] range in self?.trim(file, range) },
                                                onClose: { [weak self] in self?.endSession() }),
                                  anchor: current.anchor)
        }
    }

    private func trim(_ file: URL, _ range: ClosedRange<Double>) {
        let anchor = session?.anchor ?? NSEvent.mouseLocation
        endSession()
        showToast(String(localized: "正在截取…"), at: anchor)
        Task { [weak self] in
            let message: String
            do {
                let output = try await MediaTrim.trim(file, range: range)
                NSWorkspace.shared.activateFileViewerSelecting([output])
                message = String(localized: "已截取 \(MediaTrim.label(range.upperBound - range.lowerBound))")
            } catch {
                message = (error as? MediaTrim.Failure)?.message ?? error.localizedDescription
            }
            // 截取要一会儿：这期间又唤起了 Pop 的话不去打断
            guard let self, self.session == nil else { return }
            self.showToast(message, at: anchor)
        }
    }

    /// 转换视频要一会儿：先提示正在转换，好了在访达里选中新文件
    private func convertVideos(_ files: [URL], _ operation: VideoConverter.Operation) {
        let anchor = session?.anchor ?? NSEvent.mouseLocation
        showToast(operation.progress, at: anchor)
        Task { [weak self] in
            var outputs: [URL] = []
            var notes: [String] = []
            var failures: [String] = []
            for file in files {
                do {
                    let result = try await VideoConverter.convert(file, operation)
                    outputs.append(result.url)
                    if let note = result.note {
                        notes.append(note)
                    }
                } catch let failure as VideoConverter.Failure {
                    failures.append(failure.message)
                } catch {
                    failures.append(error.localizedDescription)
                }
            }
            guard let self else { return }
            if !outputs.isEmpty {
                NSWorkspace.shared.activateFileViewerSelecting(outputs)
            }
            let message: String
            if let failure = failures.first {
                message = outputs.isEmpty ? failure : String(localized: "转换了 \(outputs.count) 个，\(failures.count) 个失败：\(failure)")
            } else if outputs.count > 1 {
                message = String(localized: "已转换 \(outputs.count) 个视频")
            } else {
                message = ([operation.done] + notes).joined(separator: String(localized: "；"))
            }
            // 转换要一会儿：这期间又唤起了 Pop 的话不去打断，结果在访达里已经选中了
            if self.session == nil {
                self.showToast(message, at: NSEvent.mouseLocation)
            }
        }
    }

    /// 证件照：抠图、预览都在卡片里做，确认后另存一份放在原图旁边
    private func presentIDPhoto(_ file: URL) {
        guard let current = session else { return }
        stopPointerTracking()
        let model = IDPhotoModel(file: file)
        overlay.showCard(IDPhotoView(model: model,
                                     onSave: { [weak self] in self?.saveIDPhoto(model) },
                                     onClose: { [weak self] in self?.endSession() }),
                         anchor: current.anchor)
    }

    private func saveIDPhoto(_ model: IDPhotoModel) {
        let anchor = session?.anchor ?? NSEvent.mouseLocation
        endSession()
        Task { [weak self] in
            do {
                let saved = try await model.save()
                NSWorkspace.shared.activateFileViewerSelecting([saved.photo] + (saved.sheet.map { [$0] } ?? []))
                let sheet = saved.sheet == nil ? "" : String(localized: "，还有一张 6 寸排版（\(saved.copies) 张）")
                self?.showToast(String(localized: "已存成「\(saved.photo.lastPathComponent)」\(sheet)"), at: anchor)
            } catch {
                self?.showToast((error as? IDPhoto.Failure)?.message ?? error.localizedDescription, at: anchor)
            }
        }
    }

    /// 语音转文字：要一会儿，先收起卡片；识别完存好文字和字幕，在访达里选中，没在用 Pop 的话再弹出结果卡片
    private func transcribe(_ file: URL, language: String) {
        let anchor = session?.anchor ?? NSEvent.mouseLocation
        endSession()
        Task { [weak self] in
            guard await Transcriber.authorize() else {
                self?.showToast(String(localized: "要先在「系统设置 → 隐私与安全性 → 语音识别」里允许 Pop"), at: anchor)
                return
            }
            self?.showToast(String(localized: "正在识别「\(file.lastPathComponent)」里说的话…"), at: anchor)
            do {
                let transcript = try await Transcriber.transcribe(file, language: language, onDownload: { [weak self] in
                    DispatchQueue.main.async { [weak self] in
                        MainActor.assumeIsolated {
                            // 正在用 Pop 的话不打断
                            guard let self, self.session == nil else { return }
                            self.showToast(String(localized: "第一次识别这种话，要先下载系统的识别模型，稍等一会儿…"), at: NSEvent.mouseLocation)
                        }
                    }
                })
                let saved = try Transcriber.save(transcript, beside: file, language: language)
                NSWorkspace.shared.activateFileViewerSelecting([saved.text, saved.subtitles])
                guard let self, self.session == nil else { return }
                let point = NSEvent.mouseLocation
                self.session = Session(anchor: point, pid: nil, sourceAppName: nil, buttonHeld: false, content: .empty)
                self.present(.card(Transcriber.card(transcript, file: file, language: language)))
            } catch {
                self?.showToast(Transcriber.describe(error), at: NSEvent.mouseLocation)
            }
        }
    }

    /// 常用短语：选一条，填好占位符后粘贴到原来的 App（粘贴完剪贴板恢复原样）
    private func presentSnippets() {
        guard let current = session else { return }
        stopPointerTracking()
        let model = SnippetPickerModel(snippets: settingsStore.settings.snippets)
        let selection = current.content?.text
        model.onPaste = { [weak self] snippet in
            let text = SnippetExpander.expand(snippet.text, clipboard: NSPasteboard.general.string(forType: .string),
                                              selection: selection)
            self?.replaceSelection(with: text)
        }
        model.onOpenSettings = { [weak self] in
            self?.endSession()
            self?.openSettings(.clipboard)
        }
        overlay.showCard(SnippetPickerView(model: model, onClose: { [weak self] in self?.endSession() }),
                         anchor: current.anchor,
                         keyHandler: { event in model.handleKey(event) })
    }

    /// 打开方式：选一个 App 打开文件或链接
    private func presentOpenWith(_ request: OpenWithRequest) {
        guard let current = session else { return }
        stopPointerTracking()
        let choose: (URL) -> Void = { [weak self] app in
            self?.endSession()
            NSWorkspace.shared.open(request.targets, withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration(),
                                    completionHandler: nil)
        }
        overlay.showCard(OpenWithCardView(request: request, onChoose: choose, onClose: { [weak self] in self?.endSession() }),
                         anchor: current.anchor,
                         keyHandler: { event in
                             guard let index = OpenWithCardView.index(for: event), request.apps.indices.contains(index) else {
                                 return false
                             }
                             choose(request.apps[index])
                             return true
                         })
    }

    /// AI 卡片：马上执行指定的指令，或者等用户选指令、提问
    private func presentAI(_ spec: AIRequestSpec) {
        guard let current = session else { return }
        let model = AIChatModel(source: spec.text, settings: settingsStore.settings)
        let canReplace = Self.canReplace(current) && current.content?.text == spec.text
        overlay.showCard(AICardView(model: model, canReplace: canReplace,
                                    focusQuestion: spec.action == nil && spec.prompt == nil,
                                    onAction: { [weak self] action in self?.perform(action) },
                                    onMore: moreAction(for: current),
                                    onOpenSettings: { [weak self] in
                                        self?.endSession()
                                        self?.openSettings(.ai)
                                    },
                                    onClose: { [weak self] in self?.endSession() }),
                         anchor: current.anchor,
                         keyHandler: { event in model.handleKey(event) })
        if let prompt = spec.prompt {
            model.run(prompt: prompt, label: spec.label ?? "AI")
        } else if let action = spec.action {
            model.run(action)
        }
    }

    /// 生词本：搜索、朗读、复习、导出
    private func presentVocabulary() {
        guard let current = session else { return }
        stopPointerTracking()
        let model = VocabularyModel(store: VocabularyStore.shared)
        overlay.showCard(VocabularyView(model: model,
                                        onCopy: { [weak self] text in self?.copy(text) },
                                        onSpeak: { entry in Speaker.shared.speak(entry.word, language: entry.sourceLanguage) },
                                        onExport: { [weak self] format in self?.exportVocabulary(format) },
                                        onClose: { [weak self] in self?.endSession() }),
                         anchor: current.anchor)
    }

    /// 生词本存成文件：CSV 开头加 BOM，Excel 打开中文不会乱码
    private func exportVocabulary(_ format: VocabularyStore.ExportFormat) {
        endSession()
        let text = (format == .csv ? "\u{FEFF}" : "") + VocabularyStore.export(VocabularyStore.shared.entries, as: format)
        NSApp.activate()
        let panel = NSSavePanel()
        panel.nameFieldStringValue = String(localized: "Pop 生词本.\(format.fileExtension)")
        panel.allowedContentTypes = [format.contentType]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            showToast(String(localized: "导出失败：\(error.localizedDescription)"), at: NSEvent.mouseLocation)
        }
    }

    /// 压缩到指定大小：选一档，每张图另存一份不超过这个大小的 JPEG
    private func presentImageSizeLimit(_ files: [URL]) {
        guard let current = session else { return }
        stopPointerTracking()
        overlay.showCard(ImageSizeLimitView(files: files,
                                            onCompress: { [weak self] limit in self?.compressImages(files, toBytes: limit) },
                                            onClose: { [weak self] in self?.endSession() }),
                         anchor: current.anchor)
    }

    private func compressImages(_ files: [URL], toBytes limit: Int) {
        let anchor = session?.anchor ?? NSEvent.mouseLocation
        endSession()
        Task { [weak self] in
            let result = await runInBackground { () -> (outputs: [(url: URL, bytes: Int)], failures: [String]) in
                var outputs: [(url: URL, bytes: Int)] = []
                var failures: [String] = []
                for file in files {
                    do {
                        outputs.append(try ImageConverter.compress(file, toBytes: limit))
                    } catch {
                        failures.append((error as? ImageConverter.Failure)?.message ?? error.localizedDescription)
                    }
                }
                return (outputs, failures)
            }
            guard let self else { return }
            if !result.outputs.isEmpty {
                NSWorkspace.shared.activateFileViewerSelecting(result.outputs.map { $0.url })
            }
            let message: String
            if let failure = result.failures.first {
                message = result.outputs.isEmpty ? failure : String(localized: "压好了 \(result.outputs.count) 张，\(result.failures.count) 张失败：\(failure)")
            } else if result.outputs.count == 1 {
                message = String(localized: "已压缩到 \(FileInfo.shortSize(Int64(result.outputs[0].bytes)))")
            } else {
                message = String(localized: "已压缩 \(result.outputs.count) 张，都在 \(ImageConverter.sizeLabel(limit)) 以内")
            }
            self.showToast(message, at: anchor)
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
        // 最近用过的排在前面，⌘1–5 就能直接选到
        let ordered = PluginUsage.ordered(plugins, recent: PluginUsage.shared.recent())
        // 这台 Mac 上没装的插件包：搜索时也列出来，点一下装上
        let available = PluginCatalog.all.filter { !PluginBundles.shared.isLoaded($0.id) }
        let model = PluginChooserModel(plugins: ordered.plugins,
                                       recent: Set(ordered.plugins.prefix(ordered.recentCount).map(\.id)),
                                       packages: pluginManager == nil ? [] : available,
                                       manager: pluginManager)
        model.onRun = { [weak self] info in
            self?.run(info.id)
        }
        model.onInstall = { [weak self] package in
            self?.installFromChooser(package)
        }
        session?.panel = .chooser
        overlay.showCard(PluginChooserView(model: model, onClose: { [weak self] in self?.endSession() }),
                         anchor: current.anchor,
                         keyHandler: { event in model.handleKey(event) })
    }

    /// 「全部功能」里点了没装的插件：装上；装好时「全部功能」还开着，能处理当前内容就直接用，处理不了就提示装好了
    private func installFromChooser(_ package: PluginPackage) {
        guard let manager = pluginManager, let current = session else { return }
        if case .installing = manager.status(of: package) { return }
        manager.install(package)
        let sessionID = current.id
        chooserInstall = manager.$statuses
            .compactMap { $0[package.id] }
            .first { (status: PluginManager.Status) -> Bool in
                switch status {
                case .installed, .failed: return true
                case .installing, .notInstalled: return false
                }
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                MainActor.assumeIsolated {
                    guard let self, case .installed = status, let current = self.session,
                          current.id == sessionID, current.panel == .chooser else { return }
                    let content = current.content ?? .empty
                    if let id = package.functions.first(where: { self.registry.plugin(id: $0)?.info.canHandle(content) == true }) {
                        self.run(id)
                    } else {
                        self.showToast(String(localized: "装好了「\(package.name)」"), at: current.anchor)
                    }
                }
            }
    }

    private func presentClipboardHistory() {
        guard let current = session else { return }
        stopPointerTracking()
        let model = ClipboardHistoryModel(service: clipboard)
        model.onPaste = { [weak self] item in
            self?.pasteFromHistory(item)
        }
        model.onPasteText = { [weak self] text in
            // 合在一起的文字留在剪贴板里，和粘贴一条历史一样
            self?.endSession()
            Paster.paste { pasteboard in
                pasteboard.setString(text, forType: .string)
            }
        }
        model.onOpenSettings = { [weak self] in
            self?.endSession()
            self?.openSettings(.clipboard)
        }
        model.onTranslate = { [weak self] text in
            self?.present(.translate(text: text, language: ContentClassifier.dominantLanguage(text)))
        }
        model.onPin = { [weak self] item in
            self?.pinFromHistory(item)
        }
        model.onRecognize = { [weak self] item in
            self?.recognizeFromHistory(item)
        }
        model.onAnnotate = { [weak self] item in
            self?.annotateFromHistory(item)
        }
        if settingsStore.settings.isInstalled(BuiltinPluginID.tableOCR), registry.plugin(id: BuiltinPluginID.tableOCR) != nil {
            model.onRecognizeTable = { [weak self] item in
                self?.recognizeTableFromHistory(item)
            }
        }
        model.onSaveSnippet = { [weak self] item in
            self?.saveSnippet(from: item)
        }
        session?.panel = .clipboard
        overlay.showCard(ClipboardHistoryView(model: model, onClose: { [weak self] in self?.endSession() }),
                         anchor: current.anchor,
                         keyHandler: { event in model.handleKey(event) })
    }

    /// 剪贴板历史里的文字或图片贴到屏幕上
    private func pinFromHistory(_ item: ClipboardItem) {
        let anchor = session?.anchor ?? NSEvent.mouseLocation
        endSession()
        switch item.kind {
        case .text:
            PinBoard.shared.pin(text: item.text, around: anchor)
        case .image:
            if let url = clipboard.store.imageURL(for: item), let data = try? Data(contentsOf: url) {
                PinBoard.shared.pin(imageData: data, around: anchor)
            }
        case .files:
            break
        }
    }

    /// 在标注窗口里打开剪贴板历史里的一张图片
    private func annotateFromHistory(_ item: ClipboardItem) {
        let anchor = session?.anchor ?? NSEvent.mouseLocation
        guard let url = clipboard.store.imageURL(for: item), let data = try? Data(contentsOf: url),
              let image = TextRecognizer.cgImage(from: data) else {
            present(.failure(String(localized: "无法读取这张图片")))
            return
        }
        endSession()
        AnnotationWindowController.present(ScreenCapture.Capture(image: image, png: data), near: anchor)
    }

    /// 把剪贴板历史里的一段文字存成常用短语（已经有同样的就不重复存）
    private func saveSnippet(from item: ClipboardItem) {
        let text = item.text
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        settingsStore.update { settings in
            guard !settings.snippets.contains(where: { $0.text == text }) else { return }
            settings.snippets.append(Snippet(title: "", text: text))
        }
        finish(toast: String(localized: "已存为常用短语"))
    }

    /// 识别剪贴板历史里某张图片上的文字
    private func recognizeFromHistory(_ item: ClipboardItem) {
        guard let url = clipboard.store.imageURL(for: item), let image = TextRecognizer.cgImage(contentsOf: url) else {
            present(.failure(String(localized: "无法读取这张图片")))
            return
        }
        let sessionID = session?.id
        Task { [weak self] in
            let result = await TextRecognizer.recognize(image)
            guard let self, self.session?.id == sessionID else { return }
            switch result {
            case .success(let text) where !text.isEmpty:
                self.present(.card(TextRecognizer.card(title: String(localized: "识别文字"), text: text)))
            case .success:
                self.present(.failure(String(localized: "图片里没有识别到文字")))
            case .failure(let error):
                self.present(.failure(error.message))
            }
        }
    }

    /// 剪贴板历史里的图片按表格识别：交给「识别表格」插件（macOS 26；更早的系统按普通文字识别）
    private func recognizeTableFromHistory(_ item: ClipboardItem) {
        guard let plugin = registry.plugin(id: BuiltinPluginID.tableOCR) else { return }
        // 先确认图片读得出来：插件拿到读不出的图片会改成去框选屏幕
        guard let url = clipboard.store.imageURL(for: item), let data = try? Data(contentsOf: url),
              TextRecognizer.cgImage(from: data) != nil else {
            present(.failure(String(localized: "无法读取这张图片")))
            return
        }
        let sessionID = session?.id
        let context = PluginContext(settings: settingsStore.settings, openSettings: { [weak self] in self?.openSettings(nil) })
        Task { [weak self] in
            let outcome = await plugin.run(ContentClassifier.classify(.image(data)), context: context)
            guard let self, self.session?.id == sessionID else { return }
            self.present(outcome)
        }
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

    /// 交给插件的这次唤起：插件用它弹自己的卡片、显示提示。唤起已经结束（又唤起了一次）时什么都不做
    private func pluginSession(_ current: Session) -> PluginSession {
        let id = current.id
        let anchor = current.anchor
        return PluginSession(
            anchor: anchor,
            canReplace: Self.canReplace(current),
            isCurrentHandler: { [weak self] in
                self?.session?.id == id
            },
            showCardHandler: { [weak self] view, keyHandler in
                guard let self, let session = self.session, session.id == id else { return }
                self.stopPointerTracking()
                self.overlay.showCard(view, anchor: session.anchor, keyHandler: keyHandler)
            },
            finishHandler: { [weak self] message in
                guard let self else { return }
                if self.session?.id == id {
                    self.finish(toast: message)
                } else if self.session == nil {
                    // 这次唤起已经结束（比如在后台转换完了），又没有新的唤起：照样提示
                    self.showToast(message, at: anchor)
                }
            },
            endHandler: { [weak self] in
                guard let self, self.session?.id == id else { return }
                self.endSession()
            },
            performHandler: { [weak self] action in
                guard let self, self.session?.id == id else { return }
                self.perform(action)
            },
            failHandler: { [weak self] message in
                guard let self, self.session?.id == id else { return }
                self.present(.failure(message))
            })
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

    /// 在前台 App 里选中了一段文字，才能把结果写回去替换它
    private static func canReplace(_ current: Session) -> Bool {
        guard !current.fromLink, case .text = current.content?.selection else { return false }
        return true
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
        finish(toast: String(localized: "已复制"))
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

    /// 靠近屏幕边缘时圆盘整体往里挪了：鼠标键还按着的话，把指针也挪到圆盘中心。
    /// 按住时按「相对按下点的方向」选格子，指针不在圆心的话，朝看到的一格划过去，选中的却是旁边那格；
    /// 指针贴着屏幕边缘时，往边外那几格也划不过去。圆盘出来之前已经拖过的那一段接着算
    private func followRingWithPointer() {
        guard let current = session, current.buttonHeld, let center = overlay.ringCenter,
              let shift = ScreenGeometry.ringShift(anchor: current.anchor, center: center) else { return }
        let moved = current.dragPoint.map { CGVector(dx: $0.x - current.anchor.x, dy: $0.y - current.anchor.y) } ?? CGVector(dx: 0, dy: 0)
        let target = CGPoint(x: center.x + moved.dx, y: center.y + moved.dy)
        CGWarpMouseCursorPosition(CGPoint(x: target.x, y: OverlayController.primaryScreenHeight - target.y))
        // 挪完马上恢复指针跟手，不然指针会停顿一小会儿
        CGAssociateMouseAndMouseCursorPosition(1)
        session?.anchor = center
        if current.dragPoint != nil {
            session?.dragPoint = target
        }
        Self.log.notice("圆盘靠边挪了 \(Int(shift.dx), privacy: .public), \(Int(shift.dy), privacy: .public)，指针跟着挪到圆心")
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
