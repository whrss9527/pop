import AppKit
import Combine
import SwiftUI

/// 组装各个模块，并根据设置和权限状态启动/停止它们。
@MainActor
final class AppController {
    let settingsStore: SettingsStore
    let registry: PluginRegistry
    let permissions: PermissionMonitor
    let overlay: OverlayController
    let downloads: TranslationDownloadRequest
    let updates: UpdateManager
    let cloudSync: CloudSync
    let trigger: MouseTrigger
    let hotKeys: HotKeyManager
    let coordinator: PopCoordinator
    let statusItem: StatusItemController
    let settingsWindow: SettingsWindowController

    private var cancellables = Set<AnyCancellable>()

    init() {
        settingsStore = SettingsStore()
        registry = PluginRegistry()
        permissions = PermissionMonitor()
        overlay = OverlayController()
        downloads = TranslationDownloadRequest()
        updates = UpdateManager()
        cloudSync = CloudSync(settingsStore: settingsStore)
        trigger = MouseTrigger()
        hotKeys = HotKeyManager()
        coordinator = PopCoordinator(settingsStore: settingsStore, registry: registry, overlay: overlay, downloads: downloads)
        statusItem = StatusItemController()

        let catalog = registry.catalog
        let store = settingsStore
        let permissionMonitor = permissions
        let sync = cloudSync
        let updateManager = updates
        let downloadRequest = downloads
        settingsWindow = SettingsWindowController { navigation in
            AnyView(
                SettingsRootView(navigation: navigation, catalog: catalog)
                    .environmentObject(store)
                    .environmentObject(permissionMonitor)
                    .environmentObject(sync)
                    .environmentObject(updateManager)
                    .environmentObject(downloadRequest)
            )
        }
    }

    func start() {
        AlertVolume.restorePendingIfNeeded()
        MainMenu.install()

        coordinator.openSettings = { [weak self] tab in
            self?.settingsWindow.show(tab: tab)
        }
        trigger.delegate = coordinator
        hotKeys.onPress = { [weak self] in
            self?.coordinator.activateFromHotKey()
        }

        statusItem.stateProvider = { [weak self] in
            guard let self else { return StatusItemController.State() }
            return StatusItemController.State(isPaused: self.coordinator.isPaused,
                                              isTrusted: self.permissions.isTrusted,
                                              pendingUpdateVersion: self.updates.pendingUpdateVersion)
        }
        statusItem.onOpenSettings = { [weak self] in
            self?.settingsWindow.show()
        }
        statusItem.onCheckForUpdates = { [weak self] in
            self?.updates.checkForUpdates()
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

        updates.$pendingUpdateVersion
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.statusItem.refresh()
            }
            .store(in: &cancellables)

        permissions.start()
        updates.start()
        cloudSync.start()

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
        hotKeys.unregister()
    }

    func showSettings() {
        settingsWindow.show()
    }

    private func apply(_ settings: AppSettings) {
        trigger.configuration = MouseTrigger.Configuration(mode: settings.trigger.mode,
                                                           holdDuration: settings.trigger.holdDuration,
                                                           modifier: settings.trigger.modifier)
        hotKeys.register(settings.trigger.hotKey)
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
        appMenu.addItem(withTitle: "关于 Pop", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "隐藏 Pop", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "退出 Pop", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "窗口")
        windowMenu.addItem(withTitle: "关闭", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)

        NSApp.mainMenu = mainMenu
    }
}
