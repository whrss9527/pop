#if POP_UI_FIXTURE
import AppKit
import SwiftUI

/// 只由 PopUIFixture target 编译；不构造 AppDelegate/AppController，不启动任何系统服务。
@main
@MainActor
enum UIFixtureMain {
    private static var delegate: UIFixtureDelegate?
    static func main() {
        precondition(Bundle.main.bundleIdentifier == "io.github.whrss9527.pop.ui-fixture")
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let owner = UIFixtureDelegate()
        delegate = owner
        app.delegate = owner
        app.run()
    }
}

@MainActor
private final class UIFixtureDelegate: NSObject, NSApplicationDelegate {
    private var window: UIFixtureWindow?
    func applicationDidFinishLaunching(_ notification: Notification) {
        let state = UIFixtureState()
        let window = UIFixtureWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 760),
                                     styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Pop UI Fixture — isolated / offline"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: UIFixtureView(state: state))
        window.onKey = { [weak state] in state?.handleKey($0) ?? false }
        self.window = window
        let menu = NSMenu()
        let item = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Pop UI Fixture", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = appMenu
        menu.addItem(item)
        NSApp.mainMenu = menu
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

/// 仅处理本窗口送来的事件，不装本地/全局事件监听，也不合成系统输入。
private final class UIFixtureWindow: NSWindow {
    var onKey: ((NSEvent) -> Bool)?
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, onKey?(event) == true { return }
        super.sendEvent(event)
    }
}

@MainActor
private final class UIFixtureState: ObservableObject {
    @Published var scene = 0
    @Published var dark = false
    @Published var reduceMotion = false
    @Published var count = 8
    @Published var loading = false
    @Published var longNames = false
    @Published var ring: RingViewModel
    @Published var chooser: PluginChooserModel
    @Published var notice = "Actions only update this message; no plug-in is executed."
    @Published var libraryOpen = false
    @Published var libraryMode = 0
    @Published var library: PluginLibraryModel?
    let presentation = OverlayPresentation(phase: .shown)
    let root: URL
    let defaults: UserDefaults
    let store: SettingsStore
    let pluginStore: PluginStore
    let catalog: [PluginInfo]
    private let session: URLSession

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--fixture-root"), arguments.indices.contains(index + 1) {
            root = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
        } else {
            root = FileManager.default.temporaryDirectory.appending(path: "PopUIFixture-\(UUID().uuidString)", directoryHint: .isDirectory)
        }
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let suite = "io.github.whrss9527.pop.ui-fixture.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        store = SettingsStore(defaults: defaults)
        pluginStore = PluginStore(directory: root.appending(path: "Plugins", directoryHint: .isDirectory), defaults: defaults)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [UIFixtureURLProtocol.self]
        session = URLSession(configuration: config)
        UIFixtureNetwork.shared.configure(root: root)
        // 只读取描述；不装载插件包、创建插件管理器或执行插件。
        let core = BuiltinPlugins.make().map(\.info)
        let existing = Set(core.map(\.id))
        catalog = core + PluginCatalog.all.compactMap { package in
            guard let id = package.functions.first, !existing.contains(id) else { return nil }
            return PluginInfo(id: id, name: package.name, symbol: package.symbol, summary: package.summary, accepts: [])
        }
        ring = Self.makeRing(Array(catalog.prefix(8)), loading: false)
        chooser = PluginChooserModel(plugins: catalog)
        chooser.onRun = { [weak self] info in self?.notice = "Selected: \(info.name) [\(info.id)]" }
        print("POP_UI_FIXTURE_ROOT=\(root.path)")
    }

    private static func makeRing(_ entries: [PluginInfo], loading: Bool) -> RingViewModel {
        RingViewModel(layout: RingLayout(slots: entries.map { Optional($0.id) }), catalog: entries,
                      installed: Set(entries.map(\.id)), content: loading ? nil : ContentClassifier.classify(.text("Liquid glass")))
    }

    func resetRing() {
        var entries = Array(catalog.prefix(count))
        if longNames {
            entries = entries.enumerated().map { index, info in
                PluginInfo(id: info.id, name: index % 2 == 0 ? "Translate selected text into another language" : "选中文字后转换为方便阅读的长名称示例",
                           symbol: info.symbol, summary: info.summary, accepts: info.accepts)
            }
        }
        ring = Self.makeRing(entries, loading: loading)
        notice = "Ring reset — production RingMenuView / RingViewModel"
    }

    func openLibrary() {
        let mode = ["slow", "retry", "ready"][libraryMode]
        let url = URL(string: "https://fixture.invalid/\(mode)/index.json")!
        library = PluginLibraryModel(sources: [url], session: session, defaults: defaults)
        libraryOpen = true
    }

    /// 键盘分发是 fixture 适配器；列表直接复用生产 handleKey，圆盘复用生产选择/移动模型。
    func handleKey(_ event: NSEvent) -> Bool {
        guard !libraryOpen else { return false }
        if scene == 1 { return chooser.handleKey(event) }
        guard scene == 0 else { return false }
        switch event.keyCode {
        case 123, 126: ring.setHovered(ring.nextVisibleSlot(by: -1)); return true
        case 124, 125: ring.setHovered(ring.nextVisibleSlot(by: 1)); return true
        case 36, 76:
            if let info = ring.selectablePlugin(at: ring.hovered), let index = ring.hovered {
                ring.commit(index)
                notice = "Selected: \(info.name) [\(info.id)]"
            }
            return true
        case 53: ring.resetSelection(); return true
        default: return false
        }
    }

    /// 与生产语言设置一样重开后生效，但只用新进程参数，不写系统或生产 App 偏好。
    func language(_ identifier: String) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.arguments = ["--fixture-root", root.path, "-AppleLanguages", "(\(identifier))"]
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            DispatchQueue.main.async {
                if error == nil { NSApp.terminate(nil) }
            }
        }
    }
}

