import AppKit
import Combine
import Sparkle

/// 基于 Sparkle 的检查更新 / 一键更新。
///
/// - 更新源（appcast）放在 GitHub Releases，地址见 Info.plist 的 SUFeedURL；
/// - 安装包用 EdDSA 签名，公钥来自构建设置 SPARKLE_PUBLIC_ED_KEY。没有配置公钥的开发构建不启动更新器，
///   避免 Sparkle 弹出「配置错误」提示；
/// - Pop 是菜单栏 App，后台发现新版本时用「温和提醒」：菜单栏图标变成下载箭头，而不是直接弹窗打断用户。
@MainActor
final class UpdateManager: NSObject, ObservableObject, SPUStandardUserDriverDelegate {
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var pendingUpdateVersion: String? = nil

    let isConfigured: Bool
    private var controller: SPUStandardUpdaterController?

    override init() {
        let publicKey = (Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String ?? ""
        isConfigured = !publicKey.isEmpty && !publicKey.hasPrefix("$(") && !feed.isEmpty
        super.init()
    }

    func start() {
        guard isConfigured, controller == nil else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
        self.controller = controller
        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .assign(to: &$canCheckForUpdates)
    }

    var currentVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    var automaticallyChecksForUpdates: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set {
            objectWillChange.send()
            controller?.updater.automaticallyChecksForUpdates = newValue
        }
    }

    var automaticallyDownloadsUpdates: Bool {
        get { controller?.updater.automaticallyDownloadsUpdates ?? false }
        set {
            objectWillChange.send()
            controller?.updater.automaticallyDownloadsUpdates = newValue
        }
    }

    var lastUpdateCheckDate: Date? {
        controller?.updater.lastUpdateCheckDate
    }

    /// 用户主动检查：Sparkle 会显示进度和结果，有新版本时「安装更新」一键完成下载、替换、重启。
    func checkForUpdates() {
        guard let controller else {
            showNotConfiguredAlert()
            return
        }
        NSApp.activate()
        controller.checkForUpdates(nil)
    }

    private func showNotConfiguredAlert() {
        let alert = NSAlert()
        alert.messageText = "这是开发构建"
        alert.informativeText = "没有配置更新签名公钥（SPARKLE_PUBLIC_ED_KEY），自动更新已关闭。正式发布的版本会从 GitHub Releases 检查更新。"
        alert.addButton(withTitle: "好")
        NSApp.activate()
        alert.runModal()
    }

    // MARK: - SPUStandardUserDriverDelegate（温和提醒）

    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        // 刚启动等 Sparkle 认为适合立即显示的时机交给它；其余时候只在菜单栏提示。
        immediateFocus
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        guard !state.userInitiated else { return }
        let version = update.displayVersionString
        MainActor.assumeIsolated {
            self.pendingUpdateVersion = version
        }
    }

    nonisolated func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        MainActor.assumeIsolated {
            self.pendingUpdateVersion = nil
        }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        MainActor.assumeIsolated {
            self.pendingUpdateVersion = nil
        }
    }
}
