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

    var title: String {
        switch self {
        case .general: return "通用"
        case .ring: return "圆盘"
        case .plugins: return "功能"
        case .rules: return "直达规则"
        case .hotKeys: return "快捷键"
        case .clipboard: return "剪贴板"
        case .translation: return "翻译"
        case .ai: return "AI"
        case .sync: return "同步"
        case .update: return "更新"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .ring: return "circle.circle"
        case .plugins: return "square.grid.2x2"
        case .rules: return "arrow.turn.down.right"
        case .hotKeys: return "keyboard"
        case .clipboard: return "list.clipboard"
        case .translation: return "character.bubble"
        case .ai: return "sparkles"
        case .sync: return "icloud"
        case .update: return "arrow.down.circle"
        }
    }
}

@MainActor
final class SettingsNavigation: ObservableObject {
    @Published var tab: SettingsTab = .general
    /// 「功能」页上打开着插件库
    @Published var showsPluginLibrary = false
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

    /// 打开「功能」页上的插件库
    func showPluginLibrary() {
        show(tab: .plugins)
        navigation.showsPluginLibrary = true
    }

    func show(tab: SettingsTab? = nil) {
        if let tab {
            navigation.tab = tab
        }
        let window = self.window ?? makeWindow()
        let wasVisible = window.isVisible
        // 上次关掉时有一部分在屏幕外面（换了显示器、分辨率变了），这次重新居中
        if !wasVisible, let screen = window.screen ?? NSScreen.main, !screen.visibleFrame.contains(window.frame) {
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
        if !wasVisible {
            // 打开了「键盘导航」时，系统会把焦点放到第一个控件上、画一圈蓝色的焦点环；
            // 刚打开设置时不给任何控件焦点，按 Tab 再出现
            window.makeFirstResponder(nil)
            DispatchQueue.main.async { [weak window] in
                MainActor.assumeIsolated {
                    _ = window?.makeFirstResponder(nil)
                }
            }
        }
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
        VStack(spacing: 0) {
            SettingsTabBar(selection: $navigation.tab)
            Divider()
            page(navigation.tab)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }

    @ViewBuilder
    private func page(_ tab: SettingsTab) -> some View {
        let catalog = registry.catalog
        switch tab {
        case .general: GeneralSettingsView()
        case .ring: RingSettingsView(catalog: catalog)
        case .plugins: PluginsSettingsView(catalog: catalog, showsLibrary: $navigation.showsPluginLibrary)
        case .rules: RulesSettingsView(catalog: catalog)
        case .hotKeys: HotKeySettingsView(catalog: catalog)
        case .clipboard: ClipboardSettingsView()
        case .translation: TranslationSettingsView()
        case .ai: AISettingsView()
        case .sync: SyncSettingsView()
        case .update: UpdateSettingsView()
        }
    }
}

/// 设置窗口顶上的一排页面：图标下面写名字，选中的那一个衬一块圆角底色、图标用强调色。
/// 自己画而不用 TabView 的分段标签：系统的分段标签在一些系统版本上选中的底色画不满。
struct SettingsTabBar: View {
    @Binding var selection: SettingsTab

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(SettingsTab.allCases.enumerated()), id: \.element) { index, tab in
                SettingsTabButton(tab: tab, isSelected: tab == selection, shortcut: Self.shortcut(for: index)) {
                    selection = tab
                }
            }
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
    }

    /// ⌘1–⌘9 切到前九页，⌘0 是第十页
    static func shortcut(for index: Int) -> Character? {
        switch index {
        case 0..<9: return Character(String(index + 1))
        case 9: return "0"
        default: return nil
        }
    }
}

private struct SettingsTabButton: View {
    let tab: SettingsTab
    let isSelected: Bool
    let shortcut: Character?
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let fill = isSelected ? Color.primary.opacity(0.1) : (hovering ? Color.primary.opacity(0.05) : Color.clear)
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 17))
                    .frame(height: 21)
                Text(tab.title)
                    .font(.system(size: 11))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            .frame(width: 70, height: 48)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(fill))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // 页面按钮不接收键盘焦点：焦点环会留在打开设置时的第一个按钮上，看起来像两页都选中了
        .focusable(false)
        .focusEffectDisabled()
        .keyboardShortcut(shortcut.map { KeyboardShortcut(KeyEquivalent($0), modifiers: .command) })
        .help(shortcut.map { "\(tab.title)（⌘\($0)）" } ?? tab.title)
        .onHover { hovering = $0 }
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? AccessibilityTraits.isSelected : AccessibilityTraits())
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
