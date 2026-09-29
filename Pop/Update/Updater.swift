import AppKit
import Combine
import os

/// 一键更新：定期检查 GitHub Releases，有新版本时提醒；用户点「更新」后下载、校验、替换 Pop.app 并重新启动。
/// 状态只在主线程上改，设置页和菜单栏直接观察它。
@MainActor
final class Updater: ObservableObject {
    enum Phase: Equatable {
        case idle
        case checking
        case upToDate
        /// 有新版本，但用户选择过跳过它
        case skipped(ReleaseInfo)
        case available(ReleaseInfo)
        case downloading(ReleaseInfo, Double?)
        case verifying(ReleaseInfo)
        case installing(ReleaseInfo)
        case relaunching(ReleaseInfo)
        case failed(ReleaseInfo, String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var lastChecked: Date? = nil
    /// 最近一次手动检查失败的原因
    @Published private(set) var checkError: String? = nil
    /// 自动检查更新（启动后和每 6 小时一次）
    @Published var automaticChecks: Bool {
        didSet { defaults.set(automaticChecks, forKey: Self.automaticChecksKey) }
    }
    /// 也接收测试版（预发布版本）
    @Published var includePrereleases: Bool {
        didSet { defaults.set(includePrereleases, forKey: Self.includePrereleasesKey) }
    }

    /// 自动检查发现新版本时调用（每个版本只提醒一次）
    var notify: ((ReleaseInfo) -> Void)?
    /// 新程序已经换好、该退出了
    var onRelaunch: (() -> Void)?

    static let checkInterval: TimeInterval = 6 * 3600
    /// 测试用：发现新版本后直接安装（CI 的端到端更新测试用它）
    static let autoInstallVariable = "POP_UPDATE_AUTO_INSTALL"

    private static let automaticChecksKey = "pop.update.automaticChecks"
    private static let includePrereleasesKey = "pop.update.includePrereleases"
    private static let skippedKey = "pop.update.skippedVersion"
    private static let notifiedKey = "pop.update.notifiedVersion"
    private static let lastCheckedKey = "pop.update.lastChecked"

    private let defaults: UserDefaults
    private var timer: Timer?
    private var installTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        automaticChecks = defaults.object(forKey: Self.automaticChecksKey) as? Bool ?? true
        // 现在发布的都是测试版，默认要能收到
        includePrereleases = defaults.object(forKey: Self.includePrereleasesKey) as? Bool ?? true
        lastChecked = defaults.object(forKey: Self.lastCheckedKey) as? Date
    }

    // MARK: - 状态

    /// 发现的新版本（含正在安装和安装失败的），跳过的不算
    var release: ReleaseInfo? {
        switch phase {
        case .available(let release), .downloading(let release, _), .verifying(let release),
             .installing(let release), .relaunching(let release), .failed(let release, _):
            return release
        case .idle, .checking, .upToDate, .skipped:
            return nil
        }
    }

    var isInstalling: Bool {
        switch phase {
        case .downloading, .verifying, .installing, .relaunching: return true
        default: return false
        }
    }

    var currentVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    /// 从下载文件夹这类临时位置运行时，更新会装进「应用程序」
    var relocationNote: String? {
        guard let plan = InstallLocation.current(), plan.relocating else { return nil }
        let folder = InstallLocation.displayName(of: plan.target.deletingLastPathComponent())
        return "现在是从临时位置运行的，这次会装进\(folder)" + (plan.trashAfter == nil ? "" : "，旧的那份移到废纸篓")
    }

    private var skippedVersion: String? {
        get { defaults.string(forKey: Self.skippedKey) }
        set { defaults.set(newValue, forKey: Self.skippedKey) }
    }

    // MARK: - 检查

    /// 启动后检查一次，之后每 6 小时一次（关掉自动检查时跳过）。
    func startAutomaticChecks() {
        timer?.invalidate()
        let timer = Timer(timeInterval: Self.checkInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.checkAutomatically()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        // 测试时不用等太久
        let delay: TimeInterval = UpdateChecker.overrideURL == nil ? 5 : 1
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            MainActor.assumeIsolated {
                self?.checkAutomatically()
            }
        }
    }

    private func checkAutomatically() {
        guard automaticChecks || UpdateChecker.overrideURL != nil else { return }
        Task {
            let found = await check(manual: false)
            if found != nil, ProcessInfo.processInfo.environment[Self.autoInstallVariable] == "1" {
                install()
            }
        }
    }

    /// 用户点「检查更新」
    func checkNow() {
        if case .skipped = phase {
            showSkippedVersion()
            return
        }
        Task {
            await check(manual: true)
        }
    }

