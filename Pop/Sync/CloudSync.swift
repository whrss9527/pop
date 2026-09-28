import Combine
import Foundation
import Security
import SystemConfiguration

/// 上传到 iCloud 的内容：设置本身 + 来自哪台设备（显示用）。
struct SyncEnvelope: Codable, Equatable {
    var version = 1
    var device: String
    var settings: AppSettings
}

/// 决定本地和云端谁的设置更新（最后修改者优先）。
enum SyncResolver {
    enum Action: Equatable {
        /// 云端更新，采用云端
        case applyRemote
        /// 本地更新（或云端没有），上传本地
        case pushLocal
        case none
    }

    static func resolve(local: AppSettings, remote: AppSettings?) -> Action {
        guard let remote else {
            // 云端还没有数据：本地改过才上传，全新安装的默认设置不去覆盖别人。
            return local.modifiedAt > .distantPast ? .pushLocal : .none
        }
        if remote.modifiedAt > local.modifiedAt {
            return remote.hasSameContent(as: local) ? .none : .applyRemote
        }
        if local.modifiedAt > remote.modifiedAt {
            return .pushLocal
        }
        return .none
    }
}

/// 通过 iCloud 键值存储（NSUbiquitousKeyValueStore）在多台 Mac 之间同步设置。
/// 设置很小（几 KB），键值存储最合适：不用建 CloudKit 表结构，系统负责推送和离线合并。
@MainActor
final class CloudSync: ObservableObject {
    @Published private(set) var isEnabled: Bool
    @Published private(set) var statusText = "未开启"
    @Published private(set) var lastSyncDate: Date?
    @Published private(set) var lastRemoteDevice: String? = nil

    /// 当前构建是否带有 iCloud 键值存储能力（没有付费开发者账号签名时没有）。
    let isAvailableInBuild: Bool

    private let settingsStore: SettingsStore
    private var store: NSUbiquitousKeyValueStore?
    private var cancellables = Set<AnyCancellable>()
    private var pushWorkItem: DispatchWorkItem?
    private var externalChangeObserver: NSObjectProtocol?

    private static let settingsKey = "pop.settings.v1"
    private static let enabledKey = "pop.icloudSyncEnabled"
    private static let lastSyncKey = "pop.icloudLastSync"
    static let entitlement = "com.apple.developer.ubiquity-kvstore-identifier"

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
        isAvailableInBuild = Self.hasEntitlement(Self.entitlement)
        isEnabled = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
        lastSyncDate = UserDefaults.standard.object(forKey: Self.lastSyncKey) as? Date

        settingsStore.localChanges
            .sink { [weak self] _ in
                self?.schedulePush()
            }
            .store(in: &cancellables)
    }

    func start() {
        guard isAvailableInBuild else {
            statusText = "当前构建未启用 iCloud"
            return
        }
        guard isEnabled else {
            statusText = "未开启"
            return
        }
        let store = self.store ?? NSUbiquitousKeyValueStore.default
        if self.store == nil {
            self.store = store
            externalChangeObserver = NotificationCenter.default.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                                                   object: store, queue: .main) { [weak self] notification in
                let reason = notification.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int
                MainActor.assumeIsolated {
                    self?.handleExternalChange(reason: reason)
                }
            }
        }
        if FileManager.default.ubiquityIdentityToken == nil {
            statusText = "没有登录 iCloud（登录后会自动同步）"
        } else {
            statusText = "已开启"
        }
        _ = store.synchronize()
        reconcile()
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
        if enabled {
            start()
        } else {
            pushWorkItem?.cancel()
            statusText = "未开启"
        }
    }

    func syncNow() {
        guard isEnabled, isAvailableInBuild else { return }
        _ = store?.synchronize()
        reconcile()
    }

    // MARK: - 内部

    private func handleExternalChange(reason: Int?) {
        guard isEnabled else { return }
        switch reason {
        case NSUbiquitousKeyValueStoreQuotaViolationChange:
            statusText = "iCloud 存储空间超出配额"
        case NSUbiquitousKeyValueStoreAccountChange:
            statusText = FileManager.default.ubiquityIdentityToken == nil ? "iCloud 账号已退出" : "iCloud 账号已切换"
            reconcile()
        default:
            reconcile()
        }
    }

    /// 比较本地和云端，决定采用哪一边。
    private func reconcile() {
        guard let store, isEnabled else { return }
        let remote = store.data(forKey: Self.settingsKey).flatMap { try? JSONDecoder().decode(SyncEnvelope.self, from: $0) }
        if let remote {
            lastRemoteDevice = remote.device
        }
        switch SyncResolver.resolve(local: settingsStore.settings, remote: remote?.settings) {
        case .applyRemote:
            if let remote {
                settingsStore.applyRemote(remote.settings)
                markSynced()
            }
        case .pushLocal:
            push()
        case .none:
            markSynced()
        }
    }

    private func schedulePush() {
        guard isEnabled, isAvailableInBuild else { return }
        pushWorkItem?.cancel()
        // 拖动滑块之类的连续修改合并成一次上传
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.push()
            }
        }
        pushWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: item)
    }

    private func push() {
        guard let store, isEnabled else { return }
        let envelope = SyncEnvelope(device: Self.deviceName, settings: settingsStore.settings)
        guard let data = try? JSONEncoder().encode(envelope) else { return }
        store.set(data, forKey: Self.settingsKey)
        _ = store.synchronize()
        lastRemoteDevice = envelope.device
        markSynced()
    }

    private func markSynced() {
        let now = Date()
        lastSyncDate = now
        UserDefaults.standard.set(now, forKey: Self.lastSyncKey)
    }

    /// 「系统设置 → 通用 → 共享」里的电脑名称（Host.current() 可能会做网络查询，比较慢）。
    private static let deviceName: String = {
        (SCDynamicStoreCopyComputerName(nil, nil) as String?) ?? "Mac"
    }()

    /// 读取自身签名里的 entitlement，判断这次构建是否启用了 iCloud。
    private static func hasEntitlement(_ name: String) -> Bool {
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        return SecTaskCopyValueForEntitlement(task, name as CFString, nil) != nil
    }
}
