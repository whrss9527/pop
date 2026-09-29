import AppKit
import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable, Hashable {
    case general
    case ring
    case plugins
    case rules
    case hotKeys
    case clipboard
    case translation
    case ai
    case sync
    case update

    var id: String { rawValue }
}

@MainActor
final class SettingsNavigation: ObservableObject {
    @Published var tab: SettingsTab = .general
}

/// 设置窗口用 AppKit 自己管理：菜单栏 App 从 AppKit 代码里打开 SwiftUI Settings 场景并不可靠。
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    let navigation = SettingsNavigation()
    private var window: NSWindow?
    private let makeContent: (SettingsNavigation) -> AnyView

    init(makeContent: @escaping (SettingsNavigation) -> AnyView) {
        self.makeContent = makeContent
        super.init()
    }

    var isVisible: Bool { window?.isVisible ?? false }

    func show(tab: SettingsTab? = nil) {
        if let tab {
            navigation.tab = tab
        }
        let window = self.window ?? makeWindow()
        // 上次关掉时有一部分在屏幕外面（换了显示器、分辨率变了），这次重新居中
        if !window.isVisible, let screen = window.screen ?? NSScreen.main, !screen.visibleFrame.contains(window.frame) {
            window.center()
        }
        // Pop 平时只在菜单栏（LSUIElement），系统启动它时不会把它切到前台，
        // 这时普通的 makeKeyAndOrderFront 会把窗口放到当前 App 的窗口后面，用户根本看不到。
        // 所以打开设置时临时变成普通 App（程序坞里出现图标、可以 ⌘Tab 切换），
        // 并且无条件把窗口放到最前面；关闭设置窗口后再变回菜单栏 App。
        NSApp.setActivationPolicy(.regular)
        window.orderFrontRegardless()
        window.makeKey()
        NSApp.activate()
    }

    private func makeWindow() -> NSWindow {
        let controller = NSHostingController(rootView: makeContent(navigation))
        let window = NSWindow(contentViewController: controller)
        window.title = "Pop 设置"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        // SwiftUI 的内容这时还没排版，窗口可能还是很小的尺寸；先定好大小再居中，
        // 否则窗口会从屏幕中间往右下方长大，小屏幕上有一部分跑到屏幕外面
        window.setContentSize(SettingsRootView.size)
        window.center()
        self.window = window
        return window
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

struct SettingsRootView: View {
    /// 设置窗口内容的大小
    static let size = CGSize(width: 840, height: 600)

    @ObservedObject var navigation: SettingsNavigation
    @EnvironmentObject var registry: PluginRegistry

    var body: some View {
        let catalog = registry.catalog
        TabView(selection: $navigation.tab) {
            GeneralSettingsView()
                .tabItem { Label("通用", systemImage: "gearshape") }
                .tag(SettingsTab.general)
            RingSettingsView(catalog: catalog)
                .tabItem { Label("圆盘", systemImage: "circle.circle") }
                .tag(SettingsTab.ring)
            PluginsSettingsView(catalog: catalog)
                .tabItem { Label("功能", systemImage: "square.grid.2x2") }
                .tag(SettingsTab.plugins)
            RulesSettingsView(catalog: catalog)
                .tabItem { Label("直达规则", systemImage: "arrow.turn.down.right") }
                .tag(SettingsTab.rules)
            HotKeySettingsView(catalog: catalog)
                .tabItem { Label("快捷键", systemImage: "keyboard") }
                .tag(SettingsTab.hotKeys)
            ClipboardSettingsView()
                .tabItem { Label("剪贴板", systemImage: "list.clipboard") }
                .tag(SettingsTab.clipboard)
            TranslationSettingsView()
                .tabItem { Label("翻译", systemImage: "character.bubble") }
                .tag(SettingsTab.translation)
            AISettingsView()
                .tabItem { Label("AI", systemImage: "sparkles") }
                .tag(SettingsTab.ai)
            SyncSettingsView()
                .tabItem { Label("同步", systemImage: "icloud") }
                .tag(SettingsTab.sync)
            UpdateSettingsView()
                .tabItem { Label("更新", systemImage: "arrow.down.circle") }
                .tag(SettingsTab.update)
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }
}

extension SettingsStore {
    /// 把设置里的某个字段变成 SwiftUI Binding，写入时走 update（会记录修改时间并触发同步）。
    func binding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { self.settings[keyPath: keyPath] },
            set: { newValue in self.update { $0[keyPath: keyPath] = newValue } }
        )
    }
}

enum AppInfo {
    static func url(for bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    static func name(for bundleID: String) -> String {
        guard let url = url(for: bundleID) else { return bundleID }
        let name = FileManager.default.displayName(atPath: url.path(percentEncoded: false))
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }

    static func icon(for bundleID: String) -> NSImage? {
        guard let url = url(for: bundleID) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false))
    }
}
