import CryptoKit
import Foundation
import NaturalLanguage

// 各个文字处理功能的纯逻辑部分，不依赖界面，方便测试。

// MARK: - 大小写

enum CaseConverter {
    /// 拆成单词：按空格、标点拆分，也拆开驼峰写法（getHTTPResponse → get、HTTP、Response）。
    static func words(_ text: String) -> [String] {
        var words: [String] = []
        var current = ""
        let characters = Array(text)
        for (index, character) in characters.enumerated() {
            guard character.isLetter || character.isNumber else {
                if !current.isEmpty {
                    words.append(current)
                    current = ""
                }
                continue
            }
            if let last = current.last {
                let next: Character? = index + 1 < characters.count ? characters[index + 1] : nil
                let lowerToUpper = (last.isLowercase || last.isNumber) && character.isUppercase
                let acronymEnds = last.isUppercase && character.isUppercase && (next?.isLowercase ?? false)
                if lowerToUpper || acronymEnds {
                    words.append(current)
                    current = ""
                }
            }
            current.append(character)
        }
        if !current.isEmpty {
            words.append(current)
        }
        return words
    }

    static func conversions(_ text: String) -> [ResultCard.Row] {
        let lower = words(text).map { $0.lowercased() }
        guard let first = lower.first else { return [] }
        let capitalized = lower.map { String($0.prefix(1)).uppercased() + String($0.dropFirst()) }
        return [
            ResultCard.Row(label: "大写", value: text.uppercased()),
            ResultCard.Row(label: "小写", value: text.lowercased()),
            ResultCard.Row(label: "首字母大写", value: text.capitalized),
            ResultCard.Row(label: "camelCase", value: first + capitalized.dropFirst().joined()),
            ResultCard.Row(label: "PascalCase", value: capitalized.joined()),
            ResultCard.Row(label: "snake_case", value: lower.joined(separator: "_")),
            ResultCard.Row(label: "kebab-case", value: lower.joined(separator: "-")),
            ResultCard.Row(label: "CONSTANT", value: lower.joined(separator: "_").uppercased()),
        ]
    }
}

// MARK: - 编码转换

enum TextCodec {
    /// 能解码的放在前面（选中一段编码过的文字时，多半是想看原文）。
    static func conversions(_ text: String) -> [ResultCard.Row] {
        var rows: [ResultCard.Row] = []
        if let decoded = base64Decode(text), decoded != text {
            rows.append(ResultCard.Row(label: "Base64 解码", value: decoded))
        }
        if let decoded = urlDecode(text), decoded != text {
            rows.append(ResultCard.Row(label: "URL 解码", value: decoded))
        }
        if let decoded = unicodeUnescape(text), decoded != text {
            rows.append(ResultCard.Row(label: "Unicode 还原", value: decoded))
        }
        if let decoded = htmlUnescape(text), decoded != text {
            rows.append(ResultCard.Row(label: "HTML 还原", value: decoded))
        }
        rows.append(ResultCard.Row(label: "Base64 编码", value: base64Encode(text)))
        rows.append(ResultCard.Row(label: "URL 编码", value: urlEncode(text)))
        let unicode = unicodeEscape(text)
        if unicode != text {
            rows.append(ResultCard.Row(label: "Unicode 转义", value: unicode))
        }
        let html = htmlEscape(text)
        if html != text {
            rows.append(ResultCard.Row(label: "HTML 转义", value: html))
        }
        return rows
    }

    static func base64Encode(_ text: String) -> String {
        Data(text.utf8).base64EncodedString()
    }

