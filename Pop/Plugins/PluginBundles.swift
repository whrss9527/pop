import AppKit
import os

/// 插件包的入口。
///
/// 插件包是 Plugins/ 下面单独编译的 .bundle，装在「~/Library/Application Support/Pop/Plugins」里，由 Pop 在启动时
/// （或者刚装上时）装载。插件包的 Info.plist 里 NSPrincipalClass 指向一个实现了这个协议的类；PopPluginID 是插件包的 ID；
/// PopBuildID 必须和 Pop 自己的一样：插件包直接用 Pop 里的类型，只能和同一次构建出来的 Pop 一起用。
protocol PopPluginBundle: AnyObject {
    /// 插件包提供的功能
    static func makePlugins() -> [any PopPlugin]
    /// 装载以后调用一次：在这里注册录屏时不录的窗口、演示模式的步骤这些
    @MainActor static func didLoad(_ host: PluginHost.Registrar)
}

extension PopPluginBundle {
    @MainActor static func didLoad(_ host: PluginHost.Registrar) {}
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
        /// 显示出来，返回要截的区域（AppKit 屏幕坐标）
        let show: @MainActor (NSScreen) -> CGRect?
        let hide: @MainActor () -> Void
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
            PluginHost.shared.demoScenes.append((owner, scene))
        }
    }

    private var recordingExclusions: [(owner: String, windows: @MainActor () -> [Int])] = []
    private var demoScenes: [(owner: String, scene: DemoScene)] = []

    /// 录屏时不录进去的窗口编号
    var windowsExcludedFromRecording: [Int] {
        recordingExclusions.flatMap { $0.windows() }
    }

    /// 排在演示的这一步后面的插件包步骤
    func demoScenes(after step: String) -> [DemoScene] {
        demoScenes.map(\.scene).filter { $0.after == step }
    }

    /// 插件包卸载时拿掉它注册的东西
    func removeAll(owner: String) {
        recordingExclusions.removeAll { $0.owner == owner }
        demoScenes.removeAll { $0.owner == owner }
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
        let plugins: [any PopPlugin]
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
    nonisolated static var buildID: String {
        Bundle.main.object(forInfoDictionaryKey: "PopBuildID") as? String ?? ""
    }

    /// 装好的插件包放在这里
    nonisolated static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Pop", isDirectory: true)
            .appendingPathComponent("Plugins", isDirectory: true)
    }

    /// 测试和截图用：POP_PLUGIN_DIR 指向一个放着插件包的文件夹（比如构建出来的那个），启动时一起装载
    nonisolated static var extraDirectory: URL? {
        guard let path = ProcessInfo.processInfo.environment["POP_PLUGIN_DIR"], !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    /// 启动时装载装好的插件包；只做一次
    func loadInstalled() {
        guard !didLoadInstalled else { return }
        didLoadInstalled = true
        for directory in [Self.extraDirectory, Self.directory].compactMap({ $0 }) {
            for url in Self.bundles(in: directory) {
                _ = load(url)
            }
        }
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
        let info = NSDictionary(contentsOf: url.appendingPathComponent("Contents/Info.plist")) as? [String: Any]
        guard let id = info?["PopPluginID"] as? String, !id.isEmpty else { return nil }
        return id
    }

    /// 检查并装载一个插件包。同一个 ID 已经装载过时直接返回那一个。
    func load(_ url: URL) -> Result<Loaded, LoadError> {
        let result = loadChecked(url)
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

    private func loadChecked(_ url: URL) -> Result<Loaded, LoadError> {
        guard let id = Self.pluginID(of: url), let bundle = Bundle(url: url) else { return .failure(.notAPlugin) }
        if let existing = loaded.first(where: { $0.id == id }) {
            return .success(existing)
        }
        let build = bundle.object(forInfoDictionaryKey: "PopBuildID") as? String ?? ""
        guard build == Self.buildID else { return .failure(.wrongBuild(build)) }
        guard CodeSignature.isTrustedPlugin(url) else { return .failure(.untrusted) }
        do {
            try bundle.loadAndReturnError()
        } catch {
            return .failure(.failed(error.localizedDescription))
        }
        guard let entry = bundle.principalClass as? PopPluginBundle.Type else { return .failure(.noEntry) }
        let item = Loaded(id: id, url: url, plugins: entry.makePlugins())
        entry.didLoad(PluginHost.Registrar(owner: id))
        loaded.append(item)
        return .success(item)
    }
}
