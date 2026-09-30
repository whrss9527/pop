import AppKit

enum BuiltinPlugins {
    /// 顺序就是设置里「内置功能」和「全部功能」列表的顺序。
    static func make() -> [any PopPlugin] {
        let text: [any PopPlugin] = [
            TranslatePlugin(),
            ScreenshotTranslatePlugin(),
            WebSearchPlugin(),
            DictionaryPlugin(),
            VocabularyPlugin(),
            SpeakPlugin(),
            OpenLinkPlugin(),
            LinkInspectPlugin(),
            WebCapturePlugin(),
            CalculatorPlugin(),
            NumberStatsPlugin(),
            UnitConvertPlugin(),
            CopyPlainTextPlugin(),
            TextCleanupPlugin(),
            ExtractInfoPlugin(),
            IDNumberPlugin(),
            LineToolsPlugin(),
            ReminderPlugin(),
            SpellCheckPlugin(),
        ]
        let ai: [any PopPlugin] = AIPlugin.all.map { $0 as any PopPlugin }
        let others: [any PopPlugin] = [
            ChangeCasePlugin(),
            EncodeDecodePlugin(),
            CharInfoPlugin(),
            TextStatsPlugin(),
            TextDiffPlugin(),
            FormatJSONPlugin(),
            YAMLJSONPlugin(),
            FormatXMLPlugin(),
            FormatSQLPlugin(),
            JSONTypesPlugin(),
            TableConvertPlugin(),
            JWTPlugin(),
            RegexTestPlugin(),
            CronPlugin(),
            MarkdownCopyPlugin(),
            MarkdownPreviewPlugin(),
            ToMarkdownPlugin(),
            MarkdownTOCPlugin(),
            CodeImagePlugin(),
            TimestampPlugin(),
            DateSpanPlugin(),
            NumberConvertPlugin(),
            ColorConvertPlugin(),
            ContrastPlugin(),
            HashPlugin(),
            QRCodePlugin(),
            Base64ImagePlugin(),
            OCRPlugin(),
            ScreenshotOCRPlugin(),
            TableOCRPlugin(),
            ScanCodePlugin(),
            AnnotatePlugin(),
            ScreenRecordPlugin(),
            PinPlugin(),
            RemoveBackgroundPlugin(),
            ImageConvertPlugin(),
            StitchImagesPlugin(),
            WatermarkPlugin(),
            IDPhotoPlugin(),
            CropImagePlugin(),
            PalettePlugin(),
            ColorPickerPlugin(),
            RulerPlugin(),
            RandomPlugin(),
            QuickNotePlugin(),
            WindowLayoutPlugin(),
            AirDropPlugin(),
            SendToPhonePlugin(),
            CopyPathPlugin(),
            FileInfoPlugin(),
            FolderTreePlugin(),
            DuplicatesPlugin(),
            DiskUsagePlugin(),
            CodeStatsPlugin(),
            FolderComparePlugin(),
            BatchRenamePlugin(),
            RevealInFinderPlugin(),
            OpenWithPlugin(),
            ZipPlugin(),
            UnzipPlugin(),
            PDFPlugin(),
            VideoConvertPlugin(),
            TrimMediaPlugin(),
            TranscribePlugin(),
            ShelfPlugin(),
            OpenInTerminalPlugin(),
            KeepAwakePlugin(),
            TimerPlugin(),
            ClipboardHistoryPlugin(),
            SnippetsPlugin(),
            AllPluginsPlugin(),
            OpenSettingsPlugin(),
        ]
        return text + ai + others
    }
}

/// 内置功能的分类，设置里按它分组显示。
enum BuiltinCategory: CaseIterable, Identifiable {
    case text
    case ai
    case convert
    case developer
    case screen
    case files
    case other

    var id: Self { self }

    var title: String {
        switch self {
        case .text: return String(localized: "文字")
        case .ai: return "AI"
        case .convert: return String(localized: "转换")
        case .developer: return String(localized: "开发")
        case .screen: return String(localized: "屏幕与图片")
        case .files: return String(localized: "文件和系统")
        case .other: return String(localized: "其他")
        }
    }

