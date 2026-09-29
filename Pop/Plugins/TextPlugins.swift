import AppKit
import AVFoundation
import CoreServices

struct DictionaryPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.dictionary, name: "词典", symbol: "character.book.closed",
                          summary: "用系统「词典」查询选中的单词或词语", accepts: [.text], maxLength: 60)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text else { return .failure("没有可查询的词") }
        var buttons: [CardButton] = []
        if let encoded = text.addingPercentEncoding(withAllowedCharacters: .popURLValueAllowed),
           let url = URL(string: "dict://\(encoded)") {
            buttons.append(CardButton(title: "在词典中打开", action: .open(url)))
        }
        let range = CFRange(location: 0, length: (text as NSString).length)
        guard let definition = DCSCopyTextDefinition(nil, text as CFString, range)?.takeRetainedValue() as String? else {
            return .card(ResultCard(title: "词典", body: "系统词典里没有找到「\(text)」。可以在「词典」App 的设置里启用更多词典。",
                                    buttons: buttons))
        }
        if VocabularyStore.isWordLike(text) {
            buttons.append(CardButton(title: "加入生词本", action: .addToVocabulary(word: text, translation: Self.brief(definition, word: text),
                                                                                source: content.language, target: nil)))
        }
        return .card(ResultCard(title: text, body: Self.format(definition), copyText: definition, buttons: buttons))
    }

    /// 存进生词本的简短释义：去掉开头重复的词，最多 120 个字
    static func brief(_ definition: String, word: String) -> String {
        var text = definition.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        if text.lowercased().hasPrefix(word.lowercased()) {
            text = String(text.dropFirst(word.count))
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "|")))
        return text.count > 120 ? String(text.prefix(120)) + "…" : text
    }

    /// 系统返回的释义挤在一行里，在义项编号和分隔符前断行，读起来轻松一些。
    static func format(_ definition: String) -> String {
        var result = definition
        for marker in [" ▶", " ▸", " • ", " | "] {
            result = result.replacingOccurrences(of: marker, with: "\n" + marker.trimmingCharacters(in: .whitespaces) + " ")
        }
        return result
    }
}

/// 朗读用的语音合成器（要一直持有它，否则一开始读就被释放了）。
@MainActor
final class Speaker {
    static let shared = Speaker()

    private let synthesizer = AVSpeechSynthesizer()

    var isSpeaking: Bool { synthesizer.isSpeaking }

    func speak(_ text: String, language: String?) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.voice(for: language)
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    private static func voice(for language: String?) -> AVSpeechSynthesisVoice? {
        guard let language else { return nil }
        let code: String
        if language.hasPrefix("zh-Hant") {
            code = "zh-TW"
        } else if language.hasPrefix("zh") {
            code = "zh-CN"
        } else {
            code = language
        }
        let voices = AVSpeechSynthesisVoice.speechVoices()
        return voices.first { $0.language == code } ?? voices.first { $0.language.hasPrefix(code) }
    }
}

struct SpeakPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.speak, name: "朗读", symbol: "speaker.wave.2",
                          summary: "用系统语音朗读选中的文字，朗读中再用一次就停止", accepts: [.text])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        if Speaker.shared.isSpeaking {
            Speaker.shared.stop()
            return .done(toast: "已停止朗读")
        }
        guard let text = content.text else { return .failure("没有可朗读的文字") }
        let language = content.language ?? ContentClassifier.dominantLanguage(text)
        Speaker.shared.speak(text, language: language)
        return .done(toast: "正在朗读…")
    }
}

struct ChangeCasePlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.changeCase, name: "大小写", symbol: "textformat",
                          summary: "大写、小写、驼峰、下划线等写法互相转换", accepts: [.text],
                          pattern: "[A-Za-z]", maxLength: 20_000)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text else { return .failure("没有文字") }
        let rows = CaseConverter.conversions(text)
        guard !rows.isEmpty else { return .failure("没有可以转换的字母") }
        return .card(ResultCard(title: "大小写转换", rows: rows, rowsReplaceable: true))
    }
}