private struct UIFixtureView: View {
    @ObservedObject var state: UIFixtureState
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Picker("Scene", selection: $state.scene) {
                    Text(verbatim: "Ring / 圆盘").tag(0)
                    Text(verbatim: "Features / 全部功能").tag(1)
                    Text(verbatim: "Library / 插件库").tag(2)
                }.pickerStyle(.segmented)
                Toggle("Dark", isOn: $state.dark).toggleStyle(.switch)
                Button("中文") { state.language("zh-Hans") }
                Button("English") { state.language("en") }
            }
            Text(verbatim: "Language buttons reopen this fixture. No AppController, clipboard, permissions, cloud, updater, or global event monitors.")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            if state.scene == 0 {
                HStack {
                    Picker("Slots", selection: $state.count) {
                        ForEach([4, 8, 12], id: \.self) { Text("\($0)").tag($0) }
                    }.frame(width: 140)
                    Toggle("Long names", isOn: $state.longNames)
                    Toggle("Loading", isOn: $state.loading)
                    Toggle("Reduce Motion", isOn: $state.reduceMotion)
                    Button("Reset") { state.resetRing() }
                }
                RingMenuView(model: state.ring, presentation: state.presentation, reduceMotionOverride: state.reduceMotion)
                    .onContinuousHover { phase in
                        if case .active(let location) = phase {
                            let size = state.ring.geometry.diameter + OverlayController.ringPadding * 2
                            state.ring.updateHover(offset: CGVector(dx: location.x - size / 2, dy: size / 2 - location.y))
                        } else { state.ring.setHovered(nil) }
                    }
                    .onTapGesture {
                        if let index = state.ring.hovered, let info = state.ring.selectablePlugin(at: index) {
                            state.ring.commit(index)
                            state.notice = "Selected: \(info.name) [\(info.id)]"
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if state.scene == 1 {
                PluginChooserView(model: state.chooser, onClose: { state.scene = 0 })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 20) {
                    Picker("Fake response", selection: $state.libraryMode) {
                        Text("5 seconds").tag(0)
                        Text("Fail once, then succeed").tag(1)
                        Text("Ready").tag(2)
                    }.frame(width: 360)
                    Button("Open production plugin library") { state.openLibrary() }
                    Text(verbatim: "Only URLProtocol fixtures. Installs write to a temporary plug-in directory; external links are blocked.")
                    Text(verbatim: state.root.path).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            Text(verbatim: state.notice).font(.caption).frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .frame(width: 900, height: 760)
        .preferredColorScheme(state.dark ? .dark : .light)
        .environment(\.openURL, OpenURLAction { _ in .discarded })
        .onChange(of: state.count) { _, _ in state.resetRing() }
        .onChange(of: state.longNames) { _, _ in state.resetRing() }
        .onChange(of: state.loading) { _, _ in state.resetRing() }
        .sheet(isPresented: $state.libraryOpen) {
            if let model = state.library {
                PluginLibraryView(store: state.store, pluginStore: state.pluginStore, model: model,
                                  onClose: { state.libraryOpen = false })
                    .environment(\.openURL, OpenURLAction { _ in .discarded })
            }
        }
    }
}

/// 请求日志只写本 fixture 临时目录；URLProtocol 中所有 URL 都被截获，没有真实传输。
private final class UIFixtureNetwork {
    static let shared = UIFixtureNetwork()
    private let lock = NSLock()
    private var url: URL?
    private var counts: [String: Int] = [:]
    func configure(root: URL) { url = root.appending(path: "requests.log") }
    @discardableResult func record(_ event: String, path: String) -> Int {
        lock.lock(); defer { lock.unlock() }
        if event == "start" { counts[path, default: 0] += 1 }
        if let url {
            let data = Data("\(event) \(path)\n".utf8)
            if !FileManager.default.fileExists(atPath: url.path) { try? data.write(to: url) }
            else if let file = try? FileHandle(forWritingTo: url) {
                try? file.seekToEnd(); try? file.write(contentsOf: data); try? file.close()
            }
        }
        return counts[path, default: 0]
    }
}

private final class UIFixtureURLProtocol: URLProtocol {
    private var pending: DispatchWorkItem?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        let count = UIFixtureNetwork.shared.record("start", path: url.path)
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if url.path.contains("/retry/"), count == 1 {
                UIFixtureNetwork.shared.record("failure", path: url.path)
                self.client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
                return
            }
            let manifest = Data(#"{"id":"fixture-search","name":"Fixture Search","action":{"type":"url","url":"https://fixture.invalid/search?q={text}"}}"#.utf8)
            let index: [String: Any] = ["format": 1, "plugins": [["id": "fixture-search", "name": "示例搜索", "summary": "只保存到临时目录，不会执行", "author": "UI Fixture", "type": "url", "url": "plugin.json", "sha256": Digests.sha256(manifest), "localized": ["en": ["name": "Fixture Search", "summary": "Saved only in the temporary directory; never executed"]]]]]
            let data = url.lastPathComponent == "index.json" ? (try! JSONSerialization.data(withJSONObject: index)) : manifest
            UIFixtureNetwork.shared.record("response", path: url.path)
            self.client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: data)
            self.client?.urlProtocolDidFinishLoading(self)
        }
        pending = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + (url.path.contains("/slow/") ? 5 : 0.25), execute: work)
    }
    override func stopLoading() {
        pending?.cancel()
        if let url = request.url { UIFixtureNetwork.shared.record("cancel", path: url.path) }
    }
}
#endif
