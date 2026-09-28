import Foundation

/// 小型算式求值器：支持 + - * / ^、括号、百分号（50% = 0.5）和常见全角符号。
/// 不用 NSExpression，因为它遇到非法输入会抛 Objective-C 异常直接崩溃。
enum Calculator {
    static func evaluate(_ input: String) -> Double? {
        let chars = normalize(input)
        guard !chars.isEmpty, chars.count <= 256 else { return nil }
        var parser = Parser(chars: chars)
        guard let value = parser.parseExpression(), parser.isAtEnd, value.isFinite else { return nil }
        return value
    }

    static func format(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 1e15 {
            return String(Int64(value))
        }
        return String(format: "%.12g", value)
    }

    /// 统一符号、去掉空白和千分位逗号、去掉末尾的等号。
    static func normalize(_ input: String) -> [Character] {
        var result: [Character] = []
        for ch in input {
            switch ch {
            case "×", "＊", "✕": result.append("*")
            case "÷", "／": result.append("/")
            case "＋": result.append("+")
            case "－", "−": result.append("-")
            case "（": result.append("(")
            case "）": result.append(")")
            case "％": result.append("%")
            case "，", ",": continue
            default:
                if ch.isWhitespace { continue }
                result.append(ch)
            }
        }
        while result.last == "=" || result.last == "＝" {
            result.removeLast()
        }
        return result
    }

    // expression := term (('+' | '-') term)*
    // term       := unary (('*' | '/') unary)*
    // unary      := ('+' | '-') unary | power
    // power      := postfix ('^' unary)?
    // postfix    := primary '%'*
    // primary    := number | '(' expression ')'
    private struct Parser {
        let chars: [Character]
        var index = 0
        var depth = 0

        var isAtEnd: Bool { index >= chars.count }

        func peek() -> Character? { index < chars.count ? chars[index] : nil }

        mutating func parseExpression() -> Double? {
            depth += 1
            defer { depth -= 1 }
            guard depth < 64, var value = parseTerm() else { return nil }
            while let op = peek(), op == "+" || op == "-" {
                index += 1
                guard let rhs = parseTerm() else { return nil }
                value = op == "+" ? value + rhs : value - rhs
            }
            return value
        }

        mutating func parseTerm() -> Double? {
            guard var value = parseUnary() else { return nil }
            while let op = peek(), op == "*" || op == "/" {
                index += 1
                guard let rhs = parseUnary() else { return nil }
                if op == "*" {
                    value *= rhs
                } else {
                    guard rhs != 0 else { return nil }
                    value /= rhs
                }
            }
            return value
        }

        mutating func parseUnary() -> Double? {
            if let op = peek(), op == "+" || op == "-" {
                index += 1
                depth += 1
                defer { depth -= 1 }
                guard depth < 64, let value = parseUnary() else { return nil }
                return op == "-" ? -value : value
            }
            return parsePower()
        }

        mutating func parsePower() -> Double? {
            guard let base = parsePostfix() else { return nil }
            if peek() == "^" {
                index += 1
                guard let exponent = parseUnary() else { return nil }
                return pow(base, exponent)
            }
            return base
        }

        mutating func parsePostfix() -> Double? {
            guard var value = parsePrimary() else { return nil }
            while peek() == "%" {
                index += 1
                value /= 100
            }
            return value
        }

        mutating func parsePrimary() -> Double? {
            if peek() == "(" {
                index += 1
                guard let value = parseExpression(), peek() == ")" else { return nil }
                index += 1
                return value
            }
            return parseNumber()
        }

        mutating func parseNumber() -> Double? {
            let start = index
            var sawDigit = false
            var sawDot = false
            while let c = peek() {
                if c.isASCII, c.isNumber {
                    sawDigit = true
                    index += 1
                } else if c == ".", !sawDot {
                    sawDot = true
                    index += 1
                } else {
                    break
                }
            }
            guard sawDigit else {
                index = start
                return nil
            }
            return Double(String(chars[start..<index]))
        }
    }
}
