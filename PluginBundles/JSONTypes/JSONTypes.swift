import Foundation
@testable import Pop

/// 根据一段 JSON 示例生成类型定义：TypeScript、Swift（Codable）、Go、Kotlin（kotlinx.serialization）。
/// 同一个位置上见过的值合起来推断：数组里的对象取所有字段，有的对象里没有的字段是可选的，出现过 null 的可以为空。
/// 纯逻辑，方便测试。
enum JSONTypes {
    enum Language: String, CaseIterable {
        case typeScript = "TypeScript"
        case swift = "Swift"
        case go = "Go"
        case kotlin = "Kotlin"
    }

    static let maxLength = 200_000

    struct Output {
        var typeCount: Int
        var code: [(language: Language, text: String)]
    }

    /// 不是 JSON、或者里面没有对象时返回 nil
    static func generate(_ json: String) -> Output? {
        guard json.utf8.count <= maxLength, let value = JSONReader.parse(json) else { return nil }
        let root = Shape()
        root.merge(value)
        let model = Model(root: root)
        guard !model.definitions.isEmpty else { return nil }
        return Output(typeCount: model.definitions.count,
                      code: Language.allCases.map { ($0, model.render($0)) })
    }

    // MARK: - 合并示例

    /// 同一个位置上见过的所有值合起来的样子
    final class Shape {
        var string = false
        var integer = false
        var double = false
        var bool = false
        var null = false
        /// 整数超出 32 位
        var long = false
        /// 见过数组时：数组元素合起来的样子
        var array: Shape?
        var object: ObjectShape?

        func merge(_ value: JSONReader.Value) {
            switch value {
            case .string:
                string = true
            case .integer(let number):
                integer = true
                if let number {
                    if number < Int64(Int32.min) || number > Int64(Int32.max) { long = true }
                } else {
                    // 超出 64 位的整数只能当小数
                    double = true
                }
            case .double:
                double = true
            case .bool:
                bool = true
            case .null:
                null = true
            case .array(let elements):
                let element = array ?? Shape()
                array = element
                for item in elements { element.merge(item) }
            case .object(let members):
                let shape = object ?? ObjectShape()
                object = shape
                shape.merge(members)
            }
        }
    }

    final class ObjectShape {
        /// 按第一次出现的顺序
        var keys: [String] = []
        var fields: [String: Shape] = [:]
        /// 每个字段在几个对象里出现过
        var presence: [String: Int] = [:]
        /// 合并了几个对象
        var count = 0

        func merge(_ members: [JSONReader.Member]) {
            count += 1
            var seenHere = Set<String>()
            for member in members {
                let field: Shape
                if let existing = fields[member.key] {
                    field = existing
                } else {
                    field = Shape()
                    fields[member.key] = field
                    keys.append(member.key)
                }
                if seenHere.insert(member.key).inserted {
                    presence[member.key, default: 0] += 1
                }
                field.merge(member.value)
            }
        }
    }

    // MARK: - 类型

    indirect enum TypeRef: Equatable {
        case string, int, long, double, bool
        case array(TypeRef)
        case named(String)
        /// 示例里只有 null 或者空数组，看不出类型
        case unknown
        /// 同一个字段有时是字符串、有时是数字……
        case mixed([TypeRef])
    }

    struct Field {
        var key: String
        var type: TypeRef
        /// 有的对象里没有这个字段
        var optional: Bool
        /// 出现过 null
        var nullable: Bool
    }

    struct Definition {
        var name: String
        var fields: [Field]
    }

    /// 和各语言自带的类型重名的，加上 Info
    private static let reservedNames: Set<String> = [
        "String", "Int", "Int64", "Double", "Float", "Bool", "Boolean", "Data", "Date", "Error", "Type", "Array",
        "Dictionary", "Set", "List", "Map", "Object", "Any", "Result", "Optional", "URL", "UUID", "Decimal", "Character",
        "Number", "Record", "Promise", "Long", "Unit", "Nothing", "Pair", "Protocol", "Self", "Codable", "JsonElement",
    ]

    struct Model {
        private(set) var definitions: [Definition] = []
        private var usedNames = JSONTypes.reservedNames

        init(root: Shape) {
            if root.object != nil {
                _ = resolve(root, name: "Root")
                return
            }
            // 根是数组时，数组里的对象叫 Item
            var element = root.array
            while let shape = element, shape.object == nil, shape.array != nil {
                element = shape.array
            }
            if let element {
                _ = resolve(element, name: "Item")
            }
        }

