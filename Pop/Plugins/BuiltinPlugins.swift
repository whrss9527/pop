import AppKit

enum BuiltinPlugins {
    static func make() -> [any PopPlugin] {
        [
            TranslatePlugin(),
            WebSearchPlugin(),
            OpenLinkPlugin(),
            CalculatorPlugin(),
            CopyPlainTextPlugin(),
            FormatJSONPlugin(),
            TimestampPlugin(),
            CopyPathPlugin(),
            RevealInFinderPlugin(),
            OpenSettingsPlugin(),
        ]
    }
}

struct TranslatePlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.translate, name: "翻译", symbol: "character.bubble",
                          summary: "用系统离线翻译翻译选中的文字", accepts: [.text])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text else { return .failure("没有可翻译的文字") }
        return .translate(text: text, language: content.language)
    }
}

struct WebSearchPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.search, name: "搜索", symbol: "magnifyingglass",
                          summary: "用默认浏览器搜索选中的文字", accepts: [.text])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text, let url = context.settings.searchEngine.searchURL(for: text) else {
            return .failure("没有可搜索的文字")
        }
        NSWorkspace.shared.open(url)
        return .done(toast: nil)
    }
}

struct OpenLinkPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.openURL, name: "打开链接", symbol: "safari",
                          summary: "在浏览器中打开链接，或给邮箱写邮件", accepts: [.url, .email])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let url = content.url else { return .failure("没有识别到链接") }
        NSWorkspace.shared.open(url)
        return .done(toast: nil)
    }
}

struct CalculatorPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.calculate, name: "计算", symbol: "function",
                          summary: "计算选中的算式，支持 + - × ÷ ^ % 和括号", accepts: [.math])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text, let value = Calculator.evaluate(text) else {
            return .failure("无法计算这个算式")
        }
        let result = Calculator.format(value)
        return .card(ResultCard(title: "计算结果", body: result, detail: text, monospaced: true, copyText: result))
    }
}

struct CopyPlainTextPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.copyPlain, name: "纯文本复制", symbol: "doc.on.clipboard",
                          summary: "去掉格式，只把文字复制到剪贴板", accepts: [.text])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text else { return .failure("没有文字") }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        return .done(toast: "已复制纯文本")
    }
}

struct FormatJSONPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.formatJSON, name: "JSON 格式化", symbol: "curlybraces",
                          summary: "格式化选中的 JSON", accepts: [.json])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text, let pretty = JSONFormatter.prettyPrinted(text) else {
            return .failure("不是合法的 JSON")
        }
        return .card(ResultCard(title: "JSON 格式化", body: pretty, monospaced: true, copyText: pretty))
    }
}

struct TimestampPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.timestamp, name: "时间戳", symbol: "clock",
                          summary: "把 Unix 时间戳（秒/毫秒）转换成日期", accepts: [.timestamp])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text, let date = TimestampConverter.date(from: text) else {
            return .failure("不是有效的时间戳")
        }
        let local = TimestampConverter.localString(date)
        return .card(ResultCard(title: "时间戳转换", body: local,
                                detail: "UTC \(TimestampConverter.isoString(date))",
                                monospaced: true, copyText: local))
    }
}

struct CopyPathPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.copyPath, name: "复制路径", symbol: "folder",
                          summary: "复制选中文件的完整路径", accepts: [.files])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard !content.files.isEmpty else { return .failure("没有选中文件") }
        let paths = content.files.map { $0.path(percentEncoded: false) }.joined(separator: "\n")
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(paths, forType: .string)
        return .done(toast: content.files.count == 1 ? "已复制路径" : "已复制 \(content.files.count) 个路径")
    }
}

struct RevealInFinderPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.revealInFinder, name: "在访达中显示", symbol: "macwindow",
                          summary: "在访达中定位选中的文件", accepts: [.files])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard !content.files.isEmpty else { return .failure("没有选中文件") }
        NSWorkspace.shared.activateFileViewerSelecting(content.files)
        return .done(toast: nil)
    }
}

struct OpenSettingsPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.settings, name: "设置", symbol: "gearshape",
                          summary: "打开 Pop 设置", accepts: [])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        context.openSettings()
        return .done(toast: nil)
    }
}
