import AppKit
@testable import Pop

/// 插件包「快捷键一览」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopMenuShortcutsEntry)
final class MenuShortcutsEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [MenuShortcutsPlugin()]
    }

    @MainActor static func didLoad(_ host: PluginHost.Registrar) {
        // CI 截图：一份写好的示例菜单，不去读真的 App
        host.addDemoScene(PluginHost.DemoScene(name: "menuShortcuts", after: "textImage", delay: 1.4, hold: 0, show: { demo in
            let shortcuts = MenuShortcutsModel(appName: "备忘录")
            shortcuts.load(MenuShortcutsEntry.sampleMenus)
            demo.overlay.showCard(MenuShortcutsView(model: shortcuts, onClose: {}), anchor: demo.center)
            return demo.cardRegion
        }))
    }

    /// 快捷键一览演示用的菜单：备忘录的一部分菜单
    static var sampleMenus: [MenuShortcuts.Node] {
        func entry(_ title: String, _ shortcut: String? = nil, enabled: Bool = true) -> MenuShortcuts.Node {
            MenuShortcuts.Node(title: title, shortcut: shortcut, enabled: enabled)
        }
        return [
            MenuShortcuts.Node(title: "备忘录", shortcut: nil, enabled: true, children: [
                entry("关于备忘录"), entry("设置…", "⌘,"), entry("隐藏备忘录", "⌘H"), entry("退出备忘录", "⌘Q"),
            ]),
            MenuShortcuts.Node(title: "文件", shortcut: nil, enabled: true, children: [
                entry("新建备忘录", "⌘N"), entry("新建文件夹", "⇧⌘N"), entry("关闭", "⌘W"), entry("导出为 PDF…"), entry("打印…", "⌘P"),
            ]),
            MenuShortcuts.Node(title: "编辑", shortcut: nil, enabled: true, children: [
                entry("撤销", "⌘Z", enabled: false), entry("重做", "⇧⌘Z", enabled: false), entry("剪切", "⌘X"), entry("拷贝", "⌘C"),
                entry("粘贴", "⌘V"), entry("全选", "⌘A"),
                MenuShortcuts.Node(title: "查找", shortcut: nil, enabled: true, children: [entry("查找…", "⌘F"), entry("查找下一个", "⌘G")]),
            ]),
            MenuShortcuts.Node(title: "格式", shortcut: nil, enabled: true, children: [
                entry("标题", "⇧⌘T"), entry("正文", "⇧⌘B"), entry("核对清单", "⇧⌘L"), entry("表格", "⌥⌘T"), entry("粗体", "⌘B"),
            ]),
        ]
    }
}

struct MenuShortcutsPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.menuShortcuts, name: String(localized: "快捷键一览"), symbol: "command",
                          summary: String(localized: "列出当前 App 菜单里的所有快捷键，可以搜索，点一项直接执行"), accepts: [])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        let appName = context.sourceAppName ?? String(localized: "当前 App")
        let pid = context.sourcePID
        return .present(PluginPresentation { session in
            // 在后台读唤起时前台 App 的菜单（菜单多的 App 要一会儿），选一项就让那个 App 执行它
            let model = MenuShortcutsModel(appName: appName)
            session.showCard(MenuShortcutsView(model: model, onClose: { session.end() }),
                             keyHandler: { event in model.handleKey(event) })
            guard let pid, pid != ProcessInfo.processInfo.processIdentifier else {
                model.fail(String(localized: "不知道要看哪个 App 的菜单：先点一下那个 App 的窗口，再唤起 Pop"))
                return
            }
            guard Permissions.isAccessibilityTrusted else {
                model.fail(String(localized: "要先在「系统设置 → 隐私与安全性 → 辅助功能」里允许 Pop，才能读到菜单"))
                return
            }
            model.onRun = { item in Self.press(item, pid: pid, session: session) }
            Task { @MainActor [weak model] in
                let nodes = await runInBackground { () -> [MenuShortcuts.Node] in
                    let menus = MenuShortcuts.read(pid: pid)
                    // 搜索用的拼音也在后台算好：大的 App 有几百个菜单项，列出来时不用在主线程上一项项转
                    for item in MenuShortcuts.flatten(menus) {
                        _ = MenuShortcuts.searchKeys(for: item)
                    }
                    return menus
                }
                guard let model, session.isCurrent else { return }
                model.load(nodes)
            }
        })
    }

    /// 先收起浮窗、让那个 App 回到前台，再点它的菜单项
    @MainActor static func press(_ item: MenuShortcuts.Item, pid: pid_t, session: PluginSession) {
        session.end()
        NSRunningApplication(processIdentifier: pid)?.activate()
        let path = item.path
        let title = item.title
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000)
            let pressed = await runInBackground { MenuShortcuts.press(pid: pid, path: path) }
            if !pressed {
                // 这期间又唤起了 Pop 的话不会去打断
                session.finish(toast: String(localized: "没能执行「\(title)」，菜单可能已经变了"))
            }
        }
    }
}
