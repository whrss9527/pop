import AppKit
import AVFoundation
import CoreServices

struct DictionaryPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.dictionary, name: String(localized: "词典"), symbol: "character.book.closed",
                          summary: String(localized: "用系统「词典」查询选中的单词或词语"), accepts: [.text], maxLength: 60)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text else { return .failure(String(localized: "没有可查询的词")) }
        var buttons: [CardButton] = []
        if let encoded = text.addingPercentEncoding(withAllowedCharacters: .popURLValueAllowed),
           let url = URL(string: "dict://\(encoded)") {
            buttons.append(CardButton(title: String(localized: "在词典中打开"), action: .open(url)))
        }
        let range = CFRange(location: 0, length: (text as NSString).length)
        guard let definition = DCSCopyTextDefinition(nil, text as CFString, range)?.takeRetainedValue() as String? else {
            return .card(ResultCard(title: String(localized: "词典"), body: String(localized: "系统词典里没有找到「\(text)」。可以在「词典」App 的设置里启用更多词典。"),
                                    buttons: buttons))
        }
        if VocabularyStore.isWordLike(text) {
            buttons.append(CardButton(title: String(localized: "加入生词本"), action: .addToVocabulary(word: text, translation: Self.brief(definition, word: text),
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
    let info = PluginInfo(id: BuiltinPluginID.speak, name: String(localized: "朗读"), symbol: "speaker.wave.2",
                          summary: String(localized: "用系统语音朗读选中的文字，朗读中再用一次就停止"), accepts: [.text])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        if Speaker.shared.isSpeaking {
            Speaker.shared.stop()
            return .done(toast: String(localized: "已停止朗读"))
        }
        guard let text = content.text else { return .failure(String(localized: "没有可朗读的文字")) }
        let language = content.language ?? ContentClassifier.dominantLanguage(text)
        Speaker.shared.speak(text, language: language)
        return .done(toast: String(localized: "正在朗读…"))
    }
}

struct TextImagePlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.textImage, name: String(localized: "文字转图片"), symbol: "text.below.photo",
                          summary: String(localized: "把选中的文字排成一张手机上看着舒服的长图（宽 1080 像素），白底、米黄、深色三种底色，可以复制、存储或贴到屏幕上"),
                          accepts: [.text], maxLength: 50_000)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text else { return .failure(String(localized: "没有文字")) }
        return Self.outcome(text, style: .paper)
    }

    @MainActor static func outcome(_ text: String, style: TextImage.Style) -> PluginOutcome {
        guard let png = TextImage.render(text, style: style) else { return .failure(String(localized: "没能把这段文字画成图片")) }
        return .card(TextImage.card(text, style: style, png: png))
    }
}

struct ChangeCasePlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.changeCase, name: String(localized: "大小写"), symbol: "textformat",
                          summary: String(localized: "大写、小写、驼峰、下划线等写法互相转换"), accepts: [.text],
                          pattern: "[A-Za-z]", maxLength: 20_000)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text else { return .failure(String(localized: "没有文字")) }
        let rows = CaseConverter.conversions(text)
        guard !rows.isEmpty else { return .failure(String(localized: "没有可以转换的字母")) }
        return .card(ResultCard(title: String(localized: "大小写转换"), rows: rows, rowsReplaceable: true))
    }
}

struct EncodeDecodePlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.encodeDecode, name: String(localized: "编码转换"), symbol: "chevron.left.forwardslash.chevron.right",
                          summary: String(localized: "Base64、URL、Unicode、HTML 实体的编码和解码"), accepts: [.text], maxLength: 200_000)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text else { return .failure(String(localized: "没有文字")) }
        let rows = await runInBackground { TextCodec.conversions(text) }
        return .card(ResultCard(title: String(localized: "编码转换"), rows: rows, rowsReplaceable: true))
    }
}

struct TextStatsPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.textStats, name: String(localized: "字数统计"), symbol: "number",
                          summary: String(localized: "统计字符、汉字、单词、行数和阅读时间"), accepts: [.text])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text else { return .failure(String(localized: "没有文字")) }
        let statistics = await runInBackground { TextStatistics(text) }
        return .card(ResultCard(title: String(localized: "字数统计"), rows: statistics.rows))
    }
}

struct NumberStatsPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.numberStats, name: String(localized: "数字统计"), symbol: "sum",
                          summary: String(localized: "选中一列或一串数字，算出合计、平均、中位数、最大、最小"), accepts: [.text],
                          maxLength: 100_000, check: .numberList)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text, let summary = await runInBackground({ NumberStats.parse(text) }) else {
            return .failure(String(localized: "需要至少两个数：一列（每行一个，前面可以有文字），或者一行用逗号、空格隔开"))
        }
        return .card(ResultCard(title: String(localized: "数字统计"), detail: String(localized: "共 \(summary.count) 个数"), rows: summary.rows))
    }
}