    /// 检查一次。manual：用户点的，失败要显示，跳过的版本也显示。返回可以安装的新版本。
    @discardableResult
    func check(manual: Bool) async -> ReleaseInfo? {
        if isInstalling { return release }
        if case .checking = phase { return nil }
        let previous = phase
        phase = .checking
        checkError = nil
        do {
            let latest = try await UpdateChecker.latest(includePrereleases: includePrereleases)
            let now = Date()
            lastChecked = now
            defaults.set(now, forKey: Self.lastCheckedKey)
            let current = UpdateChecker.currentVersion
            guard let latest, UpdateChecker.isNewer(latest.version, than: current) else {
                UpdateLog.info("当前 \(current) 已是最新")
                phase = .upToDate
                return nil
            }
            if !manual, latest.version == skippedVersion {
                UpdateLog.info("有新版本 \(latest.version)，之前选择过跳过")
                phase = .skipped(latest)
                return nil
            }
            UpdateLog.info("有新版本 \(latest.version)（当前 \(current)）")
            phase = .available(latest)
            if !manual, defaults.string(forKey: Self.notifiedKey) != latest.version {
                defaults.set(latest.version, forKey: Self.notifiedKey)
                notify?(latest)
            }
            return latest
        } catch {
            UpdateLog.info("检查失败：\(error.localizedDescription)")
            phase = previous == .checking ? .idle : previous
            if manual {
                checkError = "检查更新失败：\(error.localizedDescription)"
            }
            return nil
        }
    }

    func skipAvailableVersion() {
        guard case .available(let release) = phase else { return }
        skippedVersion = release.version
        phase = .skipped(release)
    }

    /// 跳过的版本重新拿出来看
    func showSkippedVersion() {
        guard case .skipped(let release) = phase else { return }
        skippedVersion = nil
        phase = .available(release)
    }

    // MARK: - 安装

    /// 下载并安装当前发现的新版本，完成后重新启动。
    func install() {
        guard let release, !isInstalling, installTask == nil else { return }
        guard release.canInstall else {
            phase = .failed(release, UpdateError.noArchive.localizedDescription)
            return
        }
        installTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.perform(release)
            } catch let error where Self.isCancellation(error) {
                UpdateLog.info("已取消")
                self.phase = .available(release)
            } catch {
                UpdateLog.info("更新到 \(release.version) 失败：\(error.localizedDescription)")
                self.phase = .failed(release, error.localizedDescription)
            }
            self.installTask = nil
        }
    }

    func cancel() {
        installTask?.cancel()
    }

    private static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }

    /// 检查并直接安装（菜单栏里的「安装新版本」、通知上的「立即更新」）
    func checkAndInstall() {
        Task {
            if case .skipped = phase {
                showSkippedVersion()
            }
            if release == nil {
                await check(manual: true)
            }
            install()
        }
    }

    private func perform(_ release: ReleaseInfo) async throws {
        guard let plan = InstallLocation.current() else {
            throw UpdateError.notInstallable("不是从 Pop.app 运行的，没法在程序里更新")
        }
        guard let archiveURL = release.archiveURL, let checksumsURL = release.checksumsURL else {
            throw UpdateError.noArchive
        }
        let fileManager = FileManager.default
        let workDirectory = fileManager.temporaryDirectory.appendingPathComponent("Pop-update-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: workDirectory) }

        let archive = workDirectory.appendingPathComponent(release.archiveName ?? "Pop-\(release.version).zip")
        phase = .downloading(release, nil)
        UpdateLog.info("下载 \(archiveURL.absoluteString)")
        try await UpdateInstaller.download(archiveURL, expectedSize: release.archiveSize, to: archive) { fraction in
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, case .downloading = self.phase else { return }
                    self.phase = .downloading(release, fraction)
                }
            }
        }
        try Task.checkCancellation()

        phase = .verifying(release)
        try await UpdateInstaller.verify(archive: archive, checksumsURL: checksumsURL)
        UpdateLog.info("校验和一致")
        let app = try await UpdateInstaller.extract(archive: archive, to: workDirectory.appendingPathComponent("extracted", isDirectory: true))
        try await UpdateInstaller.validate(app: app, expectedVersion: release.version)
        UpdateLog.info("签名检查通过")
        try Task.checkCancellation()

        phase = .installing(release)
        try await UpdateInstaller.install(newApp: app, replacing: plan.target)
        if let old = plan.trashAfter {
            do {
                try fileManager.trashItem(at: old, resultingItemURL: nil)
                UpdateLog.info("已把旧版本 \(old.path) 移到废纸篓")
            } catch {
                UpdateLog.info("旧版本 \(old.path) 没能移到废纸篓：\(error.localizedDescription)")
            }
        }
        UpdateLog.info("已安装 \(release.version)（\(plan.target.path)），重新启动")
        phase = .relaunching(release)
        UpdateInstaller.relaunch(plan.target)
        try? await Task.sleep(for: .milliseconds(600))
        onRelaunch?()
    }
}

/// 更新过程写进系统日志（「控制台」里搜「Pop 更新」），CI 的端到端测试也靠它判断进度。
/// 用 Logger 并把内容标成公开：在 macOS 26 上 NSLog 的内容在系统日志里只显示成 <private>。
enum UpdateLog {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Pop", category: "update")

    static func info(_ message: String) {
        logger.notice("Pop 更新：\(message, privacy: .public)")
    }

    /// 每次启动记一行版本号，CI 的端到端测试靠它确认新版本已经跑起来了
    static func launched(version: String) {
        logger.notice("Pop 已启动，版本 \(version, privacy: .public)")
    }
}