struct EncodeDecodePlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.encodeDecode, name: "编码转换", symbol: "chevron.left.forwardslash.chevron.right",
                          summary: "Base64、URL、Unicode、HTML 实体的编码和解码", accepts: [.text], maxLength: 200_000)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text else { return .failure("没有文字") }
        let rows = await runInBackground { TextCodec.conversions(text) }
        return .card(ResultCard(title: "编码转换", rows: rows, rowsReplaceable: true))
    }
}

struct TextStatsPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.textStats, name: "字数统计", symbol: "number",
                          summary: "统计字符、汉字、单词、行数和阅读时间", accepts: [.text])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text else { return .failure("没有文字") }
        let statistics = await runInBackground { TextStatistics(text) }
        return .card(ResultCard(title: "字数统计", rows: statistics.rows))
    }
}

struct NumberStatsPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.numberStats, name: "数字统计", symbol: "sum",
                          summary: "选中一列或一串数字，算出合计、平均、中位数、最大、最小", accepts: [.text],
                          maxLength: 100_000, check: .numberList)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text, let summary = await runInBackground({ NumberStats.parse(text) }) else {
            return .failure("需要至少两个数：一列（每行一个，前面可以有文字），或者一行用逗号、空格隔开")
        }
        return .card(ResultCard(title: "数字统计", detail: "共 \(summary.count) 个数", rows: summary.rows))
    }
}

struct SpellCheckPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.spellCheck, name: "拼写检查", symbol: "text.badge.checkmark",
                          summary: "找出外文里拼错的词，给出改法，可以直接换成改好的文字（系统自带的拼写检查，离线）",
                          accepts: [.foreignText], maxLength: 20_000)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text else { return .failure("没有文字") }
        let issues = SpellCheck.issues(in: text, language: SpellCheck.supportedLanguage(content.language))
        guard !issues.isEmpty else { return .done(toast: "没有发现拼写错误") }
        let rows = issues.map { issue in
            ResultCard.Row(label: issue.word,
                           value: issue.suggestions.isEmpty ? "（没有建议）" : issue.suggestions.joined(separator: " / "))
        }
        let corrected = SpellCheck.corrected(text, issues: issues)
        let changed = corrected != text
        return .card(ResultCard(title: "拼写检查", body: changed ? corrected : "",
                                detail: changed ? "发现 \(issues.count) 处拼写问题；上面是按第一个建议改好的文字"
                                    : "发现 \(issues.count) 处可能拼错的词，没有找到改法",
                                copyText: changed ? corrected : nil, replaceText: changed ? corrected : nil, rows: rows))
    }
}

struct TextDiffPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.textDiff, name: "文本对比", symbol: "arrow.left.arrow.right.square",
                          summary: "把选中的文字和剪贴板里的文字对比，标出删去和新增的地方", accepts: [.text],
                          maxLength: Self.maxLength)
    static let maxLength = 300_000
    /// 剪贴板里的文字（测试时换掉）
    var clipboardText: @MainActor () -> String? = { NSPasteboard.general.string(forType: .string) }

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text else { return .failure("没有文字") }
        // 选中的文字去掉了首尾的空白，剪贴板里的也一样处理，免得只差一个换行
        let copied = clipboardText()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !copied.isEmpty else {
            return .failure("剪贴板里没有文字。先复制一段文字，再选中另一段，用「文本对比」看两段有什么不同。")
        }
        guard copied.count <= Self.maxLength else { return .failure("剪贴板里的文字太长了") }
        let result = await runInBackground { TextDiff.compare(copied, text) }
        if result.isIdentical {
            return .done(toast: "两段文字完全相同")
        }
        return .card(ResultCard(title: "文本对比",
                                detail: "剪贴板 → 选中的文字：删去 \(result.removedCount) 行，新增 \(result.addedCount) 行。"
                                    + "红色是只在剪贴板里有的，绿色是只在选中的文字里有的。",
                                copyText: result.unifiedText, diff: result))
    }
}