        private mutating func resolve(_ shape: Shape, name: String) -> TypeRef {
            var types: [TypeRef] = []
            if shape.string { types.append(.string) }
            if shape.double {
                types.append(.double)
            } else if shape.integer {
                types.append(shape.long ? .long : .int)
            }
            if shape.bool { types.append(.bool) }
            if let element = shape.array { types.append(.array(resolve(element, name: JSONTypes.singular(name)))) }
            if let object = shape.object { types.append(.named(define(object, name: name))) }
            switch types.count {
            case 0: return .unknown
            case 1: return types[0]
            default: return .mixed(types)
            }
        }

        private mutating func define(_ object: ObjectShape, name: String) -> String {
            let base = usedNames.contains(name) && JSONTypes.reservedNames.contains(name) ? name + "Info" : name
            var unique = base
            var suffix = 2
            while usedNames.contains(unique) {
                unique = base + String(suffix)
                suffix += 1
            }
            usedNames.insert(unique)
            // 先占好位置，外层的类型排在里层前面
            let index = definitions.count
            definitions.append(Definition(name: unique, fields: []))
            var fields: [Field] = []
            for key in object.keys {
                guard let shape = object.fields[key] else { continue }
                let fieldType = resolve(shape, name: JSONTypes.typeName(key))
                fields.append(Field(key: key, type: fieldType, optional: (object.presence[key] ?? 0) < object.count,
                                    nullable: shape.null))
            }
            definitions[index].fields = fields
            return unique
        }

        func render(_ language: Language) -> String {
            switch language {
            case .typeScript: return JSONTypes.typeScript(definitions)
            case .swift: return JSONTypes.swift(definitions)
            case .go: return JSONTypes.go(definitions)
            case .kotlin: return JSONTypes.kotlin(definitions)
            }
        }
    }

    // MARK: - 命名

    /// 按非字母数字的字符和大小写变化拆词：first_name、firstName、FirstName、URLPath
    static func words(_ key: String) -> [String] {
        var words: [String] = []
        var current = ""
        let characters = Array(key)
        for (index, character) in characters.enumerated() {
            guard character.isLetter || character.isNumber else {
                if !current.isEmpty {
                    words.append(current)
                    current = ""
                }
                continue
            }
            if !current.isEmpty, character.isUppercase {
                let previous = characters[index - 1]
                let next = index + 1 < characters.count ? characters[index + 1] : nil
                // aB → a|B；URLPath 的 LP → URL|Path
                if previous.isLowercase || previous.isNumber || (previous.isUppercase && next?.isLowercase == true) {
                    words.append(current)
                    current = ""
                }
            }
            current.append(character)
        }
        if !current.isEmpty { words.append(current) }
        return words
    }

    private static func capitalized(_ word: String) -> String {
        word.prefix(1).uppercased() + word.dropFirst()
    }

    /// 字段名 → 类型名：user_info → UserInfo
    static func typeName(_ key: String) -> String {
        let name = words(key).map(capitalized).joined()
        guard let first = name.first else { return "Value" }
        return first.isNumber ? "T" + name : name
    }

    /// 数组字段的元素类型名：items → Item，categories → Category，data → DataItem
    static func singular(_ name: String) -> String {
        let lower = name.lowercased()
        if lower.hasSuffix("ies"), name.count > 3 { return String(name.dropLast(3)) + "y" }
        if ["sses", "shes", "ches", "xes"].contains(where: lower.hasSuffix) { return String(name.dropLast(2)) }
        if lower.hasSuffix("s"), !lower.hasSuffix("ss"), !lower.hasSuffix("us"), name.count > 1 { return String(name.dropLast()) }
        return name + "Item"
    }

    /// 字段名 → 驼峰属性名：first_name → firstName，URLPath → urlPath
    static func camelCase(_ key: String) -> String {
        let parts = words(key)
        guard let first = parts.first else { return "value" }
        let name = first.lowercased() + parts.dropFirst().map(capitalized).joined()
        return name.first?.isNumber == true ? "_" + name : name
    }

    private static let goInitialisms: Set<String> = [
        "acl", "api", "ascii", "cpu", "css", "dns", "eof", "guid", "html", "http", "https", "id", "ip", "json", "qps",
        "ram", "rpc", "sla", "smtp", "sql", "ssh", "tcp", "tls", "ttl", "udp", "ui", "gid", "uid", "uuid", "uri", "url",
        "utf8", "vm", "xml", "xmpp", "xsrf", "xss",
    ]

    /// Go 的字段名要大写开头才能导出：user_id → UserID
    static func goName(_ key: String) -> String {
        let name = words(key).map { goInitialisms.contains($0.lowercased()) ? $0.uppercased() : capitalized($0) }.joined()
        guard let first = name.first else { return "Value" }
        return first.isUppercase ? name : "X" + name
    }

