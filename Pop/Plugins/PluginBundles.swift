import AppKit
import os

/// 插件包的入口。
///
/// 插件包是 PluginBundles/ 下面单独编译的 .bundle，装在「~/Library/Application Support/Pop/PluginBundles」里，由 Pop 在启动时
/// （或者刚装上时）装载。插件包的 Info.plist 里 NSPrincipalClass 指向一个实现了这个协议的类；PopPluginID 是插件包的 ID；
/// PopBuildID 必须和 Pop 自己的一样：插件包直接用 Pop 里的类型，只能和同一次构建出来的 Pop 一起用。
protocol PopPluginBundle: AnyObject {
    /// 插件包提供的功能
    static func makePlugins() -> [any PopPlugin]
    /// 装载以后调用一次：在这里注册录屏时不录的窗口、演示模式的步骤这些
    @MainActor static func didLoad(_ host: PluginHost.Registrar)
    /// 卸载之前调用：关掉插件包开着的窗口、停掉它在后台做的事。代码要等 Pop 下次启动才真正卸掉
    @MainActor static func willUninstall()
}

extension PopPluginBundle {
    @MainActor static func didLoad(_ host: PluginHost.Registrar) {}
    @MainActor static func willUninstall() {}
}

/// 插件包挂进 Pop 的地方。按插件包记下谁注册了什么，卸载时一起拿掉。
@MainActor
final class PluginHost {
    static let shared = PluginHost()

    /// 演示模式（CI 截图）里插件包加的一步
    struct DemoScene {
        /// 截图步骤的名字，和 scripts/overlay-screenshots.sh 里的计划对应
        let name: String
        /// 排在演示的哪一步后面
        let after: String
        /// 排在同一步后面的几个插件包步骤按它从小到大排
        var order = 0
        /// 显示之前先停多久、显示以后停多久再收起（乘上动画放慢的倍数）；最多停到截图拍完（见 OverlayDemo）
        var delay = 0.4
        var hold = 1.4
        /// 显示出来，返回要截的区域（AppKit 屏幕坐标）；返回 nil 时沿用上一次的区域。可以先等一会儿（比如识别示例图片）
        let show: @MainActor (DemoContext) async -> CGRect?
        var hide: @MainActor () -> Void = {}
    }

    /// 演示步骤显示时用得上的：屏幕、演示里的唤起点（卡片从这里弹出来）、浮窗、卡片的截图区域
    @MainActor
    struct DemoContext {
        let screen: NSScreen
        let center: CGPoint
        let overlay: OverlayController
        let cardRegion: CGRect
    }

    /// 交给插件包注册用：注册的东西都记在这个插件包名下
    @MainActor
    struct Registrar {
        let owner: String

        /// 录屏时不录进去的窗口（插件包自己的浮窗，比如提词器）：返回此刻要排除的窗口编号
        func excludeFromRecording(_ windows: @escaping @MainActor () -> [Int]) {
            PluginHost.shared.recordingExclusions.append((owner, windows))
        }

        func addDemoScene(_ scene: DemoScene) {
            PluginHost.shared.scenes.append((owner, scene))
        }
    }

    private var recordingExclusions: [(owner: String, windows: @MainActor () -> [Int])] = []
    private var scenes: [(owner: String, scene: DemoScene)] = []

    /// 用某个功能处理这些文件，结果在指针的位置弹出来。插件包自己的小窗（不在浮窗里）要接着交给别的功能时用，
    /// 比如录音存好后「转成文字」。Pop 启动时接上
    var runFunction: @MainActor (_ pluginID: String, _ files: [URL]) -> Void = { _, _ in }

    /// 录屏时不录进去的窗口编号
    var windowsExcludedFromRecording: [Int] {
        recordingExclusions.flatMap { $0.windows() }
    }

    /// 排在演示的这一步后面的插件包步骤
    func demoScenes(after step: String) -> [DemoScene] {
        scenes.map(\.scene).filter { $0.after == step }.sorted { ($0.order, $0.name) < ($1.order, $1.name) }
    }

