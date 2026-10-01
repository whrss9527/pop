import AppKit
import Combine
import SwiftUI

/// 组装各个模块，并根据设置和权限状态启动/停止它们。
@MainActor
final class AppController {
    let settingsStore: SettingsStore
    let pluginStore: PluginStore
    let registry: PluginRegistry
    /// 插件包的安装、卸载和更新
    let pluginManager: PluginManager
    let permissions: PermissionMonitor
    let overlay: OverlayController
    let downloads: TranslationDownloadRequest
    let updater: Updater
    let cloudSync: CloudSync
    let clipboard: ClipboardService
    let trigger: MouseTrigger
    let hotKeys: HotKeyManager
    let coordinator: PopCoordinator
    let statusItem: StatusItemController
    let settingsWindow: SettingsWindowController
    /// 拖着文件晃几下打开暂存架
    let shakeDetector = DragShakeDetector()
    /// 选中文字后显示工具条
    let selectionWatcher = SelectionWatcher()

    private var cancellables = Set<AnyCancellable>()
    /// 最近一个在前台的别的 App：打开 pop:// 链接时系统会把 Pop 带到前台，处理前先切回去
    private var lastExternalApp: NSRunningApplication?

    init() {
        settingsStore = SettingsStore()
        pluginStore = PluginStore()
        // 先装载装好的插件包，功能列表里才有它们提供的功能
        PluginBundles.shared.loadInstalled()
        registry = PluginRegistry()
        pluginManager = PluginManager(settingsStore: settingsStore, registry: registry)
        permissions = PermissionMonitor()
        overlay = OverlayController()
        downloads = TranslationDownloadRequest()
        updater = Updater()
        cloudSync = CloudSync(settingsStore: settingsStore, pluginStore: pluginStore)
        clipboard = ClipboardService()
        trigger = MouseTrigger()
        hotKeys = HotKeyManager()
        coordinator = PopCoordinator(settingsStore: settingsStore, registry: registry, overlay: overlay,
                                     downloads: downloads, clipboard: clipboard)
        statusItem = StatusItemController()

        let store = settingsStore
        let plugins = pluginStore
        let pluginRegistry = registry
        let packages = pluginManager
        let permissionMonitor = permissions
        let sync = cloudSync
        let appUpdater = updater
        let downloadRequest = downloads
        let clipboardService = clipboard
        settingsWindow = SettingsWindowController { navigation in
            AnyView(
                SettingsRootView(navigation: navigation)
                    .environmentObject(store)
                    .environmentObject(plugins)
                    .environmentObject(pluginRegistry)
                    .environmentObject(packages)
                    .environmentObject(permissionMonitor)
                    .environmentObject(sync)
                    .environmentObject(appUpdater)
                    .environmentObject(downloadRequest)
                    .environmentObject(clipboardService)
            )
        }
        registry.setUserManifests(pluginStore.manifests)
    }

