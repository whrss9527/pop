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
        return .card(ResultCard(title: text, body: Self.format(definition), copyText: definition, buttons: buttons))
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
                          summary: "HEX、RGB、HSL、SwiftUI 颜色写法互相转换", accepts: [.color])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text, let color = ColorValue.parse(text) else {
            return .failure("不是有效的颜色值")
        }
        return .card(ResultCard(title: "颜色转换", rows: color.rows, rowsReplaceable: true, swatchHex: color.hexString))
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