struct TextDiffPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.textDiff, name: String(localized: "文本对比"), symbol: "arrow.left.arrow.right.square",
                          summary: String(localized: "把选中的文字和剪贴板里的文字对比，标出删去和新增的地方"), accepts: [.text],
                          maxLength: Self.maxLength)
    static let maxLength = 300_000
    /// 剪贴板里的文字（测试时换掉）
    var clipboardText: @MainActor () -> String? = { NSPasteboard.general.string(forType: .string) }

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text else { return .failure(String(localized: "没有文字")) }
        // 选中的文字去掉了首尾的空白，剪贴板里的也一样处理，免得只差一个换行
        let copied = clipboardText()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !copied.isEmpty else {
            return .failure(String(localized: "剪贴板里没有文字。先复制一段文字，再选中另一段，用「文本对比」看两段有什么不同。"))
        }
        guard copied.count <= Self.maxLength else { return .failure(String(localized: "剪贴板里的文字太长了")) }
        let result = await runInBackground { TextDiff.compare(copied, text) }
        if result.isIdentical {
            return .done(toast: String(localized: "两段文字完全相同"))
        }
        return .card(ResultCard(title: String(localized: "文本对比"),
                                detail: String(localized: "剪贴板 → 选中的文字：删去 \(result.removedCount) 行，新增 \(result.addedCount) 行。红色是只在剪贴板里有的，绿色是只在选中的文字里有的。"),
                                copyText: result.unifiedText, diff: result))
    }
}

struct HashPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.hash, name: String(localized: "哈希"), symbol: "number.square",
                          summary: String(localized: "计算文字或文件的 MD5、SHA-1、SHA-256、SHA-512"), accepts: [.text, .files])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        let files = content.files.filter { !$0.hasDirectoryPath && !Self.isDirectory($0) }
        if !content.files.isEmpty {
            guard !files.isEmpty else { return .failure(String(localized: "文件夹没法计算哈希，请选择文件")) }
            let result: Result<[ResultCard.Row], PluginRunError> = await runInBackground {
                do {
                    if files.count == 1 {
                        return .success(try Digests.rows(forFile: files[0]))
                    }
                    return .success(try files.prefix(20).map { url in
                        ResultCard.Row(label: url.lastPathComponent, value: try Digests.sha256(ofFile: url))
                    })
                } catch {
                    return .failure(PluginRunError(String(localized: "读取文件失败：\(error.localizedDescription)")))
                }
            }
            switch result {
            case .success(let rows):
                let title = files.count == 1 ? files[0].lastPathComponent : String(localized: "SHA-256（\(min(files.count, 20)) 个文件）")
                return .card(ResultCard(title: title, rows: rows))
            case .failure(let error):
                return .failure(error.message)
            }
        }
        guard let text = content.text else { return .failure(String(localized: "没有内容")) }
        let rows = await runInBackground { Digests.rows(for: Data(text.utf8)) }
        return .card(ResultCard(title: String(localized: "哈希（UTF-8）"), rows: rows))
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory) && isDirectory.boolValue
    }
}

struct NumberConvertPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.numberConvert, name: String(localized: "数字转换"), symbol: "number.circle",
                          summary: String(localized: "进制转换、千分位、人民币大写"), accepts: [.number])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text, let number = NumberConverter.parse(text) else {
            return .failure(String(localized: "不是有效的数字"))
        }
        return .card(ResultCard(title: String(localized: "数字转换"), rows: NumberConverter.rows(for: number), rowsReplaceable: true))
    }
}

struct ColorConvertPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.colorConvert, name: String(localized: "颜色转换"), symbol: "paintpalette",
                          summary: String(localized: "HEX、RGB、HSL、SwiftUI 颜色写法互相转换，列出由浅到深的色阶"), accepts: [.color])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text, let color = ColorValue.parse(text) else {
            return .failure(String(localized: "不是有效的颜色值"))
        }
        // 下面一排是由浅到深的色阶，点一下复制色值
        return .card(ResultCard(title: String(localized: "颜色转换"), detail: ColorContrast.summary(for: color), rows: color.rows,
                                rowsReplaceable: true, swatchHex: color.hexString, palette: color.scale().map(\.hexString)))
    }
}

struct ContrastPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.contrast, name: String(localized: "对比度"), symbol: "circle.lefthalf.filled",
                          summary: String(localized: "选中两个颜色（比如「#333333 #FFFFFF」），算出文字和背景的对比度，看是否达到 WCAG 的 AA、AAA"),
                          accepts: [.text], maxLength: 200, check: .colorPair)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text, let pair = ColorContrast.pair(in: text) else {
            return .failure(String(localized: "需要两个颜色值，比如「#333333 #FFFFFF」"))
        }
        return .card(ResultCard(title: String(localized: "对比度"),
                                detail: String(localized: "前一个当文字颜色，后一个当背景；大号文字指 18pt 以上，或 14pt 以上的粗体"),
                                rows: ColorContrast.rows(pair.foreground, pair.background),
                                palette: [pair.foreground.hexString, pair.background.hexString]))
    }
}