    /// 支持标准和 URL 安全两种字母表，缺的补齐等号；解出来不是正常文字时返回 nil。
    static func base64Decode(_ text: String) -> String? {
        var normalized = text.filter { !$0.isWhitespace }
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        guard normalized.count >= 4,
              normalized.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "+/=".contains($0)) }) else { return nil }
        let remainder = normalized.count % 4
        guard remainder != 1 else { return nil }
        if remainder > 0 {
            normalized += String(repeating: "=", count: 4 - remainder)
        }
        guard let data = Data(base64Encoded: normalized),
              let decoded = String(data: data, encoding: .utf8), !decoded.isEmpty else { return nil }
        let allowedControls: Set<Unicode.Scalar> = ["\n", "\r", "\t"]
        let readable = decoded.unicodeScalars.allSatisfy { scalar in
            allowedControls.contains(scalar) || !CharacterSet.controlCharacters.contains(scalar)
        }
        return readable ? decoded : nil
    }

    static func urlEncode(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: .popURLValueAllowed) ?? text
    }

    static func urlDecode(_ text: String) -> String? {
        guard text.contains("%") else { return nil }
        return text.removingPercentEncoding
    }

    /// 非 ASCII 字符转成 \uXXXX（和 JavaScript、JSON 一样按 UTF-16 编码，表情等字符是一对代理项）。
    static func unicodeEscape(_ text: String) -> String {
        var result = ""
        for unit in text.utf16 {
            if unit < 0x80 {
                result.unicodeScalars.append(Unicode.Scalar(UInt8(unit)))
            } else {
                result += String(format: "\\u%04x", unit)
            }
        }
        return result
    }

    /// 还原 \uXXXX（含代理项对）和 \u{XXXXX}。
    static func unicodeUnescape(_ text: String) -> String? {
        guard text.contains("\\u") else { return nil }
        let scalars = Array(text.unicodeScalars)
        var result = ""
        var pendingUnits: [UInt16] = []

        func flushUnits() {
            if !pendingUnits.isEmpty {
                result += String(decoding: pendingUnits, as: UTF16.self)
                pendingUnits.removeAll()
            }
        }

        func hexValue(_ range: Range<Int>) -> UInt32? {
            guard range.lowerBound >= 0, range.upperBound <= scalars.count, !range.isEmpty else { return nil }
            var view = String.UnicodeScalarView()
            view.append(contentsOf: scalars[range])
            return UInt32(String(view), radix: 16)
        }

        var index = 0
        while index < scalars.count {
            if scalars[index] == "\\", index + 1 < scalars.count, scalars[index + 1] == "u" {
                if index + 2 < scalars.count, scalars[index + 2] == "{",
                   let close = scalars[(index + 3)...].firstIndex(of: "}"), close - (index + 3) <= 6,
                   let value = hexValue((index + 3)..<close), let scalar = Unicode.Scalar(value) {
                    flushUnits()
                    result.unicodeScalars.append(scalar)
                    index = close + 1
                    continue
                }
                if let value = hexValue((index + 2)..<(index + 6)), value <= 0xFFFF {
                    pendingUnits.append(UInt16(value))
                    index += 6
                    continue
                }
            }
            flushUnits()
            result.unicodeScalars.append(scalars[index])
            index += 1
        }
        flushUnits()
        return result
    }

    static func htmlEscape(_ text: String) -> String {
        var result = ""
        for character in text {
            switch character {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            case "'": result += "&#39;"
            default: result.append(character)
            }
        }
        return result
    }

    private static let namedEntities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}",
        "copy": "©", "reg": "®", "trade": "™", "hellip": "…", "mdash": "—", "ndash": "–",
        "lsquo": "‘", "rsquo": "’", "ldquo": "“", "rdquo": "”", "middot": "·", "yen": "¥", "euro": "€",
    ]

    static func htmlUnescape(_ text: String) -> String? {
        guard text.contains("&"), text.contains(";") else { return nil }
        var result = ""
        var index = text.startIndex
        while index < text.endIndex {
            if text[index] == "&", let semicolon = text[index...].prefix(12).firstIndex(of: ";") {
                let entity = text[text.index(after: index)..<semicolon]
                var replacement: String?
                if entity.hasPrefix("#x") || entity.hasPrefix("#X") {
                    if let value = UInt32(String(entity.dropFirst(2)), radix: 16), let scalar = Unicode.Scalar(value) {
                        replacement = String(Character(scalar))
                    }
                } else if entity.hasPrefix("#") {
                    if let value = UInt32(String(entity.dropFirst()), radix: 10), let scalar = Unicode.Scalar(value) {
                        replacement = String(Character(scalar))
                    }
                } else {
                    replacement = namedEntities[String(entity)]
                }
                if let replacement {
                    result += replacement
                    index = text.index(after: semicolon)
                    continue
                }
            }
            result.append(text[index])
            index = text.index(after: index)
        }
        return result
    }
}

// MARK: - 字数统计

struct TextStatistics: Equatable {
    var characters: Int
    var nonWhitespace: Int
    var chinese: Int
    var words: Int
    var lines: Int
    var utf8Bytes: Int
    /// 按中文每分钟 400 字、英文每分钟 200 词估算
    var readingMinutes: Double

