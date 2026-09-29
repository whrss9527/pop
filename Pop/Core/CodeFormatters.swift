import Foundation

// MARK: - SQL

/// SQL 格式化：关键字大写，每个子句换行；SELECT、SET、VALUES 有好几项时一项一行，WHERE 里的 AND、OR 换行缩进，
/// 子查询缩进一层。也可以压成一行。字符串、带引号的名字和注释原样保留。
enum SQLFormatter {
    enum Kind: Equatable {
        case word
        case number
        case string
        case identifier
        case comment
        case blockComment
        case op
        case punct
    }

    struct Token: Equatable {
        var kind: Kind
        var text: String
    }

    static let keywords: Set<String> = [
        "SELECT", "DISTINCT", "FROM", "WHERE", "AND", "OR", "NOT", "IN", "IS", "NULL", "LIKE", "ILIKE", "BETWEEN", "EXISTS",
        "AS", "ON", "USING", "JOIN", "INNER", "LEFT", "RIGHT", "FULL", "OUTER", "CROSS", "NATURAL", "GROUP", "BY", "HAVING",
        "ORDER", "ASC", "DESC", "LIMIT", "OFFSET", "UNION", "ALL", "INTERSECT", "EXCEPT", "INSERT", "INTO", "VALUES", "UPDATE",
        "SET", "DELETE", "RETURNING", "WITH", "RECURSIVE", "CASE", "WHEN", "THEN", "ELSE", "END", "CREATE", "TABLE", "VIEW",
        "INDEX", "UNIQUE", "PRIMARY", "KEY", "FOREIGN", "REFERENCES", "DEFAULT", "ALTER", "ADD", "DROP", "COLUMN", "IF",
        "TRUE", "FALSE", "REPLACE", "TEMPORARY", "CONSTRAINT", "CHECK", "CASCADE", "CONFLICT", "DO", "NOTHING", "OVER",
        "PARTITION", "WINDOW", "FETCH", "NEXT", "ROWS", "ONLY", "FIRST", "LAST", "NULLS", "INTERVAL",
    ]

    /// 另起一行的子句；list 表示后面有好几项时一项一行
    static let clauses: [(words: [String], list: Bool)] = [
        (["SELECT", "DISTINCT"], true), (["SELECT"], true), (["FROM"], false), (["WHERE"], false),
        (["GROUP", "BY"], false), (["HAVING"], false), (["ORDER", "BY"], false), (["LIMIT"], false), (["OFFSET"], false),
        (["UNION", "ALL"], false), (["UNION"], false), (["INTERSECT"], false), (["EXCEPT"], false),
        (["INSERT", "INTO"], false), (["VALUES"], true), (["UPDATE"], false), (["SET"], true), (["DELETE", "FROM"], false),
        (["RETURNING"], false), (["WITH", "RECURSIVE"], false), (["WITH"], false),
        (["LEFT", "OUTER", "JOIN"], false), (["RIGHT", "OUTER", "JOIN"], false), (["FULL", "OUTER", "JOIN"], false),
        (["LEFT", "JOIN"], false), (["RIGHT", "JOIN"], false), (["FULL", "JOIN"], false), (["INNER", "JOIN"], false),
        (["CROSS", "JOIN"], false), (["NATURAL", "JOIN"], false), (["JOIN"], false),
    ]

    // MARK: 认出 SQL

