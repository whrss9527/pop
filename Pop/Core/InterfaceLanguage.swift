import Foundation

/// 设置里选的界面语言。
///
/// 用的是 macOS 的标准做法：在 Pop 自己的偏好设置里写 `AppleLanguages`，下次启动时系统按它挑界面语言；
/// 「跟随系统」就把这一项删掉。只存在本机，不跟着设置导出和 iCloud 同步。
enum InterfaceLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    static let defaultsKey = "AppleLanguages"

    var id: String { rawValue }

    /// 选项的名字：语言本身的名字不翻译，谁都认得出
    var title: String {
        switch self {
        case .system: return String(localized: "跟随系统")
        case .english: return "English"
        case .simplifiedChinese: return "简体中文"
        }
    }

    /// 用户在 Pop 里选过的语言。只看 Pop 自己那一份偏好设置（`domain`），
    /// 不看全局的 AppleLanguages 和启动参数，那些是系统的语言，算「跟随系统」
    static func stored(in defaults: UserDefaults = .standard,
                       domain: String? = Bundle.main.bundleIdentifier) -> InterfaceLanguage {
        guard let domain,
              let languages = defaults.persistentDomain(forName: domain)?[defaultsKey] as? [String],
              let first = languages.first else { return .system }
        if first.hasPrefix("zh") { return .simplifiedChinese }
        if first.hasPrefix("en") { return .english }
        return .system
    }

    /// 记下选的语言，重新启动 Pop 后生效
    static func store(_ language: InterfaceLanguage, in defaults: UserDefaults = .standard) {
        switch language {
        case .system:
            defaults.removeObject(forKey: defaultsKey)
        case .english, .simplifiedChinese:
            defaults.set([language.rawValue], forKey: defaultsKey)
        }
    }

    /// 这次启动时用的设置：选的和它不一样，就要重新启动才生效
    static let atLaunch = stored()
}
