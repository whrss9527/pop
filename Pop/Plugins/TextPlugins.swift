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

struct TextStatsPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.textStats, name: String(localized: "字数统计"), symbol: "number",
                          summary: String(localized: "统计字符、汉字、单词、行数和阅读时间"), accepts: [.text])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text else { return .failure(String(localized: "没有文字")) }
        let statistics = await runInBackground { TextStatistics(text) }
        return .card(ResultCard(title: String(localized: "字数统计"), rows: statistics.rows))
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
