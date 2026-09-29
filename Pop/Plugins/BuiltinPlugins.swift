import AppKit

enum BuiltinPlugins {
    /// 顺序就是设置里「内置功能」和「全部功能」列表的顺序。
    static func make() -> [any PopPlugin] {
        let text: [any PopPlugin] = [
            TranslatePlugin(),
            ScreenshotTranslatePlugin(),
            WebSearchPlugin(),
            DictionaryPlugin(),
            SpeakPlugin(),
            OpenLinkPlugin(),
            CalculatorPlugin(),
            UnitConvertPlugin(),
            CopyPlainTextPlugin(),
            TextCleanupPlugin(),
        ]
        let ai: [any PopPlugin] = AIPlugin.all.map { $0 as any PopPlugin }
        let others: [any PopPlugin] = [
            ChangeCasePlugin(),
            EncodeDecodePlugin(),
            TextStatsPlugin(),
            FormatJSONPlugin(),
            TimestampPlugin(),
            NumberConvertPlugin(),
            ColorConvertPlugin(),
            HashPlugin(),
            QRCodePlugin(),
            OCRPlugin(),
            ScreenshotOCRPlugin(),
            PinPlugin(),
            RemoveBackgroundPlugin(),
            ImageConvertPlugin(),
            ColorPickerPlugin(),
            RandomPlugin(),
            QuickNotePlugin(),
            WindowLayoutPlugin(),
            AirDropPlugin(),
            CopyPathPlugin(),
            RevealInFinderPlugin(),
            OpenInTerminalPlugin(),
            ClipboardHistoryPlugin(),
            AllPluginsPlugin(),
            OpenSettingsPlugin(),
        ]
        return text + ai + others
    }
}

/// 把耗时的工作（哈希、文字识别）放到后台线程，不卡住界面。
func runInBackground<T>(_ work: @escaping () -> T) async -> T {
    await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
            continuation.resume(returning: work())
        }
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
        return .card(ResultCard(title: "计算结果", body: result, detail: text, monospaced: true,
                                copyText: result, replaceText: result))
    }
}

struct CopyPlainTextPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.copyPlain, name: "纯文本复制", symbol: "doc.on.clipboard",
                          summary: "去掉格式，只把文字复制到剪贴板", accepts: [.text])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text else { return .failure("没有文字") }
        PasteboardWriter.copy(text)
        return .done(toast: "已复制纯文本")
    }
}

struct FormatJSONPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.formatJSON, name: "JSON 格式化", symbol: "curlybraces",
                          summary: "格式化或压缩选中的 JSON", accepts: [.json])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text, let pretty = JSONFormatter.prettyPrinted(text) else {
            return .failure("不是合法的 JSON")
        }
        var buttons: [CardButton] = []
        if let minified = JSONFormatter.minified(text) {
            buttons.append(CardButton(title: "复制压缩版", action: .copy(minified)))
        }
        return .card(ResultCard(title: "JSON 格式化", body: pretty, monospaced: true,
                                copyText: pretty, replaceText: pretty, buttons: buttons))
    }
}

struct TimestampPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.timestamp, name: "时间转换", symbol: "clock",
                          summary: "Unix 时间戳（秒/毫秒）和日期时间互相转换", accepts: [.timestamp, .dateTime])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text,
              let date = TimestampConverter.date(from: text) ?? DateParser.parse(text) else {
            return .failure("不是有效的时间")
        }
        return .card(ResultCard(title: "时间转换", body: TimestampConverter.localString(date), monospaced: true,
                                rows: DateParser.rows(for: date), rowsReplaceable: true))
    }
}

struct CopyPathPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.copyPath, name: "复制路径", symbol: "folder",
                          summary: "复制选中文件的完整路径", accepts: [.files])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard !content.files.isEmpty else { return .failure("没有选中文件") }
        PasteboardWriter.copy(content.files.map { $0.path(percentEncoded: false) }.joined(separator: "\n"))
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

struct ClipboardHistoryPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.clipboardHistory, name: "剪贴板", symbol: "list.clipboard",
                          summary: "打开剪贴板历史，选一条粘贴", accepts: [])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        .showClipboardHistory
    }
}

struct AllPluginsPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.allPlugins, name: "全部功能", symbol: "square.grid.2x2",
                          summary: "列出所有能处理当前内容的功能，可以搜索", accepts: [])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        .showAllPlugins
    }
}