struct HashPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.hash, name: "哈希", symbol: "number.square",
                          summary: "计算文字或文件的 MD5、SHA-1、SHA-256、SHA-512", accepts: [.text, .files])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        let files = content.files.filter { !$0.hasDirectoryPath && !Self.isDirectory($0) }
        if !content.files.isEmpty {
            guard !files.isEmpty else { return .failure("文件夹没法计算哈希，请选择文件") }
            let result: Result<[ResultCard.Row], PluginRunError> = await runInBackground {
                do {
                    if files.count == 1 {
                        return .success(try Digests.rows(forFile: files[0]))
                    }
                    return .success(try files.prefix(20).map { url in
                        ResultCard.Row(label: url.lastPathComponent, value: try Digests.sha256(ofFile: url))
                    })
                } catch {
                    return .failure(PluginRunError("读取文件失败：\(error.localizedDescription)"))
                }
            }
            switch result {
            case .success(let rows):
                let title = files.count == 1 ? files[0].lastPathComponent : "SHA-256（\(min(files.count, 20)) 个文件）"
                return .card(ResultCard(title: title, rows: rows))
            case .failure(let error):
                return .failure(error.message)
            }
        }
        guard let text = content.text else { return .failure("没有内容") }
        let rows = await runInBackground { Digests.rows(for: Data(text.utf8)) }
        return .card(ResultCard(title: "哈希（UTF-8）", rows: rows))
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory) && isDirectory.boolValue
    }
}

struct NumberConvertPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.numberConvert, name: "数字转换", symbol: "number.circle",
                          summary: "进制转换、千分位、人民币大写", accepts: [.number])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text, let number = NumberConverter.parse(text) else {
            return .failure("不是有效的数字")
        }
        return .card(ResultCard(title: "数字转换", rows: NumberConverter.rows(for: number), rowsReplaceable: true))
    }
}

struct ColorConvertPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.colorConvert, name: "颜色转换", symbol: "paintpalette",
                          summary: "HEX、RGB、HSL、SwiftUI 颜色写法互相转换，列出由浅到深的色阶", accepts: [.color])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text, let color = ColorValue.parse(text) else {
            return .failure("不是有效的颜色值")
        }
        // 下面一排是由浅到深的色阶，点一下复制色值
        return .card(ResultCard(title: "颜色转换", detail: ColorContrast.summary(for: color), rows: color.rows,
                                rowsReplaceable: true, swatchHex: color.hexString, palette: color.scale().map(\.hexString)))
    }
}

struct ContrastPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.contrast, name: "对比度", symbol: "circle.lefthalf.filled",
                          summary: "选中两个颜色（比如「#333333 #FFFFFF」），算出文字和背景的对比度，看是否达到 WCAG 的 AA、AAA",
                          accepts: [.text], maxLength: 200, check: .colorPair)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text, let pair = ColorContrast.pair(in: text) else {
            return .failure("需要两个颜色值，比如「#333333 #FFFFFF」")
        }
        return .card(ResultCard(title: "对比度",
                                detail: "前一个当文字颜色，后一个当背景；大号文字指 18pt 以上，或 14pt 以上的粗体",
                                rows: ColorContrast.rows(pair.foreground, pair.background),
                                palette: [pair.foreground.hexString, pair.background.hexString]))
    }
}

struct RandomPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.random, name: "随机生成", symbol: "dice",
                          summary: "生成 UUID、密码和随机数字，可以直接粘贴到当前输入框", accepts: [])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        .card(ResultCard(title: "随机生成", rows: RandomGenerator.rows(), rowsReplaceable: true))
    }
}

