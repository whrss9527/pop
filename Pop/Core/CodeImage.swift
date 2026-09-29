import AppKit

/// 把一段代码画成图片：深色编辑器窗口、简单的语法着色，外面套上渐变背景。
enum CodeImage {
    /// 最多画这么多行、每行这么多字
    static let maxLines = 200
    static let maxColumns = 160

    struct Theme {
        var background = NSColor(srgbRed: 0.12, green: 0.12, blue: 0.16, alpha: 1)
        var text = NSColor(srgbRed: 0.87, green: 0.88, blue: 0.92, alpha: 1)
        var keyword = NSColor(srgbRed: 0.8, green: 0.55, blue: 1, alpha: 1)
        var string = NSColor(srgbRed: 0.6, green: 0.87, blue: 0.54, alpha: 1)
        var number = NSColor(srgbRed: 1, green: 0.7, blue: 0.45, alpha: 1)
        var comment = NSColor(srgbRed: 0.5, green: 0.53, blue: 0.6, alpha: 1)
        var type = NSColor(srgbRed: 0.98, green: 0.85, blue: 0.5, alpha: 1)
    }

    enum TokenKind: Equatable {
        case keyword, string, number, comment, type
    }

    private static let keywords: Set<String> = [
        "func", "let", "var", "if", "else", "for", "while", "return", "class", "struct", "enum", "import", "def", "const",
        "function", "public", "private", "static", "true", "false", "nil", "null", "None", "True", "False", "self", "this",
        "new", "try", "catch", "throw", "throws", "async", "await", "in", "of", "switch", "case", "break", "continue", "guard",
        "protocol", "extension", "interface", "type", "package", "fn", "mut", "impl", "use", "pub", "go", "defer", "from",
        "export", "default", "do", "elif", "lambda", "with", "as", "is", "not", "and", "or", "yield", "final", "override",
        "void", "int", "string", "bool", "select", "where", "match", "val", "object", "when", "fun", "echo", "then", "fi",
    ]