    /// pop:// 链接
    func open(_ url: URL) {
        guard let link = PopLink(url: url) else {
            coordinator.showToast(String(localized: "Pop 不认识这个链接：\(url.absoluteString)"), at: NSEvent.mouseLocation)
            return
        }
        switch link {
        case .settings, .pluginLibrary:
            perform(link)
        case .run, .ring, .clipboard:
            // 系统打开链接时会把 Pop 带到前台。选中的内容、结果要贴回去的地方都在原来的 App 里，
            // 所以等一下，Pop 还在前台的话先切回原来的 App 再处理
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    guard NSApp.isActive, let app = self.lastExternalApp, !app.isTerminated else {
                        self.perform(link)
                        return
                    }
                    app.activate(options: [])
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                        MainActor.assumeIsolated {
                            self?.perform(link)
                        }
                    }
                }
            }
        }
    }

    private func perform(_ link: PopLink) {
        switch link {
        case .run(let pluginID, let text, let files):
            coordinator.runFromLink(pluginID: pluginID, text: text, files: files)
        case .ring:
            coordinator.activateFromHotKey()
        case .clipboard:
            coordinator.showClipboardHistoryFromHotKey()
        case .settings(let tab):
            settingsWindow.show(tab: tab)
        case .pluginLibrary:
            settingsWindow.showPluginLibrary()
        }
    }

    func start() {
        UpdateLog.launched(version: UpdateChecker.currentVersion)
        AlertVolume.restorePendingIfNeeded()
        MainMenu.install()
        // 老用户迁移到插件包，装上设置里要的、缺着的插件包（Pop 更新后换成对应的版本）
        pluginManager.start()

        coordinator.openSettings = { [weak self] tab in
            self?.settingsWindow.show(tab: tab)
        }
        coordinator.openPluginLibrary = { [weak self] in
            self?.settingsWindow.showPluginLibrary()
        }
        coordinator.pluginManager = pluginManager
        trigger.delegate = coordinator
        PinBoard.shared.onToast = { [weak self] message, point in
            self?.coordinator.showToast(message, at: point)
        }
        PinBoard.shared.onRecognizedText = { [weak self] text, point in
            self?.coordinator.showRecognizedText(text, at: point)
        }

        statusItem.stateProvider = { [weak self] in
            guard let self else { return StatusItemController.State() }
            return StatusItemController.State(isPaused: self.coordinator.isPaused,
                                              isTrusted: self.permissions.isTrusted,
                                              pendingUpdateVersion: self.updater.release?.version,
                                              pinCount: PinBoard.shared.count,
                                              keepAwakeStatus: KeepAwake.shared.statusText(),
                                              shelfCount: FileShelf.shared.files.count,
                                              timerStatus: CountdownTimer.shared.statusText(),
                                              phoneShareStatus: PhoneShare.shared.statusText(),
                                              recordingElapsed: ScreenRecorder.shared.elapsedText())
        }
        statusItem.onCloseAllPins = {
            PinBoard.shared.closeAll()
        }
        statusItem.onStopKeepAwake = {
            KeepAwake.shared.stop()
        }
        statusItem.onShowShelf = {
            FileShelf.shared.show(near: NSEvent.mouseLocation)
        }
        statusItem.onCancelTimer = {
            CountdownTimer.shared.cancel()
        }
        statusItem.onStopPhoneShare = {
            PhoneShare.shared.stop()
        }
        statusItem.onStopRecording = {
            ScreenRecorder.shared.stop()
        }
        ScreenRecorder.shared.onTick = { [weak self] in
            self?.statusItem.refresh()
        }
        ScreenRecorder.shared.onFinish = { [weak self] result in
            self?.coordinator.recordingFinished(result)
        }
        ScrollCapture.shared.onFinish = { [weak self] result in
            self?.coordinator.scrollCaptureFinished(result)
        }
        PhoneShare.shared.onMessage = { [weak self] message in
            self?.coordinator.showToast(message, at: NSEvent.mouseLocation)
        }
        CountdownTimer.shared.onFinish = { [weak self] message in
            self?.coordinator.showToast(message, at: NSEvent.mouseLocation)
        }
        selectionWatcher.onSelection = { [weak self] point, clickCount in
            self?.coordinator.selectionMade(at: point, clickCount: clickCount)
        }
        selectionWatcher.onInteraction = { [weak self] in
            self?.coordinator.hideToolbar()
        }
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .sink { [weak self] notification in
                self?.coordinator.hideToolbar()
                if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                   app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                    self?.lastExternalApp = app
                }
            }
            .store(in: &cancellables)
        shakeDetector.onShake = { [weak self] point in
            guard let self, !self.coordinator.isPaused else { return }
            FileShelf.shared.show(near: point)
        }
        statusItem.onOpenSettings = { [weak self] in
            self?.settingsWindow.show()
        }
        statusItem.onShowClipboard = { [weak self] in
            self?.coordinator.showClipboardHistoryFromHotKey()
        }
        statusItem.onCheckForUpdates = { [weak self] in
            self?.settingsWindow.show(tab: .update)
            self?.updater.checkNow()
        }
        statusItem.onInstallUpdate = { [weak self] in
            self?.settingsWindow.show(tab: .update)
            self?.updater.checkAndInstall()
        }

        updater.notify = { release in
            Notifier.shared.showUpdate(version: release.version)
        }
        updater.onRelaunch = {
            NSApp.terminate(nil)
        }
        Notifier.shared.onOpen = { [weak self] in
            self?.settingsWindow.show(tab: .update)
        }
        Notifier.shared.onInstall = { [weak self] in
            self?.settingsWindow.show(tab: .update)
            self?.updater.checkAndInstall()
        }
        Notifier.shared.start()
        Notifier.shared.onOpenWhatsNew = { [weak self] in
            // 更新记录只有中文：英文界面打开网页上的版本说明
            if Localization.isChinese {
                self?.settingsWindow.show(tab: .update)
            } else {
                NSWorkspace.shared.open(Changelog.releasePage(UpdateChecker.currentVersion))
            }
        }
        // 刚更新过：发一条通知说这一版新增了什么（界面演示时不发）
        if !OverlayDemo.isEnabled,
           let summary = Changelog.whatsNew(current: UpdateChecker.currentVersion, releases: Changelog.bundled) {
            Notifier.shared.showWhatsNew(version: UpdateChecker.currentVersion, summary: summary)
        }
        statusItem.onTogglePause = { [weak self] in
            self?.togglePause()
        }
        statusItem.onGrantPermission = { [weak self] in
            Permissions.requestAccessibility()
            self?.settingsWindow.show(tab: .general)
        }

        // @Published 在赋值前发出通知，所以需要读取最新状态的地方都放到下一轮 RunLoop。
        settingsStore.$settings
            .receive(on: RunLoop.main)
            .sink { [weak self] settings in
                self?.apply(settings)
            }
            .store(in: &cancellables)

        permissions.$isTrusted
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] trusted in
                self?.permissionChanged(trusted)
            }
            .store(in: &cancellables)

        updater.$phase
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.statusItem.refresh()
            }
            .store(in: &cancellables)

        // 插件文件夹有变化（设置里编辑、手动修改、iCloud 同步）时刷新功能列表
        pluginStore.$manifests
            .receive(on: RunLoop.main)
            .sink { [weak self] manifests in
                self?.registry.setUserManifests(manifests)
            }
            .store(in: &cancellables)

        pluginStore.startWatching()
        permissions.start()
        cloudSync.start()

        // CI 截图用的界面演示：不检查更新、不弹设置窗口和授权提示，免得挡住浮窗
        if OverlayDemo.isEnabled {
            OverlayDemo.run(overlay: overlay, coordinator: coordinator, catalog: registry.catalog,
                            settings: settingsStore.settings)
            return
        }
        updater.startAutomaticChecks()

        // 第一次启动、或者还没授权时，主动打开设置窗口：Pop 没有程序坞图标，
        // 菜单栏图标也可能被刘海或其他图标挤掉，不弹窗的话用户会以为什么都没发生。
        let defaults = UserDefaults.standard
        let isFirstLaunch = !defaults.bool(forKey: Self.launchedBeforeKey)
        defaults.set(true, forKey: Self.launchedBeforeKey)
        if isFirstLaunch || !permissions.isTrusted {
            settingsWindow.show(tab: .general)
            if !permissions.isTrusted {
                Permissions.requestAccessibility()
            }
        }
    }

    private static let launchedBeforeKey = "pop.hasLaunchedBefore"

    func stop() {
        trigger.stop()
        hotKeys.unregisterAll()
    }

    func showSettings() {
        settingsWindow.show()
    }

    private func apply(_ settings: AppSettings) {
        trigger.configuration = MouseTrigger.Configuration(mode: settings.trigger.mode,
                                                           holdDuration: settings.trigger.holdDuration,
                                                           modifier: settings.trigger.modifier)
        hotKeys.register(.ring, preset: settings.trigger.hotKey) { [weak self] in
            self?.coordinator.activateFromHotKey()
        }
        let clipboardHotKey: HotKeyPreset = settings.clipboard.enabled ? settings.clipboard.hotKey : .none
        hotKeys.register(.clipboard, preset: clipboardHotKey) { [weak self] in
            self?.coordinator.showClipboardHistoryFromHotKey()
        }
        hotKeys.registerPluginHotKeys(settings.pluginHotKeys) { [weak self] pluginID in
            self?.coordinator.runFromHotKey(pluginID: pluginID)
        }
        clipboard.apply(settings.clipboard)
        if settings.trigger.shakeToOpenShelf {
            shakeDetector.start()
        } else {
            shakeDetector.stop()
        }
        if settings.toolbar.enabled {
            selectionWatcher.start()
        } else {
            selectionWatcher.stop()
            coordinator.hideToolbar()
        }
    }

    private func permissionChanged(_ trusted: Bool) {
        if trusted {
            startTriggerIfPossible()
        } else {
            trigger.stop()
            permissions.isTriggerRunning = false
        }
        statusItem.refresh()
    }

    /// 刚授权的一小段时间里 event tap 可能还创建不出来，隔一会儿重试；
    /// 一直失败时设置页会提示重启 Pop。
    private func startTriggerIfPossible() {
        guard permissions.isTrusted, !trigger.isRunning else { return }
        if trigger.start() {
            permissions.isTriggerRunning = true
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                MainActor.assumeIsolated {
                    self?.startTriggerIfPossible()
                }
            }
        }
    }

    private func togglePause() {
        coordinator.isPaused.toggle()
        if coordinator.isPaused {
            coordinator.endSession()
        }
        statusItem.refresh()
    }
}

/// 菜单栏 App 平时看不到主菜单，但设置窗口、结果卡片里的 ⌘C / ⌘V / ⌘W 等快捷键依赖它。
enum MainMenu {
    @MainActor
    static func install() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: String(localized: "关于 Pop"), action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: String(localized: "隐藏 Pop"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: String(localized: "退出 Pop"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: String(localized: "编辑"))
        editMenu.addItem(withTitle: String(localized: "撤销"), action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: String(localized: "重做"), action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: String(localized: "剪切"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: String(localized: "拷贝"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: String(localized: "粘贴"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: String(localized: "全选"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: String(localized: "窗口"))
        windowMenu.addItem(withTitle: String(localized: "关闭"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: String(localized: "最小化"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)

        NSApp.mainMenu = mainMenu
    }
}