    /// 插件包卸载时拿掉它注册的东西
    func removeAll(owner: String) {
        recordingExclusions.removeAll { $0.owner == owner }
        scenes.removeAll { $0.owner == owner }
    }
}

/// 找到、检查并装载插件包。
@MainActor
final class PluginBundles {
    static let shared = PluginBundles()

    /// 「控制台」里按子系统 io.github.whrss9527.pop、类别 plugins 过滤
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Pop", category: "plugins")

    struct Loaded {
        /// 插件包的 ID（Info.plist 里的 PopPluginID）
        let id: String
        let url: URL
        let entry: PopPluginBundle.Type
        let plugins: [any PopPlugin]
        /// 从 POP_PLUGIN_DIR 装载的（测试、截图用），不归「设置 → 插件」管
        let external: Bool
    }

    enum LoadError: Error, Equatable {
        /// 不是插件包（没有 PopPluginID）
        case notAPlugin
        /// 和这个 Pop 不是同一次构建的
        case wrongBuild(String)
        /// 签名不对：没签名、被改过，或者不是签这个 Pop 的那张证书
        case untrusted
        /// 找不到入口类
        case noEntry
        case failed(String)
    }

    private(set) var loaded: [Loaded] = []
    /// 没装载上的插件包：路径 → 原因
    private(set) var failures: [URL: LoadError] = [:]
    private var didLoadInstalled = false

    /// 装载好的插件包提供的功能
    var plugins: [any PopPlugin] {
        loaded.flatMap(\.plugins)
    }

    /// 这个 Pop 是哪一次构建的（Info.plist 里的 PopBuildID）：插件包的 PopBuildID 要和它一样
    nonisolated static var appBuildID: String {
        Bundle.main.object(forInfoDictionaryKey: "PopBuildID") as? String ?? ""
    }