struct QuickNotePlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.quickNote, name: "收集箱", symbol: "tray.and.arrow.down",
                          summary: "把选中的文字追加到「文稿/Pop 收集箱.md」", accepts: [.text])

    static var fileURL: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: "Documents", directoryHint: .isDirectory)
        return documents.appending(path: "Pop 收集箱.md")
    }

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text else { return .failure("没有文字") }
        do {
            try Self.append(text, source: context.sourceAppName, to: Self.fileURL)
            return .done(toast: "已记到收集箱")
        } catch {
            return .failure("写入收集箱失败：\(error.localizedDescription)")
        }
    }

    static func entry(_ text: String, source: String?, date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let heading = "## " + formatter.string(from: date) + (source.map { " · \($0)" } ?? "")
        return "\n" + heading + "\n\n" + text + "\n"
    }

    static func append(_ text: String, source: String?, to url: URL, date: Date = Date()) throws {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: url.path(percentEncoded: false)) {
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("# Pop 收集箱\n".utf8).write(to: url)
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        _ = try handle.seekToEnd()
        try handle.write(contentsOf: Data(entry(text, source: source, date: date).utf8))
    }
}

struct UnitConvertPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.unitConvert, name: "单位换算", symbol: "ruler",
                          summary: "长度、重量、温度、体积、面积、速度、数据大小和传输速率互相换算，认得斤、亩等市制单位",
                          accepts: [.measurement])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text, let quantity = UnitConverter.parse(text) else {
            return .failure("没有识别到带单位的数值")
        }
        let rows = UnitConverter.rows(for: quantity)
        guard !rows.isEmpty else { return .failure("没有可以换算的单位") }
        let source = UnitConverter.display(quantity.value, quantity.unit)
        return .card(ResultCard(title: "单位换算", detail: "\(quantity.unit.category.title)：\(source)",
                                rows: rows, rowsReplaceable: true))
    }
}

struct TextCleanupPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.textCleanup, name: "文字整理", symbol: "text.alignleft",
                          summary: "合并换行、去掉空行和多余空格、中英文之间加空格、全角转半角、简繁转换、拼音、按行排序去重",
                          accepts: [.text], pattern: TextCleanup.applicablePattern, maxLength: 100_000)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text else { return .failure("没有文字") }
        let rows = await runInBackground { TextCleanup.conversions(text) }
        guard !rows.isEmpty else { return .failure("这段文字没有需要整理的地方") }
        return .card(ResultCard(title: "文字整理", rows: rows, rowsReplaceable: true, rowLineLimit: 2))
    }
}

struct ExtractInfoPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.extractInfo, name: "提取信息", symbol: "text.magnifyingglass",
                          summary: "从一段文字里找出链接、邮箱、电话号码和 IP 地址，逐个复制或者一起复制",
                          accepts: [.text], maxLength: InfoExtractor.maxLength, check: .extractable)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text else { return .failure("没有文字") }
        let items = await runInBackground { InfoExtractor.extract(text) }
        guard !items.isEmpty else { return .failure("没有找到链接、邮箱、电话号码或 IP 地址") }
        return .card(InfoExtractor.card(for: items))
    }
}

struct LineToolsPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.lineTools, name: "按行处理", symbol: "list.bullet.rectangle",
                          summary: "一列文字加引号和逗号（SQL 的 IN 列表）、转 JSON 数组、加减序号、倒序、打乱；一行用逗号隔开的拆成多行",
                          accepts: [.text], maxLength: 500_000, check: .lineList)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text, let items = LineTools.items(text) else {
            return .failure("需要至少两项：一行一项，或者一行里用逗号隔开")
        }
        let rows = await runInBackground { LineTools.conversions(text) }
        guard !rows.isEmpty else { return .failure("这些内容没有可以转换的写法") }
        return .card(ResultCard(title: "按行处理", detail: "共 \(items.values.count) 项", rows: rows,
                                rowsReplaceable: true, rowLineLimit: 2))
    }
}

struct ReminderPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.reminder, name: "加到提醒事项", symbol: "checklist",
                          summary: "从选中的文字里认出时间（明天下午 3 点、周五、10 月 8 日、半小时后……），加到「提醒事项」或者「日历」",
                          accepts: [.text], maxLength: 500, check: .dateMention)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text else { return .failure("没有文字") }
        return .reminder(text: text)
    }
}