    /// 看起来是一条 SQL 语句。英文句子也可能以 select、update 开头，所以还要有 SQL 的写法（符号、大写的关键字）
    static func looksLikeSQL(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 10, trimmed.count <= 500_000, let last = trimmed.last, !".。?？!！".contains(last) else { return false }
        let head = String(trimmed.prefix(4000))
        let name = #"[\w."`\[\]]+"#
        func matches(_ pattern: String) -> Bool {
            head.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }
        // 这两种写法本身就只会是 SQL
        if matches(#"^update\s+"# + name + #"\s+set\s+"# + name + #"\s*="#)
            || matches(#"^with\s+(recursive\s+)?[\w"`]+(\s*\([^)]*\))?\s+as\s*\("#) {
            return true
        }
        let statements = [
            #"^select\s+[\s\S]+?\s+from\s+"# + name,
            #"^insert\s+into\s+"# + name,
            #"^delete\s+from\s+"# + name,
            #"^create\s+(or\s+replace\s+)?(temporary\s+|temp\s+)?(table|view|index|unique\s+index|function|procedure|database|schema|trigger)\b"#,
            #"^alter\s+(table|view|index|database|schema)\b"#,
            #"^drop\s+(table|view|index|database|schema|function)\b"#,
        ]
        guard statements.contains(where: matches) else { return false }
        let symbols = head.contains { "*=<>(,;'`\"".contains($0) }
        let uppercase = ["SELECT ", "INSERT ", "DELETE ", "CREATE ", "ALTER ", "DROP "].contains { head.hasPrefix($0) }
        return symbols || uppercase
    }

    // MARK: 拆成词

    static func tokenize(_ sql: String) -> [Token] {
        let characters = Array(sql)
        var tokens: [Token] = []
        var index = 0
        func starts(_ prefix: String, at position: Int) -> Bool {
            let expected = Array(prefix)
            return position + expected.count <= characters.count
                && Array(characters[position..<(position + expected.count)]) == expected
        }
        func isDigit(_ position: Int) -> Bool {
            position < characters.count && characters[position].isASCII && characters[position].isNumber
        }
        func isNamePart(_ character: Character) -> Bool {
            character.isLetter || character.isNumber || character == "_" || character == "$"
        }
        while index < characters.count {
            let character = characters[index]
            if character.isWhitespace {
                index += 1
                continue
            }
            if starts("--", at: index) {
                var end = index
                while end < characters.count, !characters[end].isNewline {
                    end += 1
                }
                tokens.append(Token(kind: .comment, text: String(characters[index..<end]).trimmingCharacters(in: .whitespaces)))
                index = end
                continue
            }
            if starts("/*", at: index) {
                var end = index + 2
                while end < characters.count, !starts("*/", at: end) {
                    end += 1
                }
                end = min(end + 2, characters.count)
                tokens.append(Token(kind: .blockComment, text: String(characters[index..<end])))
                index = end
                continue
            }
            if character == "'" || character == "\"" || character == "`" {
                // 引号里两个引号表示一个引号
                var end = index + 1
                while end < characters.count {
                    if characters[end] == character {
                        if end + 1 < characters.count, characters[end + 1] == character {
                            end += 2
                            continue
                        }
                        break
                    }
                    end += 1
                }
                end = min(end + 1, characters.count)
                tokens.append(Token(kind: character == "'" ? .string : .identifier, text: String(characters[index..<end])))
                index = end
                continue
            }
            if isDigit(index) {
                var end = index
                while isDigit(end) {
                    end += 1
                }
                if end < characters.count, characters[end] == ".", isDigit(end + 1) {
                    end += 1
                    while isDigit(end) {
                        end += 1
                    }
                }
                if end < characters.count, characters[end] == "e" || characters[end] == "E" {
                    let signed = end + 1 < characters.count && (characters[end + 1] == "+" || characters[end + 1] == "-")
                    if isDigit(end + (signed ? 2 : 1)) {
                        end += signed ? 2 : 1
                        while isDigit(end) {
                            end += 1
                        }
                    }
                }
                tokens.append(Token(kind: .number, text: String(characters[index..<end])))
                index = end
                continue
            }
            let variable = (character == "@" || character == "$") && index + 1 < characters.count && isNamePart(characters[index + 1])
            if character.isLetter || character == "_" || variable {
                var end = index + 1
                while end < characters.count, isNamePart(characters[end]) {
                    end += 1
                }
                tokens.append(Token(kind: .word, text: String(characters[index..<end])))
                index = end
                continue
            }
            if let op = ["->>", "<>", "<=", ">=", "!=", "||", "::", "->"].first(where: { starts($0, at: index) }) {
                tokens.append(Token(kind: .op, text: op))
                index += op.count
                continue
            }
            tokens.append(Token(kind: "(),;.".contains(character) ? .punct : .op, text: String(character)))
            index += 1
        }
        return tokens
    }

    // MARK: 排版

    private static func isKeyword(_ token: Token) -> Bool {
        token.kind == .word && keywords.contains(token.text.uppercased())
    }

    private static func clause(in tokens: [Token], at index: Int) -> (words: [String], list: Bool)? {
        clauses.first { candidate in
            guard index + candidate.words.count <= tokens.count else { return false }
            for (offset, word) in candidate.words.enumerated() {
                let token = tokens[index + offset]
                if token.kind != .word || token.text.uppercased() != word {
                    return false
                }
            }
            return true
        }
    }

    /// 这个子句在同一层里有没有逗号（有的话一项一行）
    private static func listHasComma(_ tokens: [Token], from start: Int) -> Bool {
        var depth = 0
        var index = start
        while index < tokens.count {
            let token = tokens[index]
            if token.kind == .punct {
                switch token.text {
                case "(":
                    depth += 1
                case ")":
                    depth -= 1
                    if depth < 0 { return false }
                case ";" where depth == 0:
                    return false
                case "," where depth == 0:
                    return true
                default:
                    break
                }
            } else if token.kind == .word, depth == 0, clause(in: tokens, at: index) != nil {
                return false
            }
            index += 1
        }
        return false
    }

    private struct Output {
        var text = ""

        mutating func newline(_ indent: Int) {
            while text.hasSuffix(" ") {
                text.removeLast()
            }
            guard !text.isEmpty else { return }
            if !text.hasSuffix("\n") {
                text += "\n"
            }
            text += String(repeating: " ", count: indent)
        }

        mutating func write(_ piece: String, space: Bool) {
            if space, let last = text.last, last != " ", last != "\n", last != "(" {
                text += " "
            }
            text += piece
        }
    }

    /// 格式化；compact 时压成一行（行注释换成 /* */）
    static func format(_ sql: String, compact: Bool = false) -> String {
        let tokens = tokenize(sql)
        var output = Output()
        var level = 0
        // 每层括号是不是子查询
        var parens: [Bool] = []
        // 进子查询之前的子句是不是一项一行
        var saved: [Bool] = []
        var inList = false
        var between = false
        var previous: Token?
        var sign = false
        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            let inlineDepth = parens.reversed().prefix { !$0 }.count
            if token.kind == .word, let found = clause(in: tokens, at: index) {
                let isList = found.list && listHasComma(tokens, from: index + found.words.count)
                let text = found.words.joined(separator: " ")
                if compact {
                    output.write(text, space: true)
                } else {
                    output.newline(level * 2)
                    output.write(text, space: false)
                    if isList {
                        output.newline(level * 2 + 2)
                    }
                }
                inList = isList
                previous = Token(kind: .word, text: found.words[found.words.count - 1])
                index += found.words.count
                sign = false
                continue
            }
            let shown = isKeyword(token) ? token.text.uppercased() : token.text
            if token.kind == .word, shown == "BETWEEN" {
                between = true
            }
            if token.kind == .word, shown == "AND" || shown == "OR", inlineDepth == 0, !compact {
                if shown == "AND", between {
                    // BETWEEN a AND b 的 AND 不换行
                    between = false
                } else {
                    output.newline(level * 2 + 2)
                    output.write(shown, space: false)
                    previous = token
                    index += 1
                    sign = false
                    continue
                }
            }
            if token.kind == .punct {
                switch token.text {
                case "(":
                    let next = index + 1 < tokens.count ? tokens[index + 1] : nil
                    let subquery = next.map { $0.kind == .word && ["SELECT", "WITH"].contains($0.text.uppercased()) } ?? false
                    // 函数调用的括号紧跟着名字；INTO t (a, b)、TABLE t (...) 的表名后面空一格
                    let afterTable = index >= 2 && tokens[index - 2].kind == .word && ["INTO", "TABLE"].contains(tokens[index - 2].text.uppercased())
                    let call = previous.map { ($0.kind == .word || $0.kind == .identifier) && !isKeyword($0) } ?? false
                    let glued = previous.map { ["(", ".", "::"].contains($0.text) } ?? false
                    output.write("(", space: !(call && !afterTable) && !glued && !sign)
                    parens.append(subquery)
                    if subquery {
                        saved.append(inList)
                        level += 1
                    }
                case ")":
                    let subquery = parens.popLast() ?? false
                    if subquery {
                        level = max(level - 1, 0)
                        inList = saved.popLast() ?? false
                        if !compact {
                            output.newline(level * 2)
                        }
                    }
                    output.write(")", space: false)
                case ",":
                    output.write(",", space: false)
                    if inList, inlineDepth == 0, !compact {
                        output.newline(level * 2 + 2)
                    }
                case ";":
                    output.write(";", space: false)
                    if !compact {
                        output.text += "\n"
                    }
                    level = 0
                    parens = []
                    saved = []
                    inList = false
                default:
                    output.write(token.text, space: false)
                }
                previous = token
                index += 1
                sign = false
                continue
            }
            if token.kind == .comment {
                if compact {
                    output.write("/* " + token.text.dropFirst(2).trimmingCharacters(in: .whitespaces) + " */", space: true)
                } else {
                    output.write(token.text, space: true)
                    output.newline(level * 2 + (inList ? 2 : 0))
                }
                previous = token
                index += 1
                sign = false
                continue
            }
            let glued = token.text == "::" || previous.map { ["(", ".", "::"].contains($0.text) } ?? false
            let isSign = token.kind == .op && (token.text == "+" || token.text == "-")
                && (previous.map { $0.kind == .op || ["(", ","].contains($0.text) || isKeyword($0) } ?? true)
            output.write(shown, space: !glued && !sign)
            sign = isSign
            previous = token
            index += 1
        }
        return output.text.components(separatedBy: "\n")
            .map { $0.replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression) }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - XML

/// XML（包括 SVG、plist、XHTML）的格式化和压缩。
enum XMLFormatter {
    /// 以 < 开头、> 结尾、有成对的标签，并且能按 XML 读出来
    static func isXML(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("<"), trimmed.hasSuffix(">"), trimmed.count <= 2_000_000,
              trimmed.contains("</") || trimmed.contains("/>") else { return false }
        return document(trimmed) != nil
    }

    /// 每层缩进一级
    static func prettyPrinted(_ text: String) -> String? {
        document(text)?.xmlString(options: [.nodePrettyPrint, .nodeCompactEmptyElement])
    }

    /// 去掉标签之间的空白，压成一行
    static func minified(_ text: String) -> String? {
        document(text)?.xmlString(options: [.nodeCompactEmptyElement])
    }

    private static func document(_ text: String) -> XMLDocument? {
        guard let document = try? XMLDocument(xmlString: text.trimmingCharacters(in: .whitespacesAndNewlines), options: []) else {
            return nil
        }
        if let root = document.rootElement() {
            removeIndentation(root)
        }
        return document
    }

    /// 元素之间只有空白的文字节点（原来的缩进和换行）去掉，重新排版时不会多出空行
    private static func removeIndentation(_ element: XMLElement) {
        let children = element.children ?? []
        let hasElements = children.contains { $0.kind == .element }
        for child in children.reversed() {
            if hasElements, child.kind == .text,
               (child.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                element.removeChild(at: child.index)
            } else if let nested = child as? XMLElement {
                removeIndentation(nested)
            }
        }
    }
}