    init(_ text: String) {
        characters = text.count
        nonWhitespace = text.filter { !$0.isWhitespace }.count
        let profile = ScriptProfile(text)
        chinese = profile.han
        lines = text.isEmpty ? 0 : text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).count
        utf8Bytes = text.utf8.count
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var count = 0
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { _, _ in
            count += 1
            return true
        }
        words = count
        readingMinutes = Double(profile.han) / 400 + Double(profile.otherWords) / 200
    }

    var readingTime: String {
        readingMinutes < 1 ? "不到 1 分钟" : "约 \(Int(readingMinutes.rounded())) 分钟"
    }

    var rows: [ResultCard.Row] {
        var rows = [
            ResultCard.Row(label: "字符", value: "\(characters)"),
            ResultCard.Row(label: "不含空白", value: "\(nonWhitespace)"),
        ]
        if chinese > 0 {
            rows.append(ResultCard.Row(label: "汉字", value: "\(chinese)"))
        }
        rows.append(ResultCard.Row(label: "词", value: "\(words)"))
        rows.append(ResultCard.Row(label: "行", value: "\(lines)"))
        rows.append(ResultCard.Row(label: "UTF-8 字节", value: "\(utf8Bytes)"))
        rows.append(ResultCard.Row(label: "阅读时间", value: readingTime))
        return rows
    }
}

// MARK: - 哈希

enum Digests {
    static func rows(for data: Data) -> [ResultCard.Row] {
        [
            ResultCard.Row(label: "MD5", value: hex(Insecure.MD5.hash(data: data))),
            ResultCard.Row(label: "SHA-1", value: hex(Insecure.SHA1.hash(data: data))),
            ResultCard.Row(label: "SHA-256", value: hex(SHA256.hash(data: data))),
            ResultCard.Row(label: "SHA-512", value: hex(SHA512.hash(data: data))),
        ]
    }

