import Foundation

/// 保留键顺序的结构化数据：JSON 和 YAML 互相转换时用。
indirect enum DataValue: Equatable {
    case object([Pair])
    case array([DataValue])
    case string(String)
    /// 数字按原来的写法保存，不丢精度
    case number(String)
    case bool(Bool)
    case null

    struct Pair: Equatable {
        var key: String
        var value: DataValue
    }
}

// MARK: - JSON

/// 按原来的顺序读写 JSON（系统的 JSONSerialization 会打乱键的顺序）。
enum OrderedJSON {
    static func parse(_ text: String) -> DataValue? {
        var parser = Parser(scalars: Array(text.unicodeScalars))
        return parser.document()
    }

    /// 两个空格缩进的 JSON
    static func format(_ value: DataValue) -> String {
        var output = ""
        write(value, indent: 0, into: &output)
        return output
    }

    /// 压成一行的 JSON
    static func compact(_ value: DataValue) -> String {
        switch value {
        case .object(let pairs):
            return "{" + pairs.map { quoted($0.key) + ":" + compact($0.value) }.joined(separator: ",") + "}"
        case .array(let items):
            return "[" + items.map { compact($0) }.joined(separator: ",") + "]"
        case .string(let text):
            return quoted(text)
        case .number(let number):
            return number
        case .bool(let flag):
            return flag ? "true" : "false"
        case .null:
            return "null"
        }
    }

    private static func write(_ value: DataValue, indent: Int, into output: inout String) {
        let pad = String(repeating: " ", count: indent + 2)
        switch value {
        case .object(let pairs):
            guard !pairs.isEmpty else {
                output += "{}"
                return
            }
            output += "{\n"
            for (index, pair) in pairs.enumerated() {
                output += pad + quoted(pair.key) + ": "
                write(pair.value, indent: indent + 2, into: &output)
                output += index < pairs.count - 1 ? ",\n" : "\n"
            }
            output += String(repeating: " ", count: indent) + "}"
        case .array(let items):
            guard !items.isEmpty else {
                output += "[]"
                return
            }
            output += "[\n"
            for (index, item) in items.enumerated() {
                output += pad
                write(item, indent: indent + 2, into: &output)
                output += index < items.count - 1 ? ",\n" : "\n"
            }
            output += String(repeating: " ", count: indent) + "]"
        case .string(let text):
            output += quoted(text)
        case .number(let number):
            output += number
        case .bool(let flag):
            output += flag ? "true" : "false"
        case .null:
            output += "null"
        }
    }