struct RandomPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.random, name: String(localized: "随机生成"), symbol: "dice",
                          summary: String(localized: "生成 UUID、密码和随机数字，可以直接粘贴到当前输入框"), accepts: [])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        .card(ResultCard(title: String(localized: "随机生成"), rows: RandomGenerator.rows(), rowsReplaceable: true))
    }
}

struct QuickNotePlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.quickNote, name: String(localized: "收集箱"), symbol: "tray.and.arrow.down",
                          summary: String(localized: "把选中的文字追加到「文稿/Pop 收集箱.md」"), accepts: [.text])

    static var fileURL: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: "Documents", directoryHint: .isDirectory)
        return documents.appending(path: "Pop 收集箱.md")
    }

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text else { return .failure(String(localized: "没有文字")) }
        do {
            try Self.append(text, source: context.sourceAppName, to: Self.fileURL)
            return .done(toast: String(localized: "已记到收集箱"))
        } catch {
            return .failure(String(localized: "写入收集箱失败：\(error.localizedDescription)"))
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
    let info = PluginInfo(id: BuiltinPluginID.unitConvert, name: String(localized: "单位换算"), symbol: "ruler",
                          summary: String(localized: "长度、重量、温度、体积、面积、速度、数据大小和传输速率互相换算，认得斤、亩等市制单位"),
                          accepts: [.measurement])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text, let quantity = UnitConverter.parse(text) else {
            return .failure(String(localized: "没有识别到带单位的数值"))
        }
        let rows = UnitConverter.rows(for: quantity)
        guard !rows.isEmpty else { return .failure(String(localized: "没有可以换算的单位")) }
        let source = UnitConverter.display(quantity.value, quantity.unit)
        return .card(ResultCard(title: String(localized: "单位换算"), detail: String(localized: "\(quantity.unit.category.title)：\(source)"),
                                rows: rows, rowsReplaceable: true))
    }
}

struct TextCleanupPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.textCleanup, name: String(localized: "文字整理"), symbol: "text.alignleft",
                          summary: String(localized: "合并换行、去掉空行和多余空格、中英文之间加空格、全角转半角、简繁转换、拼音、按行排序去重"),
                          accepts: [.text], pattern: TextCleanup.applicablePattern, maxLength: 100_000)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text else { return .failure(String(localized: "没有文字")) }
        let rows = await runInBackground { TextCleanup.conversions(text) }
        guard !rows.isEmpty else { return .failure(String(localized: "这段文字没有需要整理的地方")) }
        return .card(ResultCard(title: String(localized: "文字整理"), rows: rows, rowsReplaceable: true, rowLineLimit: 2))
    }
}

struct ExtractInfoPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.extractInfo, name: String(localized: "提取信息"), symbol: "text.magnifyingglass",
                          summary: String(localized: "从一段文字里找出链接、邮箱、电话号码和 IP 地址，逐个复制或者一起复制"),
                          accepts: [.text], maxLength: InfoExtractor.maxLength, check: .extractable)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text else { return .failure(String(localized: "没有文字")) }
        let items = await runInBackground { InfoExtractor.extract(text) }
        guard !items.isEmpty else { return .failure(String(localized: "没有找到链接、邮箱、电话号码或 IP 地址")) }
        return .card(InfoExtractor.card(for: items))
    }
}

struct IDNumberPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.idNumber, name: String(localized: "证件号码"), symbol: "person.text.rectangle",
                          summary: String(localized: "身份证号、统一社会信用代码、银行卡号：检查校验位，读出出生日期、年龄、性别、地区和登记管理部门，不联网"),
                          accepts: [.text, .number], maxLength: 40, check: .idNumber)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text, let info = IDNumber.parse(text) else {
            return .failure(String(localized: "没有认出身份证号、统一社会信用代码或银行卡号"))
        }
        return .card(IDNumber.card(info))
    }
}

struct LineToolsPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.lineTools, name: String(localized: "按行处理"), symbol: "list.bullet.rectangle",
                          summary: String(localized: "一列文字加引号和逗号（SQL 的 IN 列表）、转 JSON 数组、加减序号、倒序、打乱；一行用逗号隔开的拆成多行"),
                          accepts: [.text], maxLength: 500_000, check: .lineList)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text, let items = LineTools.items(text) else {
            return .failure(String(localized: "需要至少两项：一行一项，或者一行里用逗号隔开"))
        }
        let rows = await runInBackground { LineTools.conversions(text) }
        guard !rows.isEmpty else { return .failure(String(localized: "这些内容没有可以转换的写法")) }
        return .card(ResultCard(title: String(localized: "按行处理"), detail: String(localized: "共 \(items.values.count) 项"), rows: rows,
                                rowsReplaceable: true, rowLineLimit: 2))
    }
}

struct ReminderPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.reminder, name: String(localized: "加到提醒事项"), symbol: "checklist",
                          summary: String(localized: "从选中的文字里认出时间（明天下午 3 点、周五、10 月 8 日、半小时后……），加到「提醒事项」或者「日历」"),
                          accepts: [.text], maxLength: 500, check: .dateMention)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text else { return .failure(String(localized: "没有文字")) }
        return .reminder(text: text)
    }
}