    private static let swiftKeywords: Set<String> = [
        "associatedtype", "class", "deinit", "enum", "extension", "fileprivate", "func", "import", "init", "inout",
        "internal", "let", "open", "operator", "private", "protocol", "public", "rethrows", "static", "struct",
        "subscript", "typealias", "var", "break", "case", "continue", "default", "defer", "do", "else", "fallthrough",
        "for", "guard", "if", "in", "repeat", "return", "switch", "where", "while", "as", "catch", "false", "is", "nil",
        "super", "self", "throw", "throws", "true", "try", "async", "await",
    ]

    private static let kotlinKeywords: Set<String> = [
        "as", "break", "class", "continue", "do", "else", "false", "for", "fun", "if", "in", "interface", "is", "null",
        "object", "package", "return", "super", "this", "throw", "true", "try", "typealias", "typeof", "val", "var",
        "when", "while",
    ]

    private static func isIdentifier(_ key: String) -> Bool {
        key.range(of: #"^[A-Za-z_$][A-Za-z0-9_$]*$"#, options: .regularExpression) != nil
    }

    // MARK: - 各语言

    private static func typeScript(_ definitions: [Definition]) -> String {
        func name(_ type: TypeRef) -> String {
            switch type {
            case .string: return "string"
            case .int, .long, .double: return "number"
            case .bool: return "boolean"
            case .named(let name): return name
            case .unknown: return "unknown"
            case .array(let element):
                let inner = name(element)
                return (inner.contains(" ") ? "(\(inner))" : inner) + "[]"
            case .mixed(let types):
                var names: [String] = []
                for type in types where !names.contains(name(type)) { names.append(name(type)) }
                return names.joined(separator: " | ")
            }
        }
        return definitions.map { definition -> String in
            guard !definition.fields.isEmpty else { return "export interface \(definition.name) {}" }
            let lines = definition.fields.map { field -> String in
                let key = isIdentifier(field.key) ? field.key : LineTools.jsonString(field.key)
                var type = name(field.type)
                if field.nullable, field.type != .unknown { type += " | null" }
                return "  \(key)\(field.optional ? "?" : ""): \(type);"
            }
            return (["export interface \(definition.name) {"] + lines + ["}"]).joined(separator: "\n")
        }.joined(separator: "\n\n")
    }

    private static func swift(_ definitions: [Definition]) -> String {
        /// 类型名，外加一句说明（看不出类型、类型不固定时）
        func name(_ type: TypeRef) -> (String, String?) {
            switch type {
            case .string: return ("String", nil)
            case .int, .long: return ("Int", nil)
            case .double: return ("Double", nil)
            case .bool: return ("Bool", nil)
            case .named(let name): return (name, nil)
            case .unknown: return ("String", String(localized: "示例里只有 null 或空数组，看不出类型"))
            case .mixed: return ("String", String(localized: "示例里的类型不固定"))
            case .array(let element):
                let (inner, note) = name(element)
                return ("[\(inner)]", note)
            }
        }
        return definitions.map { definition -> String in
            guard !definition.fields.isEmpty else { return "struct \(definition.name): Codable {}" }
            var lines = ["struct \(definition.name): Codable {"]
            var keys: [String] = []
            var renamed = false
            for field in definition.fields {
                var property = camelCase(field.key)
                if swiftKeywords.contains(property) { property = "`\(property)`" }
                let (typeName, note) = name(field.type)
                let optional = field.optional || field.nullable || field.type == .unknown
                var line = "    let \(property): \(typeName)\(optional ? "?" : "")"
                if let note { line += " // \(note)" }
                lines.append(line)
                if property.trimmingCharacters(in: CharacterSet(charactersIn: "`")) == field.key {
                    keys.append("        case \(property)")
                } else {
                    renamed = true
                    keys.append("        case \(property) = \(LineTools.jsonString(field.key))")
                }
            }
            if renamed {
                lines += ["", "    enum CodingKeys: String, CodingKey {"] + keys + ["    }"]
            }
            lines.append("}")
            return lines.joined(separator: "\n")
        }.joined(separator: "\n\n")
    }

    private static func go(_ definitions: [Definition]) -> String {
        func name(_ type: TypeRef) -> String {
            switch type {
            case .string: return "string"
            case .int: return "int"
            case .long: return "int64"
            case .double: return "float64"
            case .bool: return "bool"
            case .named(let name): return name
            case .unknown, .mixed: return "any"
            case .array(let element): return "[]" + name(element)
            }
        }
        return definitions.map { definition -> String in
            guard !definition.fields.isEmpty else { return "type \(definition.name) struct{}" }
            var used = Set<String>()
            let rows = definition.fields.map { field -> (String, String, String) in
                var fieldName = goName(field.key)
                var suffix = 2
                while !used.insert(fieldName).inserted {
                    fieldName = goName(field.key) + String(suffix)
                    suffix += 1
                }
                var type = name(field.type)
                let canBeNil: Bool
                switch field.type {
                case .array, .unknown, .mixed: canBeNil = true
                default: canBeNil = false
                }
                if (field.optional || field.nullable), !canBeNil { type = "*" + type }
                let tag = "`json:\"\(field.key.replacingOccurrences(of: "\"", with: "\\\""))\(field.optional ? ",omitempty" : "")\"`"
                return (fieldName, type, tag)
            }
            // 和 gofmt 一样按列对齐
            let nameWidth = rows.map(\.0.count).max() ?? 0
            let typeWidth = rows.map(\.1.count).max() ?? 0
            let lines = rows.map { row -> String in
                let (name, type, tag) = row
                return "\t" + name.padding(toLength: nameWidth, withPad: " ", startingAt: 0) + " "
                    + type.padding(toLength: typeWidth, withPad: " ", startingAt: 0) + " " + tag
            }
            return (["type \(definition.name) struct {"] + lines + ["}"]).joined(separator: "\n")
        }.joined(separator: "\n\n")
    }

    private static func kotlin(_ definitions: [Definition]) -> String {
        func name(_ type: TypeRef) -> String {
            switch type {
            case .string: return "String"
            case .int: return "Int"
            case .long: return "Long"
            case .double: return "Double"
            case .bool: return "Boolean"
            case .named(let name): return name
            case .unknown, .mixed: return "JsonElement"
            case .array(let element): return "List<\(name(element))>"
            }
        }
        var usesSerialName = false
        var usesJsonElement = false
        let classes = definitions.map { definition -> String in
            guard !definition.fields.isEmpty else { return "@Serializable\nclass \(definition.name)" }
            var lines = ["@Serializable", "data class \(definition.name)("]
            for field in definition.fields {
                var property = camelCase(field.key)
                if kotlinKeywords.contains(property) { property = "`\(property)`" }
                let typeName = name(field.type)
                if typeName.contains("JsonElement") { usesJsonElement = true }
                let optional = field.optional || field.nullable || field.type == .unknown
                if property.trimmingCharacters(in: CharacterSet(charactersIn: "`")) != field.key {
                    usesSerialName = true
                    lines.append("    @SerialName(\(LineTools.jsonString(field.key)))")
                }
                lines.append("    val \(property): \(typeName)\(optional ? "? = null" : ""),")
            }
            lines.append(")")
            return lines.joined(separator: "\n")
        }
        var imports: [String] = []
        if usesSerialName { imports.append("import kotlinx.serialization.SerialName") }
        imports.append("import kotlinx.serialization.Serializable")
        if usesJsonElement { imports.append("import kotlinx.serialization.json.JsonElement") }
        return imports.joined(separator: "\n") + "\n\n" + classes.joined(separator: "\n\n")
    }
}