    /// JSON 的字符串写法（也是合法的 YAML 双引号字符串）
    static func quoted(_ text: String) -> String {
        var output = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": output += "\\\""
            case "\\": output += "\\\\"
            case "\n": output += "\\n"
            case "\r": output += "\\r"
            case "\t": output += "\\t"
            default:
                if scalar.value < 0x20 || scalar.value == 0x7F {
                    output += String(format: "\\u%04x", scalar.value)
                } else {
                    output.unicodeScalars.append(scalar)
                }
            }
        }
        return output + "\""
    }

    private struct Parser {
        let scalars: [Unicode.Scalar]
        var index = 0
        var depth = 0

        mutating func document() -> DataValue? {
            guard let root = value() else { return nil }
            skipWhitespace()
            return index == scalars.count ? root : nil
        }

        mutating func skipWhitespace() {
            // 空格、换行、回车、制表符
            while index < scalars.count, [0x20, 0x0A, 0x0D, 0x09].contains(scalars[index].value) {
                index += 1
            }
        }

        mutating func value() -> DataValue? {
            skipWhitespace()
            guard index < scalars.count, depth < 512 else { return nil }
            switch scalars[index] {
            case "{":
                return object()
            case "[":
                return array()
            case "\"":
                return string().map { DataValue.string($0) }
            case "t":
                return literal("true", .bool(true))
            case "f":
                return literal("false", .bool(false))
            case "n":
                return literal("null", .null)
            default:
                return number()
            }
        }

        mutating func object() -> DataValue? {
            index += 1
            depth += 1
            defer { depth -= 1 }
            var pairs: [DataValue.Pair] = []
            skipWhitespace()
            if index < scalars.count, scalars[index] == "}" {
                index += 1
                return .object(pairs)
            }
            while true {
                skipWhitespace()
                guard index < scalars.count, scalars[index] == "\"", let key = string() else { return nil }
                skipWhitespace()
                guard index < scalars.count, scalars[index] == ":" else { return nil }
                index += 1
                guard let item = value() else { return nil }
                pairs.append(DataValue.Pair(key: key, value: item))
                skipWhitespace()
                guard index < scalars.count else { return nil }
                if scalars[index] == "," {
                    index += 1
                } else if scalars[index] == "}" {
                    index += 1
                    return .object(pairs)
                } else {
                    return nil
                }
            }
        }

        mutating func array() -> DataValue? {
            index += 1
            depth += 1
            defer { depth -= 1 }
            var items: [DataValue] = []
            skipWhitespace()
            if index < scalars.count, scalars[index] == "]" {
                index += 1
                return .array(items)
            }
            while true {
                guard let item = value() else { return nil }
                items.append(item)
                skipWhitespace()
                guard index < scalars.count else { return nil }
                if scalars[index] == "," {
                    index += 1
                } else if scalars[index] == "]" {
                    index += 1
                    return .array(items)
                } else {
                    return nil
                }
            }
        }

        mutating func literal(_ word: String, _ result: DataValue) -> DataValue? {
            let expected = Array(word.unicodeScalars)
            guard index + expected.count <= scalars.count, Array(scalars[index..<(index + expected.count)]) == expected else {
                return nil
            }
            index += expected.count
            return result
        }

        mutating func number() -> DataValue? {
            let start = index
            if index < scalars.count, scalars[index] == "-" {
                index += 1
            }
            guard digits() > 0 else { return nil }
            if index < scalars.count, scalars[index] == "." {
                index += 1
                guard digits() > 0 else { return nil }
            }
            if index < scalars.count, scalars[index] == "e" || scalars[index] == "E" {
                index += 1
                if index < scalars.count, scalars[index] == "+" || scalars[index] == "-" {
                    index += 1
                }
                guard digits() > 0 else { return nil }
            }
            return .number(String(String.UnicodeScalarView(scalars[start..<index])))
        }

        mutating func digits() -> Int {
            let start = index
            while index < scalars.count, (0x30...0x39).contains(scalars[index].value) {
                index += 1
            }
            return index - start
        }

        mutating func string() -> String? {
            index += 1
            var result = String.UnicodeScalarView()
            while index < scalars.count {
                let scalar = scalars[index]
                index += 1
                switch scalar {
                case "\"":
                    return String(result)
                case "\\":
                    guard index < scalars.count else { return nil }
                    let escape = scalars[index]
                    index += 1
                    switch escape {
                    case "\"": result.append("\"")
                    case "\\": result.append("\\")
                    case "/": result.append("/")
                    case "b": result.append("\u{08}")
                    case "f": result.append("\u{0C}")
                    case "n": result.append("\n")
                    case "r": result.append("\r")
                    case "t": result.append("\t")
                    case "u":
                        guard let code = hex4() else { return nil }
                        if (0xD800...0xDBFF).contains(code) {
                            // 代理对：后面必须紧跟着低位的 \uDC00–\uDFFF
                            guard index + 1 < scalars.count, scalars[index] == "\\", scalars[index + 1] == "u" else { return nil }
                            index += 2
                            guard let low = hex4(), (0xDC00...0xDFFF).contains(low),
                                  let combined = Unicode.Scalar(0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00)) else { return nil }
                            result.append(combined)
                        } else {
                            guard let single = Unicode.Scalar(code) else { return nil }
                            result.append(single)
                        }
                    default:
                        return nil
                    }
                default:
                    guard scalar.value >= 0x20 else { return nil }
                    result.append(scalar)
                }
            }
            return nil
        }

        mutating func hex4() -> UInt32? {
            guard index + 4 <= scalars.count else { return nil }
            var value: UInt32 = 0
            for scalar in scalars[index..<(index + 4)] {
                guard let digit = Int(String(scalar), radix: 16) else { return nil }
                value = value * 16 + UInt32(digit)
            }
            index += 4
            return value
        }
    }
}

// MARK: - YAML