    /// 分块读取，大文件也不会一次读进内存。
    static func rows(forFile url: URL) throws -> [ResultCard.Row] {
        var md5 = Insecure.MD5()
        var sha1 = Insecure.SHA1()
        var sha256 = SHA256()
        var sha512 = SHA512()
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            md5.update(data: chunk)
            sha1.update(data: chunk)
            sha256.update(data: chunk)
            sha512.update(data: chunk)
        }
        return [
            ResultCard.Row(label: "MD5", value: hex(md5.finalize())),
            ResultCard.Row(label: "SHA-1", value: hex(sha1.finalize())),
            ResultCard.Row(label: "SHA-256", value: hex(sha256.finalize())),
            ResultCard.Row(label: "SHA-512", value: hex(sha512.finalize())),
        ]
    }

    static func sha256(ofFile url: URL) throws -> String {
        var hasher = SHA256()
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hex(hasher.finalize())
    }

    static func sha256(_ data: Data) -> String {
        hex(SHA256.hash(data: data))
    }

    static func hex<Bytes: Sequence>(_ bytes: Bytes) -> String where Bytes.Element == UInt8 {
        bytes.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - 数字

struct ParsedNumber: Equatable {
    /// 整数值；有小数部分时为 nil
    var integer: Int?
    var decimal: Decimal
    /// 原文的进制：10、16、8、2
    var radix: Int
}

enum NumberConverter {
    private static let decimalPattern = try! NSRegularExpression(pattern: #"^(\d{1,3}(,\d{3})+|\d+)(\.\d+)?$"#)

    /// 十进制（可以带千分位逗号和小数）、0x 十六进制、0b 二进制、0o 八进制。
    static func parse(_ text: String) -> ParsedNumber? {
        var body = text.trimmingCharacters(in: .whitespaces)
        guard !body.isEmpty, body.count <= 40 else { return nil }
        var negative = false
        if body.hasPrefix("-") {
            negative = true
            body.removeFirst()
        } else if body.hasPrefix("+") {
            body.removeFirst()
        }
        let lower = body.lowercased()
        for (prefix, radix) in [("0x", 16), ("0b", 2), ("0o", 8)] where lower.hasPrefix(prefix) {
            let digits = String(lower.dropFirst(2)).replacingOccurrences(of: "_", with: "")
            guard !digits.isEmpty, let magnitude = Int(digits, radix: radix) else { return nil }
            let value = negative ? -magnitude : magnitude
            return ParsedNumber(integer: value, decimal: Decimal(value), radix: radix)
        }
        let range = NSRange(body.startIndex..., in: body)
        guard decimalPattern.firstMatch(in: body, options: [], range: range) != nil else { return nil }
        let plain = body.replacingOccurrences(of: ",", with: "")
        guard let magnitude = Decimal(string: plain, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        let integer = plain.contains(".") ? nil : Int(plain).map { negative ? -$0 : $0 }
        return ParsedNumber(integer: integer, decimal: negative ? -magnitude : magnitude, radix: 10)
    }

    static func rows(for number: ParsedNumber) -> [ResultCard.Row] {
        var rows: [ResultCard.Row] = []
        if let value = number.integer {
            rows.append(ResultCard.Row(label: "十进制", value: String(value)))
            rows.append(ResultCard.Row(label: "十六进制", value: signed(value, radix: 16, prefix: "0x")))
            rows.append(ResultCard.Row(label: "八进制", value: signed(value, radix: 8, prefix: "0o")))
            rows.append(ResultCard.Row(label: "二进制", value: signed(value, radix: 2, prefix: "0b")))
        }
        rows.append(ResultCard.Row(label: "千分位", value: grouped(number.decimal)))
        if let uppercase = rmbUppercase(number.decimal) {
            rows.append(ResultCard.Row(label: "人民币大写", value: uppercase))
        }
        return rows
    }

    static func signed(_ value: Int, radix: Int, prefix: String) -> String {
        (value < 0 ? "-" : "") + prefix + String(value.magnitude, radix: radix, uppercase: true)
    }

    static func grouped(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 10
        return formatter.string(from: value as NSDecimalNumber) ?? "\(value)"
    }

    /// 人民币金额大写，比如 1234.5 → 壹仟贰佰叁拾肆元伍角。整数部分最多 16 位。
    static func rmbUppercase(_ value: Decimal) -> String? {
        var input = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &input, 2, .plain)
        var text = NSDecimalNumber(decimal: rounded).stringValue
        var negative = false
        if text.hasPrefix("-") {
            negative = true
            text.removeFirst()
        }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard let integerPart = parts.first else { return nil }
        let fractionPart = parts.count > 1 ? String(parts[1]) : ""
        let fraction = Array(String((fractionPart + "00").prefix(2)))
        guard !integerPart.isEmpty, integerPart.count <= 16,
              integerPart.allSatisfy({ $0.isASCII && $0.isNumber }),
              fraction.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }

        let names: [Character] = ["零", "壹", "贰", "叁", "肆", "伍", "陆", "柒", "捌", "玖"]
        let positionUnits = ["", "拾", "佰", "仟"]
        let groupUnits = ["", "万", "亿", "万亿"]
        let digits = integerPart.compactMap(\.wholeNumberValue)

        var integerText = ""
        if digits.contains(where: { $0 != 0 }) {
            var pendingZero = false
            for (offset, digit) in digits.enumerated() {
                let position = digits.count - 1 - offset
                let unitIndex = position % 4
                let groupIndex = position / 4
                if digit == 0 {
                    if !integerText.isEmpty {
                        pendingZero = true
                    }
                } else {
                    if pendingZero {
                        integerText.append("零")
                        pendingZero = false
                    }
                    integerText.append(names[digit])
                    integerText += positionUnits[unitIndex]
                }
                // 每四位一组，组内有非零数字才加「万」「亿」；组尾的零被单位吸收，不读「零」
                if unitIndex == 0, groupIndex > 0 {
                    let groupStart = max(0, offset - 3)
                    if digits[groupStart...offset].contains(where: { $0 != 0 }) {
                        integerText += groupUnits[groupIndex]
                        pendingZero = false
                    }
                }
            }
            integerText += "元"
        }

        let jiao = fraction[0].wholeNumberValue ?? 0
        let fen = fraction[1].wholeNumberValue ?? 0
        var fractionText = ""
        if jiao == 0 && fen == 0 {
            fractionText = integerText.isEmpty ? "" : "整"
        } else {
            if jiao > 0 {
                fractionText += String(names[jiao]) + "角"
            } else if !integerText.isEmpty {
                fractionText += "零"
            }
            if fen > 0 {
                fractionText += String(names[fen]) + "分"
            }
        }
        if integerText.isEmpty && fractionText.isEmpty {
            return "零元整"
        }
        return (negative ? "负" : "") + integerText + fractionText
    }
}

// MARK: - 颜色

struct ColorValue: Equatable {
    /// 0...255
    var red: Double
    var green: Double
    var blue: Double
    /// 0...1
    var alpha: Double = 1

    /// 支持 #RGB、#RGBA、#RRGGBB、#RRGGBBAA、rgb()/rgba()、hsl()/hsla()。
    /// 三四位的写法里至少要有一个字母（#123 更可能是 issue 编号）。
    static func parse(_ text: String) -> ColorValue? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmed.count <= 64 else { return nil }
        if trimmed.hasPrefix("#") {
            return parseHex(String(trimmed.dropFirst()))
        }
        if trimmed.hasPrefix("rgb") {
            return parseRGB(trimmed)
        }
        if trimmed.hasPrefix("hsl") {
            return parseHSL(trimmed)
        }
        return nil
    }

    private static func parseHex(_ digits: String) -> ColorValue? {
        guard [3, 4, 6, 8].contains(digits.count), digits.allSatisfy(\.isHexDigit) else { return nil }
        if digits.count <= 4, !digits.contains(where: \.isLetter) {
            return nil
        }
        let expanded = digits.count <= 4 ? String(digits.flatMap { [$0, $0] }) : digits
        guard let value = UInt64(expanded, radix: 16) else { return nil }
        if expanded.count == 6 {
            return ColorValue(red: Double((value >> 16) & 0xFF), green: Double((value >> 8) & 0xFF), blue: Double(value & 0xFF))
        }
        return ColorValue(red: Double((value >> 24) & 0xFF), green: Double((value >> 16) & 0xFF),
                          blue: Double((value >> 8) & 0xFF), alpha: Double(value & 0xFF) / 255)
    }

    /// rgb(1, 2, 3)、rgba(1,2,3,0.5)、rgb(1 2 3 / 50%) 括号里的各项
    private static func arguments(_ text: String, function: String) -> [String]? {
        guard let open = text.firstIndex(of: "("), text.hasSuffix(")") else { return nil }
        let name = text[..<open].trimmingCharacters(in: .whitespaces)
        guard name == function || name == function + "a" else { return nil }
        let inner = text[text.index(after: open)..<text.index(before: text.endIndex)]
        let parts = inner.split(whereSeparator: { $0 == "," || $0 == " " || $0 == "/" }).map(String.init)
        return parts.count == 3 || parts.count == 4 ? parts : nil
    }

    private static func number(_ text: String, percentScale: Double) -> Double? {
        if text.hasSuffix("%") {
            return Double(String(text.dropLast())).map { $0 / 100 * percentScale }
        }
        return Double(text)
    }

    private static func alphaArgument(_ parts: [String]) -> Double? {
        guard parts.count == 4 else { return 1 }
        guard let alpha = number(parts[3], percentScale: 1), (0...1).contains(alpha) else { return nil }
        return alpha
    }

    private static func parseRGB(_ text: String) -> ColorValue? {
        guard let parts = arguments(text, function: "rgb") else { return nil }
        var channels: [Double] = []
        for part in parts.prefix(3) {
            guard let value = number(part, percentScale: 255), (0...255).contains(value) else { return nil }
            channels.append(value)
        }
        guard let alpha = alphaArgument(parts) else { return nil }
        return ColorValue(red: channels[0], green: channels[1], blue: channels[2], alpha: alpha)
    }

    private static func parseHSL(_ text: String) -> ColorValue? {
        guard let parts = arguments(text, function: "hsl"),
              let hue = Double(parts[0].replacingOccurrences(of: "deg", with: "")),
              parts[1].hasSuffix("%"), parts[2].hasSuffix("%"),
              let saturation = number(parts[1], percentScale: 1),
              let lightness = number(parts[2], percentScale: 1),
              (0...1).contains(saturation), (0...1).contains(lightness),
              let alpha = alphaArgument(parts) else { return nil }
        let rgb = hslToRGB(hue: hue, saturation: saturation, lightness: lightness)
        return ColorValue(red: rgb.red * 255, green: rgb.green * 255, blue: rgb.blue * 255, alpha: alpha)
    }

    static func hslToRGB(hue: Double, saturation: Double, lightness: Double) -> (red: Double, green: Double, blue: Double) {
        let h = (hue.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 360
        guard saturation > 0 else { return (lightness, lightness, lightness) }
        let q = lightness < 0.5 ? lightness * (1 + saturation) : lightness + saturation - lightness * saturation
        let p = 2 * lightness - q
        func channel(_ value: Double) -> Double {
            var t = value
            if t < 0 { t += 1 }
            if t > 1 { t -= 1 }
            if t < 1.0 / 6 { return p + (q - p) * 6 * t }
            if t < 1.0 / 2 { return q }
            if t < 2.0 / 3 { return p + (q - p) * (2.0 / 3 - t) * 6 }
            return p
        }
        return (channel(h + 1.0 / 3), channel(h), channel(h - 1.0 / 3))
    }

    /// 色相 0..<360，饱和度、亮度 0...1
    var hsl: (hue: Double, saturation: Double, lightness: Double) {
        let r = red / 255
        let g = green / 255
        let b = blue / 255
        let maxValue = max(r, g, b)
        let minValue = min(r, g, b)
        let lightness = (maxValue + minValue) / 2
        guard maxValue > minValue else { return (0, 0, lightness) }
        let delta = maxValue - minValue
        let saturation = lightness > 0.5 ? delta / (2 - maxValue - minValue) : delta / (maxValue + minValue)
        var hue: Double
        if maxValue == r {
            hue = (g - b) / delta + (g < b ? 6 : 0)
        } else if maxValue == g {
            hue = (b - r) / delta + 2
        } else {
            hue = (r - g) / delta + 4
        }
        return (hue * 60, saturation, lightness)
    }

    private static func byte(_ value: Double) -> Int {
        Int(min(max(value, 0), 255).rounded())
    }

    private static func decimal(_ value: Double, digits: Int = 3) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = digits
        formatter.minimumIntegerDigits = 1
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    var hexString: String {
        let base = String(format: "#%02lX%02lX%02lX", Self.byte(red), Self.byte(green), Self.byte(blue))
        guard alpha < 1 else { return base }
        return base + String(format: "%02lX", Self.byte(alpha * 255))
    }

    var rgbString: String {
        let channels = "\(Self.byte(red)), \(Self.byte(green)), \(Self.byte(blue))"
        return alpha < 1 ? "rgba(\(channels), \(Self.decimal(alpha, digits: 2)))" : "rgb(\(channels))"
    }

    var hslString: String {
        let value = hsl
        let body = "\(Int(value.hue.rounded()) % 360), \(Int((value.saturation * 100).rounded()))%, \(Int((value.lightness * 100).rounded()))%"
        return alpha < 1 ? "hsla(\(body), \(Self.decimal(alpha, digits: 2)))" : "hsl(\(body))"
    }

    var swiftUIString: String {
        let channels = "red: \(Self.decimal(red / 255)), green: \(Self.decimal(green / 255)), blue: \(Self.decimal(blue / 255))"
        return alpha < 1 ? "Color(\(channels), opacity: \(Self.decimal(alpha, digits: 2)))" : "Color(\(channels))"
    }

    var rows: [ResultCard.Row] {
        [
            ResultCard.Row(label: "HEX", value: hexString),
            ResultCard.Row(label: "RGB", value: rgbString),
            ResultCard.Row(label: "HSL", value: hslString),
            ResultCard.Row(label: "SwiftUI", value: swiftUIString),
        ]
    }
}

// MARK: - 日期时间

enum DateParser {
    private static let formats = [
        "yyyy-MM-dd HH:mm:ss.SSS", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd",
        "yyyy/MM/dd HH:mm:ss", "yyyy/MM/dd HH:mm", "yyyy/MM/dd",
        "yyyy.MM.dd HH:mm:ss", "yyyy.MM.dd HH:mm", "yyyy.MM.dd",
        "yyyy年M月d日 HH:mm:ss", "yyyy年M月d日 HH:mm", "yyyy年M月d日H时m分s秒", "yyyy年M月d日H时m分", "yyyy年M月d日",
    ]

    private static let allowedCharacters = CharacterSet(charactersIn: "0123456789-/.: 年月日时分秒TZ+")

    /// 识别常见的日期时间写法；没写时区的按 timeZone 理解。
    static func parse(_ text: String, timeZone: TimeZone = .current) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (8...40).contains(trimmed.count), trimmed.first?.isNumber == true,
              trimmed.unicodeScalars.allSatisfy({ allowedCharacters.contains($0) }),
              trimmed.contains(where: { "-/.年".contains($0) }) else { return nil }
        if trimmed.contains("T"), trimmed.hasSuffix("Z") || trimmed.contains("+") || trimmed.dropFirst(10).contains("-") {
            let iso = ISO8601DateFormatter()
            for options: ISO8601DateFormatter.Options in [[.withInternetDateTime, .withFractionalSeconds], [.withInternetDateTime]] {
                iso.formatOptions = options
                if let date = iso.date(from: trimmed), isPlausible(date) {
                    return date
                }
            }
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.isLenient = false
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed), isPlausible(date) {
                return date
            }
        }
        return nil
    }

    private static func isPlausible(_ date: Date) -> Bool {
        // 1900-01-01 ~ 2200-01-01
        (-2_208_988_800...7_258_118_400).contains(date.timeIntervalSince1970)
    }

    static func rows(for date: Date, timeZone: TimeZone = .current, now: Date = Date()) -> [ResultCard.Row] {
        let seconds = Int64(date.timeIntervalSince1970.rounded(.down))
        let milliseconds = Int64((date.timeIntervalSince1970 * 1000).rounded())
        let relative = RelativeDateTimeFormatter()
        relative.locale = Locale(identifier: "zh_CN")
        relative.unitsStyle = .full
        let weekday = DateFormatter()
        weekday.locale = Locale(identifier: "zh_CN")
        weekday.timeZone = timeZone
        weekday.dateFormat = "EEEE"
        return [
            ResultCard.Row(label: "本地时间", value: TimestampConverter.localString(date, timeZone: timeZone)),
            ResultCard.Row(label: "UTC", value: TimestampConverter.isoString(date)),
            ResultCard.Row(label: "Unix 秒", value: String(seconds)),
            ResultCard.Row(label: "Unix 毫秒", value: String(milliseconds)),
            ResultCard.Row(label: "距今", value: relative.localizedString(for: date, relativeTo: now)),
            ResultCard.Row(label: "星期", value: weekday.string(from: date)),
        ]
    }
}

