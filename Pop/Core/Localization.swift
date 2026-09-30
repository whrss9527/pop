import Foundation

/// 界面文字的本地化。
///
/// 界面文字直接用中文原文作 key（开发语言是简体中文），英文翻译在 Resources/en.lproj/Localizable.strings。
/// 写在代码里的文字用 `String(localized: "中文")`；SwiftUI 的 `Text("中文")`、`Button("中文")` 这类会自动查翻译。
/// 运行时才知道的文字用 `Localization.string(_:)` 查。加了新文字后跑一遍 scripts/check-localization.py。
enum Localization {
    /// 界面现在用的是不是中文
    static var isChinese: Bool {
        Bundle.main.preferredLocalizations.first?.hasPrefix("zh") ?? true
    }

    /// 列举几项时的分隔符：中文是「、」，英文是「, 」
    static var listSeparator: String {
        String(localized: "、", comment: "列举几项时的分隔符")
    }

    /// 按 key 查翻译，查不到就原样返回
    static func string(_ key: String) -> String {
        Bundle.main.localizedString(forKey: key, value: key, table: nil)
    }
}

extension Sequence where Element == String {
    /// 用当前语言的分隔符连起来（中文「甲、乙」，英文「A, B」）
    func joinedAsList() -> String {
        joined(separator: Localization.listSeparator)
    }
}
