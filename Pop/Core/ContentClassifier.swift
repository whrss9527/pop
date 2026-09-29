import Foundation
import NaturalLanguage
import UniformTypeIdentifiers

/// 把原始选中内容归类，供分发规则和插件匹配使用。
enum ContentClassifier {
    static func classify(_ selection: SelectionContent) -> ClassifiedContent {
        switch selection {
        case .none:
            return .empty
        case .image:
            return ClassifiedContent(selection: selection, kinds: [.image], text: nil, language: nil, url: nil, files: [])
        case .files(let urls):
            guard !urls.isEmpty else { return .empty }
            var kinds: Set<ContentKind> = [.files]
            if urls.allSatisfy(isImageFile) {
                kinds.insert(.imageFile)
            }
            return ClassifiedContent(selection: selection, kinds: kinds, text: nil, language: nil, url: nil, files: urls)
        case .text(let raw):
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return .empty }
            return classifyText(text)
        }
    }

    private static func classifyText(_ text: String) -> ClassifiedContent {
        var content = ClassifiedContent(selection: .text(text), kinds: [.text], text: text, language: nil, url: nil, files: [])

        // 结构化文本（链接、JSON、颜色、时间、带单位的数值、数字、算式、路径）不再算作自然语言，避免被「外文直接翻译」误触发。
        if let url = detectLink(text) {
            content.url = url
            content.kinds.insert(url.scheme?.lowercased() == "mailto" ? .email : .url)
        } else if JSONFormatter.isJSON(text) {
            content.kinds.insert(.json)
        } else if ColorValue.parse(text) != nil {
            content.kinds.insert(.color)
        } else if TimestampConverter.date(from: text) != nil {
            content.kinds.insert(.timestamp)
        } else if let path = detectFilePath(text) {
            content.files = [path]
            content.kinds.insert(.files)
            if isImageFile(path) {
                content.kinds.insert(.imageFile)
            }
        } else if DateParser.parse(text) != nil {
            content.kinds.insert(.dateTime)
        } else if UnitConverter.parse(text) != nil {
            content.kinds.insert(.measurement)
        } else if NumberConverter.parse(text) != nil {
            content.kinds.insert(.number)
        } else if looksLikeMath(text) {
            content.kinds.insert(.math)
        } else if looksLikeToken(text) {
            // 令牌、哈希、密钥这类串只当普通文字，不算外文（免得被「外文直接翻译」接走）
        } else {
            let profile = ScriptProfile(text)
            if profile.isChinese {
                content.kinds.insert(.chineseText)
                let detected = dominantLanguage(text)
                content.language = detected?.hasPrefix("zh") == true ? detected : "zh-Hans"
            } else if profile.hasLetters {
                content.kinds.insert(.foreignText)
                let detected = dominantLanguage(text)
                content.language = detected?.hasPrefix("zh") == true ? nil : detected
            }
            if profile.hasLetters, isSingleWord(text) {
                content.kinds.insert(.word)
            }
        }
        return content
    }

    /// 没有空白、又长又混着字母和数字的串：JWT、哈希、API Key、提交号、订单号……
    static func looksLikeToken(_ text: String) -> Bool {
        guard text.count >= 16, !text.contains(where: \.isWhitespace) else { return false }
        return text.contains(where: { $0.isASCII && $0.isNumber }) && text.contains(where: { $0.isASCII && $0.isLetter })
            && ScriptProfile(text).han == 0
    }

    /// 单个英文单词（可以带连字符、撇号），或者不超过 8 个字的纯中文词。
    static func isSingleWord(_ text: String) -> Bool {
        guard text.count <= 40, text.first?.isLetter == true, text.last?.isLetter == true else { return false }
        let allowed = text.allSatisfy { $0.isLetter || $0 == "-" || $0 == "'" || $0 == "’" }
        guard allowed else { return false }
        let profile = ScriptProfile(text)
        if profile.han > 0 {
            return profile.han == text.count && text.count <= 8
        }
        return text.count >= 2 && profile.kana == 0 && profile.hangul == 0
    }

    /// 选中的是一个本机上存在的路径（/ 或 ~/ 开头）。
    static func detectFilePath(_ text: String) -> URL? {
        guard text.count < 1024, text.hasPrefix("/") || text.hasPrefix("~/"), !text.contains(where: \.isNewline) else { return nil }
        let path = (text as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }

    static func isImageFile(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true
    }

    /// 整段文字是一个链接或邮箱时返回对应 URL。
    /// 只认带协议头、www. 开头或邮箱，避免把 README.md、main.py 这类文件名当成域名。
    static func detectLink(_ text: String) -> URL? {
        guard text.count < 2048, !text.contains(where: { $0.isWhitespace }) else { return nil }
        let lowered = text.lowercased()
        let explicit = lowered.contains("://") || lowered.hasPrefix("www.") || lowered.hasPrefix("mailto:") || text.contains("@")
        guard explicit,
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = detector.firstMatch(in: text, options: [], range: range),
              match.range == range else { return nil }
        return match.url
    }

    /// 形如 `1+2*3`、`(3.5 - 1) / 2`、`200*15%` 的算式。
    /// 只有减号或斜杠、且没有空格的串（2026-09-28、138-0000-0000、9/28）当作日期或编号。
    static func looksLikeMath(_ text: String) -> Bool {
        guard text.count <= 200 else { return false }
        let chars = Calculator.normalize(text)
        guard chars.count >= 3 else { return false }
        let binaryOperators: Set<Character> = ["+", "-", "*", "/", "^"]
        let allowed = chars.allSatisfy { ($0.isASCII && $0.isNumber) || binaryOperators.contains($0) || "%.()".contains($0) }
        guard allowed, chars.contains(where: { $0.isASCII && $0.isNumber }) else { return false }
        let operators = chars.dropFirst().filter { binaryOperators.contains($0) }
        guard !operators.isEmpty else { return false }
        let looksLikeIdentifier = !text.contains(" ") && !chars.contains("(")
            && (operators.allSatisfy { $0 == "-" } || operators.allSatisfy { $0 == "/" })
        guard !looksLikeIdentifier else { return false }
        return Calculator.evaluate(text) != nil
    }

    static func dominantLanguage(_ text: String) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(String(text.prefix(2000)))
        return recognizer.dominantLanguage?.rawValue
    }
}