/// 保留键顺序的 JSON 解析（系统的 JSONSerialization 不保留键的顺序），只记下推断类型需要的信息
enum JSONReader {
    struct Member {
        var key: String
        var value: Value
    }

    indirect enum Value {
        case object([Member])
        case array([Value])
        case string
        /// 超出 64 位时是 nil
        case integer(Int64?)
        case double
        case bool
        case null
    }

    static func parse(_ text: String) -> Value? {
        var parser = Parser(bytes: Array(text.utf8))
        return parser.document()
    }

    private struct Parser {
        let bytes: [UInt8]
        var index = 0
        var depth = 0

        mutating func document() -> Value? {
            guard let root = value() else { return nil }
            skipWhitespace()
            return index == bytes.count ? root : nil
        }

        private mutating func skipWhitespace() {
            while index < bytes.count, bytes[index] == 0x20 || bytes[index] == 0x09 || bytes[index] == 0x0A || bytes[index] == 0x0D {
                index += 1
            }
        }

        private func peek(_ character: Unicode.Scalar) -> Bool {
            index < bytes.count && bytes[index] == UInt8(character.value)
        }

        private mutating func value() -> Value? {
            skipWhitespace()
            guard index < bytes.count else { return nil }
            switch bytes[index] {
            case UInt8(ascii: "{"): return object()
            case UInt8(ascii: "["): return array()
            case UInt8(ascii: "\""): return string() == nil ? nil : .string
            case UInt8(ascii: "t"): return literal("true") ? .bool : nil
            case UInt8(ascii: "f"): return literal("false") ? .bool : nil
            case UInt8(ascii: "n"): return literal("null") ? .null : nil
            default: return number()
            }
        }