/// YAML 和 JSON 互相转换。读 YAML 支持常用的写法：缩进的键值和列表、「- key: value」、引号字符串、
/// 多行文字（| 和 >）、[a, b] 和 {a: 1}、注释；不支持锚点和引用（& *）、标签（!）和一个文件里的多个文档。
enum YAMLConverter {
    struct Failure: Error, Equatable {
        let message: String
        /// 出错的行（从 1 开始）
        var line: Int?

        var description: String {
            line.map { "第 \($0) 行：\(message)" } ?? message
        }
    }

    // MARK: 写 YAML

    static func yaml(from value: DataValue) -> String {
        var lines: [String] = []
        switch value {
        case .object(let pairs) where !pairs.isEmpty:
            mapping(pairs, indent: 0, into: &lines)
        case .array(let items) where !items.isEmpty:
            sequence(items, indent: 0, into: &lines)
        default:
            lines.append(scalar(value))
        }
        return lines.joined(separator: "\n")
    }

    private static func mapping(_ pairs: [DataValue.Pair], indent: Int, into lines: inout [String]) {
        let pad = String(repeating: " ", count: indent)
        for pair in pairs {
            let key = plainOrQuoted(pair.key)
            switch pair.value {
            case .object(let children) where !children.isEmpty:
                lines.append("\(pad)\(key):")
                mapping(children, indent: indent + 2, into: &lines)
            case .array(let items) where !items.isEmpty:
                lines.append("\(pad)\(key):")
                sequence(items, indent: indent + 2, into: &lines)
            case .string(let text) where isBlockCandidate(text):
                lines.append("\(pad)\(key): \(blockHeader(text))")
                lines += blockLines(text, indent: indent + 2)
            default:
                lines.append("\(pad)\(key): \(scalar(pair.value))")
            }
        }
    }

    private static func sequence(_ items: [DataValue], indent: Int, into lines: inout [String]) {
        let pad = String(repeating: " ", count: indent)
        for item in items {
            var nested: [String] = []
            switch item {
            case .object(let children) where !children.isEmpty:
                // 第一项跟在「- 」后面，其余的和它对齐
                mapping(children, indent: indent + 2, into: &nested)
            case .array(let children) where !children.isEmpty:
                sequence(children, indent: indent + 2, into: &nested)
            case .string(let text) where isBlockCandidate(text):
                lines.append("\(pad)- \(blockHeader(text))")
                lines += blockLines(text, indent: indent + 2)
                continue
            default:
                lines.append("\(pad)- \(scalar(item))")
                continue
            }
            nested[0] = pad + "- " + String(nested[0].dropFirst(indent + 2))
            lines += nested
        }
    }

    static func scalar(_ value: DataValue) -> String {
        switch value {
        case .string(let text): return plainOrQuoted(text)
        case .number(let number): return number
        case .bool(let flag): return flag ? "true" : "false"
        case .null: return "null"
        case .object: return "{}"
        case .array: return "[]"
        }
    }

    static func plainOrQuoted(_ text: String) -> String {
        canBePlain(text) ? text : OrderedJSON.quoted(text)
    }

