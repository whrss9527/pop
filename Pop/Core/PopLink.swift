import Foundation

/// pop:// 链接：快捷指令、启动器和脚本用它调用 Pop。
///
/// - `pop://run?plugin=translate&text=Hello`：用这个功能处理这段文字（也可以写成 `pop://run/translate?text=Hello`）；
///   `file=/路径` 处理文件（可以写几个）；文字和文件都不带时处理当前选中的内容
/// - `pop://translate?text=Hello`：翻译
/// - `pop://ring`：在指针的位置打开圆盘
/// - `pop://clipboard`：打开剪贴板历史
/// - `pop://settings`、`pop://settings/translation`：打开设置（某一页）
/// - `pop://plugin-library`：打开插件库
enum PopLink: Equatable {
    case run(pluginID: String, text: String?, files: [URL])
    case ring
    case clipboard
    case settings(SettingsTab?)
    case pluginLibrary

    static let scheme = "pop"

    init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        // pop://run/translate：run 是主机名，translate 在路径里；pop:run/translate 没有主机名，全在路径里
        var segments: [String] = []
        if let host = components.host, !host.isEmpty {
            segments.append(host)
        }
        segments += components.path.split(separator: "/").map(String.init)
        guard let action = segments.first?.lowercased() else { return nil }
        let items = components.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first { $0.name.lowercased() == name }?.value
        }
        switch action {
        case "run":
            guard let pluginID = value("plugin") ?? segments.dropFirst().first, !pluginID.isEmpty else { return nil }
            let files = items.filter { $0.name.lowercased() == "file" }
                .compactMap(\.value)
                .filter { !$0.isEmpty }
                .map { URL(fileURLWithPath: NSString(string: $0).expandingTildeInPath) }
            self = .run(pluginID: pluginID, text: value("text"), files: files)
        case "translate":
            self = .run(pluginID: BuiltinPluginID.translate, text: value("text"), files: [])
        case "ring":
            self = .ring
        case "clipboard":
            self = .clipboard
        case "settings":
            guard let name = segments.dropFirst().first else {
                self = .settings(nil)
                return
            }
            guard let tab = SettingsTab.allCases.first(where: { $0.rawValue.lowercased() == name.lowercased() }) else { return nil }
            self = .settings(tab)
        case "plugin-library":
            self = .pluginLibrary
        default:
            return nil
        }
    }

    /// 执行某个功能的链接（设置里「拷贝链接」用）。文字里的 &、=、+、# 这些也会编码
    static func runURL(_ pluginID: String, text: String? = nil) -> URL {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+#?/")
        func encode(_ value: String) -> String {
            value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
        }
        var query = "plugin=\(encode(pluginID))"
        if let text {
            query += "&text=\(encode(text))"
        }
        return URL(string: "\(scheme)://run?\(query)")!
    }
}
