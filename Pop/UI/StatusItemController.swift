import AppKit

/// 菜单栏图标和菜单。
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    struct State {
        var isPaused = false
        var isTrusted = true
        var pendingUpdateVersion: String?
    }

    var stateProvider: () -> State = { State() }
    var onOpenSettings: () -> Void = {}
    var onCheckForUpdates: () -> Void = {}
    var onTogglePause: () -> Void = {}
    var onGrantPermission: () -> Void = {}

    private let statusItem: NSStatusItem

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        refresh()
    }

    func refresh() {
        let state = stateProvider()
        let symbol: String
        if state.pendingUpdateVersion != nil {
            symbol = "arrow.down.circle"
        } else if !state.isTrusted {
            symbol = "exclamationmark.circle"
        } else if state.isPaused {
            symbol = "pause.circle"
        } else {
            symbol = "circle.circle"
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Pop")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.title = image == nil ? "Pop" : ""
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let state = stateProvider()
        if let version = state.pendingUpdateVersion {
            addItem(to: menu, title: "安装新版本 \(version)…", action: #selector(checkForUpdates))
            menu.addItem(.separator())
        }
        if !state.isTrusted {
            addItem(to: menu, title: "授予辅助功能权限…", action: #selector(grantPermission))
            menu.addItem(.separator())
        }
        addItem(to: menu, title: state.isPaused ? "恢复 Pop" : "暂停 Pop", action: #selector(togglePause))
        menu.addItem(.separator())
        addItem(to: menu, title: "设置…", action: #selector(openSettings), key: ",")
        addItem(to: menu, title: "检查更新…", action: #selector(checkForUpdates))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出 Pop", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func addItem(to menu: NSMenu, title: String, action: Selector, key: String = "") {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
    }

    @objc private func openSettings() { onOpenSettings() }
    @objc private func checkForUpdates() { onCheckForUpdates() }
    @objc private func togglePause() { onTogglePause() }
    @objc private func grantPermission() { onGrantPermission() }
}