    /// 注释和字符串：从左往右找，谁先出现算谁（字符串里的 // 不算注释）
    private static let commentOrString = try! NSRegularExpression(
        pattern: #"(//[^\n]*|/\*[\s\S]*?\*/|(?<![\w$&])#(?![!\[{(])[^\n]*)|("(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*'|`[^`]*`)"#)
    /// 数字和单词（单词再分关键字、类型名）
    private static let word = try! NSRegularExpression(pattern: #"\b(?:0x[0-9a-fA-F_]+|\d[\d_]*(?:\.\d+)?)\b|\b[A-Za-z_][A-Za-z0-9_]*\b"#)

    /// 要着色的片段，按位置排好
    static func tokens(in code: String) -> [(range: NSRange, kind: TokenKind)] {
        let string = code as NSString
        let full = NSRange(location: 0, length: string.length)
        var result: [(range: NSRange, kind: TokenKind)] = []
        var taken = IndexSet()
        for match in commentOrString.matches(in: code, range: full) where match.range.length > 0 {
            let kind: TokenKind = match.range(at: 1).location != NSNotFound ? .comment : .string
            result.append((match.range, kind))
            taken.insert(integersIn: match.range.location..<NSMaxRange(match.range))
        }
        for match in word.matches(in: code, range: full) {
            let range = match.range
            guard range.length > 0, !taken.intersects(integersIn: range.location..<NSMaxRange(range)) else { continue }
            let text = string.substring(with: range)
            let kind: TokenKind
            if text.first?.isNumber == true {
                kind = .number
            } else if keywords.contains(text) {
                kind = .keyword
            } else if text.first?.isUppercase == true {
                kind = .type
            } else {
                continue
            }
            result.append((range, kind))
        }
        return result.sorted { $0.range.location < $1.range.location }
    }

    /// 去掉每行共同的缩进，Tab 换成 4 个空格，太长的截掉
    static func normalized(_ code: String) -> String {
        var lines = code.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\t", with: "    ")
            .components(separatedBy: "\n")
        while lines.first?.trimmingCharacters(in: .whitespaces).isEmpty == true { lines.removeFirst() }
        while lines.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { lines.removeLast() }
        let indent = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { $0.prefix(while: { $0 == " " }).count }
            .min() ?? 0
        return lines.prefix(maxLines).map { line in
            let trimmed = String(line.dropFirst(min(indent, line.prefix(while: { $0 == " " }).count)))
            return trimmed.count > maxColumns ? String(trimmed.prefix(maxColumns - 1)) + "…" : trimmed
        }.joined(separator: "\n")
    }

    static func attributed(_ code: String, theme: Theme = Theme(), fontSize: CGFloat = 14) -> NSAttributedString {
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = fontSize * 0.35
        let result = NSMutableAttributedString(string: code, attributes: [
            .font: font, .foregroundColor: theme.text, .paragraphStyle: paragraph,
        ])
        for token in tokens(in: code) {
            let color: NSColor
            switch token.kind {
            case .keyword: color = theme.keyword
            case .string: color = theme.string
            case .number: color = theme.number
            case .comment: color = theme.comment
            case .type: color = theme.type
            }
            result.addAttribute(.foregroundColor, value: color, range: token.range)
        }
        return result
    }

    /// 画成 PNG（2 倍像素）；代码是空的时返回 nil
    static func render(_ source: String, background: AnnotationBackground = .sky, scale: CGFloat = 2) -> Data? {
        let code = normalized(source)
        guard !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let theme = Theme()
        let text = attributed(code, theme: theme)
        let textSize = text.boundingRect(with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude),
                                         options: [.usesLineFragmentOrigin, .usesFontLeading]).size
        // 窗口：标题栏 32 点，左右 20 点、上下 18 点的内边距；外面留 48 点的背景
        let window = CGSize(width: max(ceil(textSize.width) + 40, 240), height: ceil(textSize.height) + 32 + 36)
        let outer: CGFloat = 48
        let size = CGSize(width: window.width + outer * 2, height: window.height + outer * 2)
        let width = Int(size.width * scale)
        let height = Int(size.height * scale)
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard width > 0, height > 0, width * height <= 60_000_000,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let gradient = CGGradient(colorsSpace: space, colors: background.nsColors.map(\.cgColor) as CFArray,
                                        locations: [0, 1]) else { return nil }
        // 换成「点、左上角为原点」的坐标
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])

        let frame = CGRect(x: outer, y: outer, width: window.width, height: window.height)
        let path = CGPath(roundedRect: frame, cornerWidth: 12, cornerHeight: 12, transform: nil)
        context.saveGState()
        // 阴影的偏移按原始像素坐标算（y 朝上），往下落要用负数
        context.setShadow(offset: CGSize(width: 0, height: -10 * scale), blur: 30 * scale,
                          color: NSColor.black.withAlphaComponent(0.4).cgColor)
        context.addPath(path)
        context.setFillColor(theme.background.cgColor)
        context.fillPath()
        context.restoreGState()

        // 标题栏上的三个圆点
        let dots: [NSColor] = [NSColor(srgbRed: 1, green: 0.37, blue: 0.34, alpha: 1),
                               NSColor(srgbRed: 1, green: 0.74, blue: 0.18, alpha: 1),
                               NSColor(srgbRed: 0.16, green: 0.79, blue: 0.25, alpha: 1)]
        for (index, color) in dots.enumerated() {
            context.setFillColor(color.cgColor)
            context.fillEllipse(in: CGRect(x: frame.minX + 16 + CGFloat(index) * 20, y: frame.minY + 12, width: 12, height: 12))
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        text.draw(with: CGRect(x: frame.minX + 20, y: frame.minY + 32 + 18, width: ceil(textSize.width) + 2,
                               height: ceil(textSize.height) + 2),
                  options: [.usesLineFragmentOrigin, .usesFontLeading])
        NSGraphicsContext.restoreGraphicsState()
        guard let image = context.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }
}