// MARK: - 随机生成

enum RandomGenerator {
    /// 去掉了容易看错的字符（l、I、O、0、1）
    private static let lowercase = Array("abcdefghijkmnopqrstuvwxyz")
    private static let uppercase = Array("ABCDEFGHJKLMNPQRSTUVWXYZ")
    private static let digits = Array("23456789")
    private static let symbols = Array("!@#$%^&*-_=+?")

    /// 每类字符至少一个。
    static func password(length: Int = 16, includeSymbols: Bool = true) -> String {
        var generator = SystemRandomNumberGenerator()
        var pools = [lowercase, uppercase, digits]
        if includeSymbols {
            pools.append(symbols)
        }
        let all = pools.flatMap { $0 }
        var characters: [Character] = []
        for pool in pools {
            if let character = pool.randomElement(using: &generator) {
                characters.append(character)
            }
        }
        while characters.count < max(length, pools.count) {
            if let character = all.randomElement(using: &generator) {
                characters.append(character)
            }
        }
        characters.shuffle(using: &generator)
        return String(characters)
    }

    static func rows() -> [ResultCard.Row] {
        let uuid = UUID().uuidString
        return [
            ResultCard.Row(label: "UUID", value: uuid),
            ResultCard.Row(label: "UUID 小写", value: uuid.lowercased()),
            ResultCard.Row(label: "密码", value: password()),
            ResultCard.Row(label: "密码 无符号", value: password(length: 20, includeSymbols: false)),
            ResultCard.Row(label: "6 位数字", value: String(format: "%06ld", Int.random(in: 0..<1_000_000))),
        ]
    }
}

// MARK: - 搜索

enum SearchText {
    /// 搜索用的关键字：原文小写、拼音全拼、拼音首字母（「翻译」可以用 fanyi、fy 搜到）。
    static func keys(for text: String) -> [String] {
        let lower = text.lowercased()
        guard let latin = text.applyingTransform(.toLatin, reverse: false)?
            .applyingTransform(.stripDiacritics, reverse: false)?
            .lowercased(), latin != lower else { return [lower] }
        let syllables = latin.split(separator: " ")
        return [lower, syllables.joined(), String(syllables.compactMap(\.first))]
    }

    static func matches(_ query: String, keys: [String]) -> Bool {
        let needle = query.lowercased().filter { !$0.isWhitespace }
        guard !needle.isEmpty else { return true }
        return keys.contains { $0.filter { !$0.isWhitespace }.contains(needle) }
    }
}