        private mutating func literal(_ word: String) -> Bool {
            let expected = Array(word.utf8)
            guard index + expected.count <= bytes.count, Array(bytes[index..<index + expected.count]) == expected else { return false }
            index += expected.count
            return true
        }

        private mutating func object() -> Value? {
            depth += 1
            defer { depth -= 1 }
            guard depth <= 200 else { return nil }
            index += 1
            var members: [Member] = []
            skipWhitespace()
            if peek("}") {
                index += 1
                return .object(members)
            }
            while true {
                skipWhitespace()
                guard peek("\""), let key = string() else { return nil }
                skipWhitespace()
                guard peek(":") else { return nil }
                index += 1
                guard let member = value() else { return nil }
                members.append(Member(key: key, value: member))
                skipWhitespace()
                if peek(",") {
                    index += 1
                } else if peek("}") {
                    index += 1
                    return .object(members)
                } else {
                    return nil
                }
            }
        }

        private mutating func array() -> Value? {
            depth += 1
            defer { depth -= 1 }
            guard depth <= 200 else { return nil }
            index += 1
            var elements: [Value] = []
            skipWhitespace()
            if peek("]") {
                index += 1
                return .array(elements)
            }
            while true {
                guard let element = value() else { return nil }
                elements.append(element)
                skipWhitespace()
                if peek(",") {
                    index += 1
                } else if peek("]") {
                    index += 1
                    return .array(elements)
                } else {
                    return nil
                }
            }
        }

        /// 当前位置是开头的引号
        private mutating func string() -> String? {
            index += 1
            var buffer: [UInt8] = []
            while index < bytes.count {
                let byte = bytes[index]
                index += 1
                switch byte {
                case UInt8(ascii: "\""):
                    return String(decoding: buffer, as: UTF8.self)
                case UInt8(ascii: "\\"):
                    guard index < bytes.count else { return nil }
                    let escape = bytes[index]
                    index += 1
                    switch escape {
                    case UInt8(ascii: "\""), UInt8(ascii: "\\"), UInt8(ascii: "/"): buffer.append(escape)
                    case UInt8(ascii: "b"): buffer.append(0x08)
                    case UInt8(ascii: "f"): buffer.append(0x0C)
                    case UInt8(ascii: "n"): buffer.append(0x0A)
                    case UInt8(ascii: "r"): buffer.append(0x0D)
                    case UInt8(ascii: "t"): buffer.append(0x09)
                    case UInt8(ascii: "u"):
                        guard var code = hex4() else { return nil }
                        // 代理对：😀
                        if (0xD800...0xDBFF).contains(code), index + 6 <= bytes.count,
                           bytes[index] == UInt8(ascii: "\\"), bytes[index + 1] == UInt8(ascii: "u") {
                            index += 2
                            guard let low = hex4() else { return nil }
                            code = 0x10000 + ((code - 0xD800) << 10) + (low &- 0xDC00)
                        }
                        let scalar = Unicode.Scalar(code) ?? "\u{FFFD}"
                        buffer += Array(String(scalar).utf8)
                    default:
                        return nil
                    }
                case 0x00...0x1F:
                    // 字符串里不能直接出现控制字符
                    return nil
                default:
                    buffer.append(byte)
                }
            }
            return nil
        }

        private mutating func hex4() -> UInt32? {
            guard index + 4 <= bytes.count,
                  let value = UInt32(String(decoding: bytes[index..<index + 4], as: UTF8.self), radix: 16) else { return nil }
            index += 4
            return value
        }

        private mutating func digits() -> Int {
            let start = index
            while index < bytes.count, (0x30...0x39).contains(bytes[index]) { index += 1 }
            return index - start
        }

        private mutating func number() -> Value? {
            let start = index
            if peek("-") { index += 1 }
            let integerStart = index
            let integerDigits = digits()
            // 0 开头的只能是 0 本身
            guard integerDigits > 0, !(bytes[integerStart] == 0x30 && integerDigits > 1) else { return nil }
            var isInteger = true
            if peek(".") {
                isInteger = false
                index += 1
                guard digits() > 0 else { return nil }
            }
            if peek("e") || peek("E") {
                isInteger = false
                index += 1
                if peek("+") || peek("-") { index += 1 }
                guard digits() > 0 else { return nil }
            }
            guard isInteger else { return .double }
            return .integer(Int64(String(decoding: bytes[start..<index], as: UTF8.self)))
        }
    }
}
