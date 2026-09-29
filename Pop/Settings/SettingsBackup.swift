import Foundation

/// 把设置（圆盘、规则、快捷键、常用短语……）和自己写的插件导出成一个 JSON 文件，
/// 换一台 Mac、或者用的是没有 iCloud 同步的版本时再导入。AI 的 API Key 存在钥匙串里，不会导出。
struct SettingsBackup: Codable {
    static let formatName = "pop-settings"

    var format = SettingsBackup.formatName
    var version = 1
    var exportedAt: Date
    /// 导出时 Pop 的版本
    var appVersion: String?
    var settings: AppSettings
    var plugins: [PluginManifest]

    struct Failure: Error, Equatable {
        let message: String
    }

    init(settings: AppSettings, plugins: [PluginManifest], appVersion: String? = nil, exportedAt: Date = Date()) {
        self.settings = settings
        self.plugins = plugins
        self.appVersion = appVersion
        self.exportedAt = exportedAt
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    static func decode(_ data: Data) throws -> SettingsBackup {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup: SettingsBackup
        do {
            backup = try decoder.decode(SettingsBackup.self, from: data)
        } catch {
            throw Failure(message: "读不了这个文件：不是 Pop 导出的设置，或者文件已经损坏")
        }
        guard backup.format == formatName else {
            throw Failure(message: "这不是 Pop 导出的设置文件")
        }
        return backup
    }

    /// 导出文件的默认名字：「Pop 设置 2026-09-29.json」
    static func suggestedFileName(date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return "Pop 设置 \(formatter.string(from: date)).json"
    }

    /// 导入前给用户看的说明
    var summary: String {
        var parts = ["圆盘、直达规则、唤起方式和快捷键、翻译、剪贴板、AI 接口设置"]
        if !settings.snippets.isEmpty { parts.append("\(settings.snippets.count) 条常用短语") }
        if !plugins.isEmpty { parts.append("\(plugins.count) 个自己写的插件") }
        return parts.joined(separator: "、")
    }
}