    /// 不加引号也不会被读错的文字
    static func canBePlain(_ text: String) -> Bool {
        guard let first = text.first, let last = text.last, !first.isWhitespace, !last.isWhitespace else { return false }
        if "-?:,[]{}#&*!|>'\"%@`".contains(first) { return false }
        if text.contains(": ") || text.contains(" #") || last == ":" { return false }
        if text.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }) { return false }
        // 老的 YAML 1.1 会把 yes、no、on、off 读成布尔值
        if ["yes", "no", "on", "off", "y", "n"].contains(text.lowercased()) { return false }
        // 老的 YAML 1.1 还会把 2026-09-29、1:20、1_000 这类读成日期或数字
        if first.isASCII, first.isNumber, text.allSatisfy({ $0.isASCII && ($0.isNumber || "_:.-+eE".contains($0)) }) { return false }
        return resolvePlain(text) == .string(text)
    }

    /// 多行文字用「|」块写，每行原样
    private static func isBlockCandidate(_ text: String) -> Bool {
        guard text.contains("\n"), !text.contains("\r"), let first = text.first, first != " ", first != "\n" else { return false }
        if text.unicodeScalars.contains(where: { ($0.value < 0x20 && $0 != "\n" && $0 != "\t") || $0.value == 0x7F }) {
            return false
        }
        // 只有空格的行在块里读回来会变成空行
        return !text.components(separatedBy: "\n").contains { !$0.isEmpty && $0.allSatisfy { $0 == " " } }
    }

    private static func trailingNewlines(_ text: String) -> Int {
        text.reversed().prefix { $0 == "\n" }.count
    }

    private static func blockHeader(_ text: String) -> String {
        switch trailingNewlines(text) {
        case 0: return "|-"
        case 1: return "|"
        default: return "|+"
        }
    }

    private static func blockLines(_ text: String, indent: Int) -> [String] {
        let pad = String(repeating: " ", count: indent)
        let trailing = trailingNewlines(text)
        var body = text
        body.removeLast(trailing)
        var lines = body.components(separatedBy: "\n").map { $0.isEmpty ? "" : pad + $0 }
        if trailing > 1 {
            lines += Array(repeating: "", count: trailing - 1)
        }
        return lines
    }

    // MARK: 读 YAML

    static func parse(_ text: String) throws -> DataValue {
        var lines: [Line] = []
        for (offset, raw) in text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n").enumerated() {
            let indent = raw.prefix { $0 == " " }.count
            let content = String(raw.dropFirst(indent))
            if content.hasPrefix("\t"), !Line.stripComment(content).trimmingCharacters(in: .whitespaces).isEmpty {
                throw Failure(message: "缩进里不能有制表符", line: offset + 1)
            }
            lines.append(Line(number: offset + 1, indent: indent, content: content))
        }
        var parser = Parser(lines: lines)
        return try parser.document()
    }

    /// 看起来是 YAML：至少两行，读出来是键值或者列表
    static func looksLikeYAML(_ text: String) -> Bool {
        let meaningful = text.components(separatedBy: "\n").filter {
            let trimmed = $0.trimmingCharacters(in: .whitespaces)
            return !trimmed.isEmpty && !trimmed.hasPrefix("#")
        }
        guard meaningful.count >= 2, !JSONFormatter.isJSON(text.trimmingCharacters(in: .whitespacesAndNewlines)),
              let value = try? parse(text) else { return false }
        switch value {
        case .object(let pairs): return !pairs.isEmpty
        case .array(let items): return !items.isEmpty
        default: return false
        }
    }

    /// 普通（不带引号）的值是什么类型：null、布尔、整数（也认 0x、0o）、小数，其余是文字
    static func resolvePlain(_ text: String) -> DataValue {
        switch text {
        case "", "~", "null", "Null", "NULL":
            return .null
        case "true", "True", "TRUE":
            return .bool(true)
        case "false", "False", "FALSE":
            return .bool(false)
        default:
            break
        }
        if text.range(of: #"^[-+]?[0-9]+$"#, options: .regularExpression) != nil {
            if let value = Int64(text) {
                return .number(String(value))
            }
            // 超出 64 位：去掉正号和开头多余的 0，按原样保留
            let negative = text.hasPrefix("-")
            let digits = text.drop { $0 == "-" || $0 == "+" }.drop { $0 == "0" }
            return .number((negative ? "-" : "") + (digits.isEmpty ? "0" : String(digits)))
        }
        if text.range(of: #"^0x[0-9a-fA-F]+$"#, options: .regularExpression) != nil, let value = Int64(text.dropFirst(2), radix: 16) {
            return .number(String(value))
        }
        if text.range(of: #"^0o[0-7]+$"#, options: .regularExpression) != nil, let value = Int64(text.dropFirst(2), radix: 8) {
            return .number(String(value))
        }
        if text.range(of: #"^[-+]?(\.[0-9]+|[0-9]+(\.[0-9]*)?)([eE][-+]?[0-9]+)?$"#, options: .regularExpression) != nil,
           let value = Double(text), value.isFinite {
            return .number(jsonNumber(text))
        }
        return .string(text)
    }

    /// 1. → 1.0、.5 → 0.5、+1.5 → 1.5（JSON 的写法）
    private static func jsonNumber(_ text: String) -> String {
        var number = text.hasPrefix("+") ? String(text.dropFirst()) : text
        let negative = number.hasPrefix("-")
        if negative {
            number.removeFirst()
        }
        if number.hasPrefix(".") {
            number = "0" + number
        }
        if let dot = number.firstIndex(of: ".") {
            let after = number.index(after: dot)
            if after == number.endIndex || !number[after].isNumber {
                number.insert("0", at: after)
            }
        }
        return (negative ? "-" : "") + number
    }

    struct Line {
        var number: Int
        var indent: Int
        /// 去掉缩进后的原文（多行文字块要用原文）
        var content: String

        /// 当作结构读的时候：去掉注释和结尾的空格
        var structural: String {
            Self.stripComment(content).trimmingCharacters(in: .whitespaces)
        }

        var isBlank: Bool { structural.isEmpty }

        /// 去掉「#」开头的注释（引号里的 # 和紧跟在字后面的 # 不算）
        static func stripComment(_ text: String) -> String {
            var single = false
            var double = false
            var previous: Character = " "
            var escaped = false
            for (offset, character) in text.enumerated() {
                if double {
                    if escaped {
                        escaped = false
                    } else if character == "\\" {
                        escaped = true
                    } else if character == "\"" {
                        double = false
                    }
                } else if single {
                    if character == "'" {
                        single = false
                    }
                } else if character == "#", previous.isWhitespace {
                    return String(text.prefix(offset))
                } else if character == "\"", previous.isWhitespace || "[{,:".contains(previous) {
                    double = true
                } else if character == "'", previous.isWhitespace || "[{,:".contains(previous) {
                    single = true
                }
                previous = character
            }
            return text
        }
    }

    /// 「键: 值」：返回键和冒号后面的部分；不是键值时返回 nil
    static func splitKey(_ content: String) -> (key: String, rest: String)? {
        let characters = Array(content)
        guard let first = characters.first, !"-[{#&*!|>%@`".contains(first) || (first == "-" && characters.count > 1 && characters[1] != " ") else {
            return nil
        }
        var index = 0
        var key: String
        if first == "\"" || first == "'" {
            // 带引号的键
            guard let (text, end) = quotedScalar(characters, from: 0) else { return nil }
            key = text
            index = end
            while index < characters.count, characters[index] == " " {
                index += 1
            }
            guard index < characters.count, characters[index] == ":" else { return nil }
        } else {
            // 普通的键：到第一个后面跟着空格（或者在行尾）的冒号为止
            while index < characters.count {
                if characters[index] == ":", index + 1 == characters.count || characters[index + 1] == " " {
                    break
                }
                index += 1
            }
            guard index < characters.count else { return nil }
            key = String(characters[0..<index]).trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { return nil }
        }
        let rest = String(characters[(index + 1)...]).trimmingCharacters(in: .whitespaces)
        return (key, rest)
    }

    /// 从 start 开始读一个带引号的字符串，返回内容和引号后面的位置
    static func quotedScalar(_ characters: [Character], from start: Int) -> (String, Int)? {
        guard start < characters.count else { return nil }
        let quote = characters[start]
        var index = start + 1
        var result = ""
        while index < characters.count {
            let character = characters[index]
            if quote == "'" {
                if character == "'" {
                    // '' 是一个单引号
                    if index + 1 < characters.count, characters[index + 1] == "'" {
                        result.append("'")
                        index += 2
                        continue
                    }
                    return (result, index + 1)
                }
                result.append(character)
                index += 1
            } else {
                if character == "\"" {
                    return (result, index + 1)
                }
                if character == "\\", index + 1 < characters.count {
                    let escape = characters[index + 1]
                    index += 2
                    switch escape {
                    case "n": result.append("\n")
                    case "t": result.append("\t")
                    case "r": result.append("\r")
                    case "0": result.append("\0")
                    case "\\": result.append("\\")
                    case "\"": result.append("\"")
                    case "/": result.append("/")
                    case " ": result.append(" ")
                    case "u", "x", "U":
                        let length = escape == "x" ? 2 : (escape == "u" ? 4 : 8)
                        guard index + length <= characters.count,
                              let code = UInt32(String(characters[index..<(index + length)]), radix: 16),
                              let scalar = Unicode.Scalar(code) else { return nil }
                        result.unicodeScalars.append(scalar)
                        index += length
                    default:
                        result.append(escape)
                    }
                    continue
                }
                result.append(character)
                index += 1
            }
        }
        return nil
    }

    private struct BlockHeader {
        var folded: Bool
        /// strip（-）去掉结尾的换行，keep（+）全部保留，clip 只留一个
        var chomping: Character?
        var indentation: Int?

        init?(_ text: String) {
            guard let first = text.first, first == "|" || first == ">", text.count <= 3 else { return nil }
            folded = first == ">"
            for character in text.dropFirst() {
                if character == "-" || character == "+" {
                    chomping = character
                } else if let digit = character.wholeNumberValue, digit > 0 {
                    indentation = digit
                } else {
                    return nil
                }
            }
        }
    }

    private struct Parser {
        var lines: [Line]
        var index = 0

        mutating func document() throws -> DataValue {
            skipBlank()
            if index < lines.count, lines[index].indent == 0, lines[index].structural == "---" {
                index += 1
            }
            let value = try block(minIndent: 0)
            skipBlank()
            if index < lines.count {
                let line = lines[index]
                if line.structural == "..." {
                    return value
                }
                if line.structural == "---" || line.structural.hasPrefix("--- ") {
                    throw Failure(message: "只支持一个文档（第二个 --- 之后的内容读不了）", line: line.number)
                }
                throw Failure(message: "缩进不对", line: line.number)
            }
            return value
        }

        mutating func skipBlank() {
            while index < lines.count, lines[index].isBlank {
                index += 1
            }
        }

        static func isSequenceItem(_ content: String) -> Bool {
            content == "-" || content.hasPrefix("- ")
        }

        mutating func block(minIndent: Int) throws -> DataValue {
            skipBlank()
            guard index < lines.count, lines[index].indent >= minIndent else { return .null }
            let line = lines[index]
            let content = line.structural
            if Self.isSequenceItem(content) {
                return try sequence(indent: line.indent)
            }
            if YAMLConverter.splitKey(content) != nil {
                return try mapping(indent: line.indent)
            }
            index += 1
            return try inline(content, line: line.number, indent: line.indent - 1)
        }

        mutating func mapping(indent: Int) throws -> DataValue {
            var pairs: [DataValue.Pair] = []
            var seen = Set<String>()
            while true {
                skipBlank()
                guard index < lines.count else { break }
                let line = lines[index]
                let content = line.structural
                if line.indent < indent || content == "..." || (line.indent == 0 && content == "---") {
                    break
                }
                guard line.indent == indent else { throw Failure(message: "缩进不对", line: line.number) }
                guard let (key, rest) = YAMLConverter.splitKey(content) else {
                    if Self.isSequenceItem(content) {
                        throw Failure(message: "列表项要比上面的键多缩进，或者放在键的下一行", line: line.number)
                    }
                    throw Failure(message: "这里应该是「键: 值」", line: line.number)
                }
                guard seen.insert(key).inserted else { throw Failure(message: "键「\(key)」重复了", line: line.number) }
                index += 1
                let value: DataValue
                if rest.isEmpty {
                    // 值在下面：缩进更深的一块，或者同样缩进的「- 」列表
                    skipBlank()
                    if index < lines.count, lines[index].indent > indent {
                        value = try block(minIndent: indent + 1)
                    } else if index < lines.count, lines[index].indent == indent, Self.isSequenceItem(lines[index].structural) {
                        value = try sequence(indent: indent)
                    } else {
                        value = .null
                    }
                } else if let header = BlockHeader(rest) {
                    value = .string(blockScalar(header, parentIndent: indent))
                } else {
                    value = try inline(rest, line: line.number, indent: indent)
                }
                pairs.append(DataValue.Pair(key: key, value: value))
            }
            return .object(pairs)
        }

        mutating func sequence(indent: Int) throws -> DataValue {
            var items: [DataValue] = []
            while true {
                skipBlank()
                guard index < lines.count else { break }
                let line = lines[index]
                let content = line.structural
                if line.indent < indent || content == "..." || (line.indent == 0 && content == "---") {
                    break
                }
                guard line.indent == indent else { throw Failure(message: "缩进不对", line: line.number) }
                // 同一层的「键: 值」：列表到这里结束（键下面同样缩进的列表）
                guard Self.isSequenceItem(content) else { break }
                let afterDash = content.dropFirst()
                let spaces = afterDash.prefix { $0 == " " }.count
                let rest = String(afterDash.dropFirst(spaces))
                index += 1
                if rest.isEmpty {
                    skipBlank()
                    if index < lines.count, lines[index].indent > indent {
                        items.append(try block(minIndent: indent + 1))
                    } else {
                        items.append(.null)
                    }
                } else if Self.isSequenceItem(rest) || YAMLConverter.splitKey(rest) != nil {
                    // 「- key: value」「- - a」：把这一行剩下的部分当成缩进更深的一行
                    index -= 1
                    lines[index] = Line(number: line.number, indent: indent + 1 + spaces, content: rest)
                    items.append(try block(minIndent: indent + 1 + spaces))
                } else if let header = BlockHeader(rest) {
                    items.append(.string(blockScalar(header, parentIndent: indent)))
                } else {
                    items.append(try inline(rest, line: line.number, indent: indent))
                }
            }
            return .array(items)
        }

        /// 跟在「键:」「- 」后面的值：引号字符串、[ ]、{ }、普通的值（下面缩进更深的行接在后面）
        mutating func inline(_ text: String, line: Int, indent: Int) throws -> DataValue {
            guard let first = text.first else { return .null }
            switch first {
            case "&", "*":
                throw Failure(message: "不支持锚点和引用（& 和 *）", line: line)
            case "!":
                throw Failure(message: "不支持标签（!）", line: line)
            case "[", "{":
                // 可以跨行：一直读到括号配对
                var flow = text
                while !FlowParser.isBalanced(flow), index < lines.count {
                    flow += " " + lines[index].structural
                    index += 1
                }
                var parser = FlowParser(characters: Array(flow))
                guard let value = parser.document() else { throw Failure(message: "[ ] 或 { } 的写法不对", line: line) }
                return value
            case "\"", "'":
                var joined = text
                var characters = Array(joined)
                // 引号可以跨行：换行变成空格
                while YAMLConverter.quotedScalar(characters, from: 0) == nil, index < lines.count {
                    joined += " " + lines[index].content.trimmingCharacters(in: .whitespaces)
                    index += 1
                    characters = Array(joined)
                }
                guard let (value, end) = YAMLConverter.quotedScalar(characters, from: 0) else {
                    throw Failure(message: "引号没有配对", line: line)
                }
                let trailing = Line.stripComment(String(characters[end...])).trimmingCharacters(in: .whitespaces)
                guard trailing.isEmpty else { throw Failure(message: "引号后面多了「\(trailing)」", line: line) }
                return .string(value)
            default:
                // 普通的值可以跨行，下面缩进更深的行接在后面（换行变成空格）
                var words = [text]
                while index < lines.count, lines[index].indent > indent, !lines[index].isBlank {
                    let next = lines[index].structural
                    if Self.isSequenceItem(next) || YAMLConverter.splitKey(next) != nil { break }
                    words.append(next)
                    index += 1
                }
                return words.count == 1 ? YAMLConverter.resolvePlain(text) : .string(words.joined(separator: " "))
            }
        }

        /// | 和 > 开头的多行文字：下面缩进更深的行原样取出来
        mutating func blockScalar(_ header: BlockHeader, parentIndent: Int) -> String {
            var blockIndent = header.indentation.map { parentIndent + $0 }
            var collected: [String] = []
            while index < lines.count {
                let line = lines[index]
                let blank = line.content.trimmingCharacters(in: .whitespaces).isEmpty
                if blank {
                    collected.append("")
                    index += 1
                    continue
                }
                if blockIndent == nil {
                    guard line.indent > parentIndent else { break }
                    blockIndent = line.indent
                }
                guard let indent = blockIndent, line.indent >= indent else { break }
                collected.append(String(repeating: " ", count: line.indent - indent) + line.content)
                index += 1
            }
            // 结尾的空行按 chomping 处理，先拿出来
            var trailingBlank = 0
            while let last = collected.last, last.isEmpty {
                collected.removeLast()
                trailingBlank += 1
            }
            // 读过头的空行留给后面的结构（它们只是空行，跳过也没关系）
            var text: String
            if header.folded {
                text = ""
                var previousWasText = false
                for line in collected {
                    if line.isEmpty {
                        text += "\n"
                        previousWasText = false
                    } else if line.hasPrefix(" ") {
                        // 缩进更深的行原样保留
                        text += (previousWasText ? "\n" : "") + line
                        previousWasText = true
                    } else {
                        text += (previousWasText ? " " : "") + line
                        previousWasText = true
                    }
                }
            } else {
                text = collected.joined(separator: "\n")
            }
            guard !collected.isEmpty else { return "" }
            switch header.chomping {
            case "-"?:
                return text
            case "+"?:
                return text + String(repeating: "\n", count: trailingBlank + 1)
            default:
                return text + "\n"
            }
        }
    }

    /// 一行里的 [a, b] 和 {a: 1}
    private struct FlowParser {
        let characters: [Character]
        var index = 0
        var depth = 0

        static func isBalanced(_ text: String) -> Bool {
            var depth = 0
            var quote: Character?
            var escaped = false
            for character in text {
                if let open = quote {
                    if escaped {
                        escaped = false
                    } else if open == "\"", character == "\\" {
                        escaped = true
                    } else if character == open {
                        quote = nil
                    }
                } else if character == "\"" || character == "'" {
                    quote = character
                } else if character == "[" || character == "{" {
                    depth += 1
                } else if character == "]" || character == "}" {
                    depth -= 1
                }
            }
            return depth <= 0 && quote == nil
        }

        mutating func document() -> DataValue? {
            guard let root = value(inMapping: false) else { return nil }
            skipSpaces()
            let rest = YAMLConverter.Line.stripComment(String(characters[index...])).trimmingCharacters(in: .whitespaces)
            return rest.isEmpty ? root : nil
        }

        mutating func skipSpaces() {
            while index < characters.count, characters[index] == " " || characters[index] == "\t" {
                index += 1
            }
        }

        mutating func value(inMapping: Bool) -> DataValue? {
            skipSpaces()
            guard index < characters.count, depth < 256 else { return nil }
            switch characters[index] {
            case "[":
                index += 1
                depth += 1
                defer { depth -= 1 }
                var items: [DataValue] = []
                while true {
                    skipSpaces()
                    guard index < characters.count else { return nil }
                    if characters[index] == "]" {
                        index += 1
                        return .array(items)
                    }
                    guard let item = value(inMapping: false) else { return nil }
                    items.append(item)
                    skipSpaces()
                    guard index < characters.count else { return nil }
                    if characters[index] == "," {
                        index += 1
                    } else if characters[index] != "]" {
                        return nil
                    }
                }
            case "{":
                index += 1
                depth += 1
                defer { depth -= 1 }
                var pairs: [DataValue.Pair] = []
                while true {
                    skipSpaces()
                    guard index < characters.count else { return nil }
                    if characters[index] == "}" {
                        index += 1
                        return .object(pairs)
                    }
                    guard case .some(let keyValue) = value(inMapping: true) else { return nil }
                    let key: String
                    switch keyValue {
                    case .string(let text): key = text
                    case .number(let text): key = text
                    case .bool(let flag): key = flag ? "true" : "false"
                    case .null: key = "null"
                    default: return nil
                    }
                    skipSpaces()
                    var item: DataValue = .null
                    if index < characters.count, characters[index] == ":" {
                        index += 1
                        guard let parsed = value(inMapping: true) else { return nil }
                        item = parsed
                    }
                    pairs.append(DataValue.Pair(key: key, value: item))
                    skipSpaces()
                    guard index < characters.count else { return nil }
                    if characters[index] == "," {
                        index += 1
                    } else if characters[index] != "}" {
                        return nil
                    }
                }
            case "\"", "'":
                guard let (text, end) = YAMLConverter.quotedScalar(characters, from: index) else { return nil }
                index = end
                return .string(text)
            default:
                // 普通的值：到逗号、右括号为止；在 { } 里还要在「: 」处停下
                let start = index
                while index < characters.count {
                    let character = characters[index]
                    if character == "," || character == "]" || character == "}" {
                        break
                    }
                    if inMapping, character == ":", index + 1 == characters.count || " ,]}".contains(characters[index + 1]) {
                        break
                    }
                    index += 1
                }
                let text = String(characters[start..<index]).trimmingCharacters(in: .whitespaces)
                return YAMLConverter.resolvePlain(text)
            }
        }
    }
}