    /// 装好的插件包放在这里（自定义插件的 JSON 在旁边的 Plugins 文件夹里，分开放）
    nonisolated static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Pop", isDirectory: true)
            .appendingPathComponent("PluginBundles", isDirectory: true)
    }

    /// App Store 版：插件包都打在 Pop.app/Contents/PlugIns 里，装上就是从那里装载，不从网上下载（审核指南 2.5.2）
    nonisolated static var bundledDirectory: URL? {
        Distribution.isAppStore ? Bundle.main.builtInPlugInsURL : nil
    }

    /// 测试和截图用：POP_PLUGIN_DIR 指向一个放着插件包的文件夹（比如构建出来的那个），启动时一起装载
    nonisolated static var extraDirectory: URL? {
        guard let path = ProcessInfo.processInfo.environment["POP_PLUGIN_DIR"], !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    /// 启动时装载装好的插件包；只做一次。
    /// 签名先在几个线程上一起查完（每个插件包都要把代码整个算一遍校验和，一个个查，插件包多的时候主线程要等挺久），
    /// 再在主线程上依次装载。装载用了多久写进日志
    func loadInstalled() {
        guard !didLoadInstalled else { return }
        didLoadInstalled = true
        let started = Date()
        var urls: [(url: URL, external: Bool)] = []
        if let extra = Self.extraDirectory {
            urls += Self.bundles(in: extra).map { (url: $0, external: true) }
        }
        urls += Self.bundles(in: Self.directory).map { (url: $0, external: false) }
        checkedSignatures = Self.checkSignatures(urls.map { $0.url })
        for item in urls {
            _ = load(item.url, external: item.external)
        }
        checkedSignatures = [:]
        let milliseconds = Int(Date().timeIntervalSince(started) * 1000)
        Self.log.notice("loaded \(self.loaded.count, privacy: .public) plugins in \(milliseconds, privacy: .public) ms")
    }

    /// 启动时一起查好的签名（插件包的位置 → 能不能装载），只在 loadInstalled 里用
    private var checkedSignatures: [URL: Bool] = [:]

    /// 在几个线程上一起查这些插件包的签名
    nonisolated static func checkSignatures(_ urls: [URL]) -> [URL: Bool] {
        let results = SignatureResults(count: urls.count)
        DispatchQueue.concurrentPerform(iterations: urls.count) { index in
            results.set(index, CodeSignature.isTrustedPlugin(urls[index]))
        }
        return Dictionary(zip(urls, results.values), uniquingKeysWith: { first, _ in first })
    }

    func isLoaded(_ id: String) -> Bool {
        loaded.contains { $0.id == id }
    }

    func loadedBundle(_ id: String) -> Loaded? {
        loaded.first { $0.id == id }
    }

    /// 卸载：拿掉它提供的功能和注册的东西。已经装载的代码要等 Pop 下次启动才真正卸掉
    func unload(_ id: String) {
        guard let item = loadedBundle(id) else { return }
        item.entry.willUninstall()
        PluginHost.shared.removeAll(owner: id)
        loaded.removeAll { $0.id == id }
        Self.log.notice("unloaded plugin \(id, privacy: .public)")
    }

    /// 装在这个文件夹里的插件包（装上、卸载都在这里）
    nonisolated static func installedURL(bundleName: String) -> URL {
        directory.appendingPathComponent("\(bundleName).bundle", isDirectory: true)
    }

    /// 文件夹里的插件包（.bundle，Info.plist 里有 PopPluginID）
    nonisolated static func bundles(in directory: URL) -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return urls
            .filter { $0.pathExtension == "bundle" && pluginID(of: $0) != nil }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// 插件包的 ID；不是插件包时是 nil
    nonisolated static func pluginID(of url: URL) -> String? {
        guard let id = info(of: url)["PopPluginID"] as? String, !id.isEmpty else { return nil }
        return id
    }

    /// 插件包是哪一次构建的
    nonisolated static func buildID(of url: URL) -> String {
        info(of: url)["PopBuildID"] as? String ?? ""
    }

    /// 直接读 Info.plist，不经过 Bundle：Bundle 会按路径一直缓存着，同一个位置换成新的插件包后读到的还是旧的
    private nonisolated static func info(of url: URL) -> [String: Any] {
        NSDictionary(contentsOf: url.appendingPathComponent("Contents/Info.plist")) as? [String: Any] ?? [:]
    }

    /// 检查并装载一个插件包。同一个 ID 已经装载过时直接返回那一个。
    func load(_ url: URL, external: Bool = false) -> Result<Loaded, LoadError> {
        let result = loadChecked(url, external: external)
        switch result {
        case .success(let item):
            failures[url] = nil
            Self.log.notice("loaded plugin \(item.id, privacy: .public) (\(item.plugins.count) functions) from \(url.path, privacy: .public)")
        case .failure(let error):
            failures[url] = error
            Self.log.error("could not load plugin at \(url.path, privacy: .public): \(String(describing: error), privacy: .public)")
        }
        return result
    }

    private func loadChecked(_ url: URL, external: Bool) -> Result<Loaded, LoadError> {
        guard let id = Self.pluginID(of: url) else { return .failure(.notAPlugin) }
        if let existing = loadedBundle(id) {
            return .success(existing)
        }
        let build = Self.buildID(of: url)
        guard build == Self.appBuildID else { return .failure(.wrongBuild(build)) }
        guard checkedSignatures[url] ?? CodeSignature.isTrustedPlugin(url) else { return .failure(.untrusted) }
        guard let bundle = Bundle(url: url) else { return .failure(.notAPlugin) }
        do {
            try bundle.loadAndReturnError()
        } catch {
            return .failure(.failed(error.localizedDescription))
        }
        guard let entry = bundle.principalClass as? PopPluginBundle.Type else { return .failure(.noEntry) }
        let item = Loaded(id: id, url: url, entry: entry, plugins: entry.makePlugins(), external: external)
        entry.didLoad(PluginHost.Registrar(owner: id))
        loaded.append(item)
        return .success(item)
    }
}

/// 几个线程一起查签名时放结果的地方
private final class SignatureResults: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Bool]

    init(count: Int) {
        storage = Array(repeating: false, count: count)
    }

    func set(_ index: Int, _ trusted: Bool) {
        lock.lock()
        storage[index] = trusted
        lock.unlock()
    }

    var values: [Bool] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
