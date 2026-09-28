import AppKit
import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable, Hashable {
    case general
    case ring
    case plugins
    case rules
    case translation
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
final class SettingsWindowController {
    let navigation = SettingsNavigation()
    private var window: NSWindow?
    private let makeContent: (SettingsNavigation) -> AnyView

    init(makeContent: @escaping (SettingsNavigation) -> AnyView) {
        self.makeContent = makeContent
    }

    func show(tab: SettingsTab? = nil) {
        if let tab {
            navigation.tab = tab
        }
        if window == nil {
            let controller = NSHostingController(rootView: makeContent(navigation))
            let window = NSWindow(contentViewController: controller)
            window.title = "Pop 设置"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsRootView: View {
    @ObservedObject var navigation: SettingsNavigation
    let catalog: [PluginInfo]

    var body: some View {
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
            TranslationSettingsView()
                .tabItem { Label("翻译", systemImage: "character.bubble") }
                .tag(SettingsTab.translation)
            SyncSettingsView()
                .tabItem { Label("同步", systemImage: "icloud") }
                .tag(SettingsTab.sync)
            UpdateSettingsView()
                .tabItem { Label("更新", systemImage: "arrow.down.circle") }
                .tag(SettingsTab.update)
        }
        .frame(width: 760, height: 580)
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
