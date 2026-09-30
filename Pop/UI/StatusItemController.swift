import AppKit

/// 菜单栏图标和菜单。
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    struct State {
        var isPaused = false
        var isTrusted = true
        var pendingUpdateVersion: String?
        /// 屏幕上贴着几张贴图
        var pinCount = 0
        /// 保持唤醒的状态说明；没有保持唤醒时为 nil
        var keepAwakeStatus: String?
        /// 暂存架上有几个文件
        var shelfCount = 0
        /// 倒计时的状态说明；没在计时时为 nil
        var timerStatus: String?
        /// 「传到手机」的状态说明；没在共享时为 nil
        var phoneShareStatus: String?
        /// 录屏录了多久；没在录时为 nil
        var recordingElapsed: String?
    }

    var stateProvider: () -> State = { State() }
    var onOpenSettings: () -> Void = {}
    var onShowClipboard: () -> Void = {}
    var onCheckForUpdates: () -> Void = {}
    var onInstallUpdate: () -> Void = {}
    var onTogglePause: () -> Void = {}
    var onGrantPermission: () -> Void = {}
    var onCloseAllPins: () -> Void = {}
    var onStopKeepAwake: () -> Void = {}
    var onShowShelf: () -> Void = {}
    var onCancelTimer: () -> Void = {}
    var onStopPhoneShare: () -> Void = {}
    var onStopRecording: () -> Void = {}

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
        if state.recordingElapsed != nil {
            symbol = "record.circle"
        } else if state.pendingUpdateVersion != nil {
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
        if let elapsed = state.recordingElapsed {
            // 录屏的时候在图标旁边显示录了多久
            statusItem.button?.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            statusItem.button?.imagePosition = .imageLeading
            statusItem.button?.title = " " + elapsed
        } else {
            statusItem.button?.title = image == nil ? "Pop" : ""
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let state = stateProvider()
        if let elapsed = state.recordingElapsed {
            addItem(to: menu, title: "停止录屏（\(elapsed)）", action: #selector(stopRecording))
            menu.addItem(.separator())
        }
        if let version = state.pendingUpdateVersion {
            addItem(to: menu, title: "安装新版本 \(version)…", action: #selector(installUpdate))
            menu.addItem(.separator())
        }
        if !state.isTrusted {
            addItem(to: menu, title: "授予辅助功能权限…", action: #selector(grantPermission))
            menu.addItem(.separator())
        }
        addItem(to: menu, title: "剪贴板历史…", action: #selector(showClipboard))
        addItem(to: menu, title: state.shelfCount > 0 ? "暂存架（\(state.shelfCount)）" : "暂存架", action: #selector(showShelf))
        if state.pinCount > 0 {
            addItem(to: menu, title: "关闭全部贴图（\(state.pinCount)）", action: #selector(closeAllPins))
        }
        if let status = state.keepAwakeStatus {
            let info = NSMenuItem(title: status, action: nil, keyEquivalent: "")
            info.isEnabled = false
            menu.addItem(info)
            addItem(to: menu, title: "停止保持唤醒", action: #selector(stopKeepAwake))
        }
        if let status = state.timerStatus {
            let info = NSMenuItem(title: status, action: nil, keyEquivalent: "")
            info.isEnabled = false
            menu.addItem(info)
            addItem(to: menu, title: "取消计时", action: #selector(cancelTimer))
        }
        if let status = state.phoneShareStatus {
            let info = NSMenuItem(title: status, action: nil, keyEquivalent: "")
            info.isEnabled = false
            menu.addItem(info)
            addItem(to: menu, title: "停止传到手机", action: #selector(stopPhoneShare))
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
    @objc private func showClipboard() {
        // 等菜单收起、焦点回到原来的 App 再弹出面板
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.onShowClipboard()
            }
        }
    }
    @objc private func checkForUpdates() { onCheckForUpdates() }
    @objc private func installUpdate() { onInstallUpdate() }
    @objc private func togglePause() { onTogglePause() }
    @objc private func grantPermission() { onGrantPermission() }
    @objc private func closeAllPins() { onCloseAllPins() }
    @objc private func stopKeepAwake() { onStopKeepAwake() }
    @objc private func showShelf() { onShowShelf() }
    @objc private func cancelTimer() { onCancelTimer() }
    @objc private func stopPhoneShare() { onStopPhoneShare() }
    @objc private func stopRecording() { onStopRecording() }
}
