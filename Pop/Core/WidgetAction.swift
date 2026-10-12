import Foundation

/// 小组件只提供明确的交互工具，不接受任意插件或隐含的选区内容。
enum WidgetAction: String, CaseIterable, Equatable {
    case clipboard
    case screenshotOCR
    case screenshotTranslate
    case pluginLibrary

    var url: URL {
        var components = URLComponents()
        components.scheme = "pop"
        components.host = "widget"
        components.queryItems = [URLQueryItem(name: "tool", value: rawValue)]
        return components.url!
    }

    var title: String {
        switch self {
        case .clipboard: return String(localized: "剪贴板历史")
        case .screenshotOCR: return String(localized: "截图识字")
        case .screenshotTranslate: return String(localized: "截图翻译")
        case .pluginLibrary: return String(localized: "插件库")
        }
    }

    var symbol: String {
        switch self {
        case .clipboard: return "clipboard"
        case .screenshotOCR: return "viewfinder"
        case .screenshotTranslate: return "character.bubble"
        case .pluginLibrary: return "square.grid.2x2"
        }
    }
}