    private static let members: [BuiltinCategory: [String]] = [
        .text: [BuiltinPluginID.translate, BuiltinPluginID.screenshotTranslate, BuiltinPluginID.search,
                BuiltinPluginID.dictionary, BuiltinPluginID.vocabulary, BuiltinPluginID.speak, BuiltinPluginID.openURL,
                BuiltinPluginID.webCapture,
                BuiltinPluginID.copyPlain,
                BuiltinPluginID.textCleanup, BuiltinPluginID.extractInfo, BuiltinPluginID.idNumber, BuiltinPluginID.lineTools,
                BuiltinPluginID.reminder,
                BuiltinPluginID.spellCheck,
                BuiltinPluginID.textStats, BuiltinPluginID.textDiff,
                BuiltinPluginID.snippets, BuiltinPluginID.quickNote],
        .ai: [BuiltinPluginID.aiAssistant, BuiltinPluginID.aiPolish, BuiltinPluginID.aiSummarize, BuiltinPluginID.aiExplain],
        .convert: [BuiltinPluginID.calculate, BuiltinPluginID.numberStats, BuiltinPluginID.unitConvert, BuiltinPluginID.changeCase,
                   BuiltinPluginID.encodeDecode, BuiltinPluginID.formatJSON, BuiltinPluginID.yamlJSON, BuiltinPluginID.formatXML,
                   BuiltinPluginID.formatSQL, BuiltinPluginID.tableConvert,
                   BuiltinPluginID.markdownCopy, BuiltinPluginID.markdownPreview, BuiltinPluginID.toMarkdown, BuiltinPluginID.markdownTOC,
                   BuiltinPluginID.timestamp, BuiltinPluginID.dateSpan,
                   BuiltinPluginID.numberConvert, BuiltinPluginID.colorConvert, BuiltinPluginID.contrast],
        .developer: [BuiltinPluginID.hash, BuiltinPluginID.qrCode, BuiltinPluginID.base64Image, BuiltinPluginID.random,
                     BuiltinPluginID.linkInspect,
                     BuiltinPluginID.jwtDecode, BuiltinPluginID.regexTest, BuiltinPluginID.cron, BuiltinPluginID.codeImage,
                     BuiltinPluginID.jsonTypes, BuiltinPluginID.charInfo],
        .screen: [BuiltinPluginID.ocr, BuiltinPluginID.screenshotOCR, BuiltinPluginID.tableOCR, BuiltinPluginID.scanCode,
                  BuiltinPluginID.annotate, BuiltinPluginID.screenRecord,
                  BuiltinPluginID.pin, BuiltinPluginID.removeBackground,
                  BuiltinPluginID.imageConvert, BuiltinPluginID.stitchImages, BuiltinPluginID.watermark, BuiltinPluginID.idPhoto,
                  BuiltinPluginID.cropImage,
                  BuiltinPluginID.palette, BuiltinPluginID.colorPicker,
                  BuiltinPluginID.ruler],
        .files: [BuiltinPluginID.copyPath, BuiltinPluginID.fileInfo, BuiltinPluginID.folderTree, BuiltinPluginID.findDuplicates,
                 BuiltinPluginID.diskUsage, BuiltinPluginID.codeStats, BuiltinPluginID.compareFolders,
                 BuiltinPluginID.batchRename,
                 BuiltinPluginID.revealInFinder,
                 BuiltinPluginID.openWith,
                 BuiltinPluginID.openInTerminal, BuiltinPluginID.zip,
                 BuiltinPluginID.unzip, BuiltinPluginID.pdf, BuiltinPluginID.videoConvert, BuiltinPluginID.trimMedia,
                 BuiltinPluginID.transcribe,
                 BuiltinPluginID.shelf, BuiltinPluginID.airDrop, BuiltinPluginID.sendToPhone,
                 BuiltinPluginID.windowLayout,
                 BuiltinPluginID.keepAwake, BuiltinPluginID.timer],
    ]

    /// 没有列出来的（剪贴板、全部功能、设置）都算「其他」
    static func of(_ pluginID: String) -> BuiltinCategory {
        allCases.first { members[$0]?.contains(pluginID) == true } ?? .other
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
    let info = PluginInfo(id: BuiltinPluginID.translate, name: String(localized: "翻译"), symbol: "character.bubble",
                          summary: String(localized: "翻译选中的文字：默认用系统离线翻译，卡片上可以换成 AI 或 DeepL，或者几家一起对比"), accepts: [.text])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text else { return .failure(String(localized: "没有可翻译的文字")) }
        return .translate(text: text, language: content.language)
    }
}

struct WebSearchPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.search, name: String(localized: "搜索"), symbol: "magnifyingglass",
                          summary: String(localized: "用默认浏览器搜索选中的文字"), accepts: [.text])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text, let url = context.settings.searchEngine.searchURL(for: text) else {
            return .failure(String(localized: "没有可搜索的文字"))
        }
        NSWorkspace.shared.open(url)
        return .done(toast: nil)
    }
}

struct OpenLinkPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.openURL, name: String(localized: "打开链接"), symbol: "safari",
                          summary: String(localized: "在浏览器中打开链接，或给邮箱写邮件"), accepts: [.url, .email])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let url = content.url else { return .failure(String(localized: "没有识别到链接")) }
        NSWorkspace.shared.open(url)
        return .done(toast: nil)
    }
}

