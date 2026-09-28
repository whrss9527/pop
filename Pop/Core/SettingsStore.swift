import Combine
import Foundation

/// 设置的唯一来源：本地持久化到 UserDefaults，并把用户的修改通知给 iCloud 同步。
@MainActor
final class SettingsStore: ObservableObject {
    @Published private(set) var settings: AppSettings

    /// 用户在本机做的修改（不包括从 iCloud 拉下来的变更），CloudSync 订阅它来上传。
    let localChanges = PassthroughSubject<AppSettings, Never>()

    private let defaults: UserDefaults
    private let storageKey: String

    init(defaults: UserDefaults = .standard, storageKey: String = "pop.settings.v1") {
        self.defaults = defaults
        self.storageKey = storageKey
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = decoded
        } else {
            settings = AppSettings()
        }
    }

    /// 修改设置。内容没变时什么都不做；变了会刷新 modifiedAt、保存并触发同步。
    func update(_ mutate: (inout AppSettings) -> Void) {
        var copy = settings
        mutate(&copy)
        guard !copy.hasSameContent(as: settings) else { return }
        copy.modifiedAt = Date()
        settings = copy
        persist()
        localChanges.send(copy)
    }

    /// 应用来自 iCloud 的设置：保留对方的 modifiedAt，也不会再回传。
    func applyRemote(_ remote: AppSettings) {
        guard remote != settings else { return }
        settings = remote
        persist()
    }

    func resetToDefaults() {
        update { $0 = AppSettings() }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