struct CalculatorPlugin: PopPlugin {
    /// 说明里列出的运算符（放在翻译的参数里：翻译文字里单独的 % 会被当成格式符）
    static let operators = "+ - × ÷ ^ %"

    let info = PluginInfo(id: BuiltinPluginID.calculate, name: String(localized: "计算"), symbol: "function",
                          summary: String(localized: "计算选中的算式，支持 \(CalculatorPlugin.operators) 和括号"), accepts: [.math])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text, let value = Calculator.evaluate(text) else {
            return .failure(String(localized: "无法计算这个算式"))
        }
        let result = Calculator.format(value)
        return .card(ResultCard(title: String(localized: "计算结果"), body: result, detail: text, monospaced: true,
                                copyText: result, replaceText: result))
    }
}

struct CopyPlainTextPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.copyPlain, name: String(localized: "纯文本复制"), symbol: "doc.on.clipboard",
                          summary: String(localized: "去掉格式，只把文字复制到剪贴板"), accepts: [.text])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text else { return .failure(String(localized: "没有文字")) }
        PasteboardWriter.copy(text)
        return .done(toast: String(localized: "已复制纯文本"))
    }
}

struct FormatJSONPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.formatJSON, name: String(localized: "JSON 格式化"), symbol: "curlybraces",
                          summary: String(localized: "格式化或压缩选中的 JSON"), accepts: [.json])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text, let pretty = JSONFormatter.prettyPrinted(text) else {
            return .failure(String(localized: "不是合法的 JSON"))
        }
        var buttons: [CardButton] = []
        if let minified = JSONFormatter.minified(text) {
            buttons.append(CardButton(title: String(localized: "复制压缩版"), action: .copy(minified)))
        }
        return .card(ResultCard(title: String(localized: "JSON 格式化"), body: pretty, monospaced: true,
                                copyText: pretty, replaceText: pretty, buttons: buttons))
    }
}

struct TimestampPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.timestamp, name: String(localized: "时间转换"), symbol: "clock",
                          summary: String(localized: "Unix 时间戳（秒/毫秒）和日期时间互相转换"), accepts: [.timestamp, .dateTime])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text,
              let date = TimestampConverter.date(from: text) ?? DateParser.parse(text) else {
            return .failure(String(localized: "不是有效的时间"))
        }
        return .card(ResultCard(title: String(localized: "时间转换"), body: TimestampConverter.localString(date), monospaced: true,
                                rows: DateParser.rows(for: date), rowsReplaceable: true))
    }
}

struct CopyPathPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.copyPath, name: String(localized: "复制路径"), symbol: "folder",
                          summary: String(localized: "复制选中文件的完整路径"), accepts: [.files])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard !content.files.isEmpty else { return .failure(String(localized: "没有选中文件")) }
        PasteboardWriter.copy(content.files.map { $0.path(percentEncoded: false) }.joined(separator: "\n"))
        return .done(toast: content.files.count == 1 ? String(localized: "已复制路径") : String(localized: "已复制 \(content.files.count) 个路径"))
    }
}

struct RevealInFinderPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.revealInFinder, name: String(localized: "在访达中显示"), symbol: "macwindow",
                          summary: String(localized: "在访达中定位选中的文件"), accepts: [.files])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard !content.files.isEmpty else { return .failure(String(localized: "没有选中文件")) }
        NSWorkspace.shared.activateFileViewerSelecting(content.files)
        return .done(toast: nil)
    }
}

struct OpenSettingsPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.settings, name: String(localized: "设置"), symbol: "gearshape",
                          summary: String(localized: "打开 Pop 设置"), accepts: [])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        context.openSettings()
        return .done(toast: nil)
    }
}

struct SnippetsPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.snippets, name: String(localized: "常用短语"), symbol: "text.bubble",
                          summary: String(localized: "从存好的短语里选一条粘贴到当前 App，可以用 {date}、{clipboard}、{selection} 这样的占位符"),
                          accepts: [], optionalContent: true)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        .showSnippets
    }
}

struct ClipboardHistoryPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.clipboardHistory, name: String(localized: "剪贴板"), symbol: "list.clipboard",
                          summary: String(localized: "打开剪贴板历史，选一条粘贴"), accepts: [])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        .showClipboardHistory
    }
}

struct AllPluginsPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.allPlugins, name: String(localized: "全部功能"), symbol: "square.grid.2x2",
                          summary: String(localized: "列出所有能处理当前内容的功能，可以搜索"), accepts: [])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        .showAllPlugins
    }
}
