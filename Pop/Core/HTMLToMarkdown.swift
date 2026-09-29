import AppKit

/// 从网页、文档里复制出来的带格式内容转成 Markdown。纯逻辑，方便测试。
///
/// - HTML（浏览器、邮件、大多数编辑器）：标题、段落、粗体、斜体、删除线、行内代码、代码块、链接、图片、
///   列表（包括任务列表）、引用、分隔线、表格；
/// - 只有 RTF 的（文本编辑、Pages 这类）：粗体、斜体、删除线、等宽字体、链接、列表，字号明显更大的整段粗体当标题。
enum HTMLToMarkdown {
    /// 选中内容带的格式：有 HTML 用 HTML，没有就用 RTF；转出来和纯文字一样（没有格式）时返回 nil
    static func convert(_ selection: RichSelection) -> String? {
        var markdown = selection.html.flatMap { convert($0) }
        if markdown == nil, let rtf = selection.rtf, let attributed = NSAttributedString(rtf: rtf, documentAttributes: nil) {
            markdown = convert(attributed: attributed)
        }
        if markdown == nil, let rtfd = selection.rtfd, let attributed = NSAttributedString(rtfd: rtfd, documentAttributes: nil) {
            markdown = convert(attributed: attributed)
        }
        guard let markdown else { return nil }
        if let text = selection.text, words(markdown) == words(text) { return nil }
        return markdown
    }

    static func convert(_ html: String) -> String? {
        guard let root = body(of: html) else { return nil }
        let markdown = tidy(blocks(in: root).joined(separator: "\n\n"))
        return markdown.isEmpty ? nil : markdown
    }

    /// 从富文本转换（没有 HTML、只有 RTF 的时候用）
    static func convert(attributed: NSAttributedString) -> String? {
        let markdown = tidy(AttributedMarkdown.convert(attributed))
        return markdown.isEmpty ? nil : markdown
    }

    /// 比较时忽略空白的差别
    private static func words(_ text: String) -> [Substring] {
        text.split(whereSeparator: { $0.isWhitespace })
    }

    // MARK: - 解析

    private static func body(of html: String) -> XMLElement? {
        let candidates = [html, "<html><body>\(html)</body></html>"]
        for source in candidates {
            guard let document = try? XMLDocument(xmlString: source, options: [.documentTidyHTML]),
                  let root = document.rootElement() else { continue }
            return find("body", in: root) ?? root
        }
        return nil
    }

    private static func find(_ name: String, in element: XMLElement) -> XMLElement? {
        if tag(element) == name { return element }
        for case let child as XMLElement in element.children ?? [] {
            if let found = find(name, in: child) { return found }
        }
        return nil
    }

    /// 标签名；Word 的 <o:p> 这类带前缀的保留前缀，不会被当成 <p>
    private static func tag(_ node: XMLNode) -> String? {
        guard node.kind == .element else { return nil }
        return node.name?.lowercased()
    }

    private static func attribute(_ name: String, of element: XMLElement) -> String? {
        element.attribute(forName: name)?.stringValue
    }

    /// 自己占一块、前后要分段的元素
    private static let blockTags: Set<String> = [
        "address", "article", "aside", "blockquote", "body", "center", "dd", "details", "dialog", "div", "dl", "dt",
        "fieldset", "figcaption", "figure", "footer", "form", "h1", "h2", "h3", "h4", "h5", "h6", "header", "hr", "html",
        "li", "main", "nav", "ol", "p", "pre", "section", "summary", "table", "tbody", "td", "tfoot", "th", "thead", "tr", "ul",
    ]

    /// 不是正文的元素，整个跳过
    private static let skippedTags: Set<String> = [
        "head", "script", "style", "noscript", "template", "title", "meta", "link", "button", "select", "option",
        "textarea", "iframe", "object", "svg", "canvas", "video", "audio",
    ]

    // MARK: - 块级元素

    /// 一个容器里的内容，每一块（段落、标题、列表……）一个字符串
    private static func blocks(in node: XMLNode) -> [String] {
        var result: [String] = []
        var inlineText = ""
        func flush() {
            let paragraph = cleanParagraph(inlineText)
            if !paragraph.isEmpty { result.append(paragraph) }
            inlineText = ""
        }
        for child in node.children ?? [] {
            if let element = child as? XMLElement, let name = tag(element), blockTags.contains(name) {
                flush()
                result += block(element, name: name)
            } else {
                inlineText += inline(child)
            }
        }
        flush()
        return result
    }

    private static func block(_ element: XMLElement, name: String) -> [String] {
        switch name {
        case "h1", "h2", "h3", "h4", "h5", "h6":
            let level = Int(name.dropFirst()) ?? 1
            let text = singleLine(inlineChildren(element))
            return text.isEmpty ? [] : [String(repeating: "#", count: level) + " " + text]
        case "ul", "ol":
            let rendered = list(element, ordered: name == "ol")
            return rendered.isEmpty ? [] : [rendered]
        case "li":
            // 没有放在列表里的 li
            return [listItem(element, marker: "- ")]
        case "blockquote":
            let inner = blocks(in: element).joined(separator: "\n\n")
            return inner.isEmpty ? [] : [quote(inner)]
        case "pre":
            let code = codeBlock(element)
            return code.isEmpty ? [] : [code]
        case "hr":
            return ["---"]
        case "table":
            return table(element).map { [$0] } ?? []
        case "dt":
            let text = singleLine(inlineChildren(element))
            return text.isEmpty ? [] : [wrap(text, "**")]
        default:
            return blocks(in: element)
        }
    }

    private static func list(_ element: XMLElement, ordered: Bool) -> String {
        var number = Int(attribute("start", of: element) ?? "") ?? 1
        var items: [String] = []
        for case let child as XMLElement in element.children ?? [] {
            switch tag(child) {
            case "li":
                let marker = ordered ? "\(number). " : "- "
                number += 1
                items.append(listItem(child, marker: marker))
            case "ul", "ol":
                // 不规范的写法：嵌套列表直接放在 ul 里，接到上一项下面
                let nested = list(child, ordered: tag(child) == "ol")
                guard !nested.isEmpty else { continue }
                if let last = items.popLast() {
                    items.append(last + "\n" + indent(nested, by: ordered ? 3 : 2))
                } else {
                    items.append(nested)
                }
            default:
                continue
            }
        }
        return items.joined(separator: "\n")
    }

    private static func listItem(_ item: XMLElement, marker: String) -> String {
        let content = blocks(in: item).joined(separator: "\n")
        guard !content.isEmpty else { return marker.trimmingCharacters(in: .whitespaces) }
        let lines = content.components(separatedBy: "\n")
        return ([marker + lines[0]] + lines.dropFirst().map { $0.isEmpty ? "" : String(repeating: " ", count: marker.count) + $0 })
            .joined(separator: "\n")
    }

    private static func indent(_ text: String, by count: Int) -> String {
        text.components(separatedBy: "\n").map { $0.isEmpty ? "" : String(repeating: " ", count: count) + $0 }
            .joined(separator: "\n")
    }

    private static func quote(_ text: String) -> String {
        text.components(separatedBy: "\n").map { $0.isEmpty ? ">" : "> " + $0 }.joined(separator: "\n")
    }

    private static func codeBlock(_ pre: XMLElement) -> String {
        let code = trimBlankLines(preformatted(pre))
        guard !code.isEmpty else { return "" }
        var fence = "```"
        while code.contains(fence) { fence += "`" }
        return fence + codeLanguage(pre) + "\n" + code + "\n" + fence
    }

    /// 代码块里的文字原样保留；有的网站用 <br> 或者每行一个 <div> 分行
    private static func preformatted(_ node: XMLNode) -> String {
        switch node.kind {
        case .text:
            return node.stringValue ?? ""
        case .element:
            guard let name = tag(node) else { return "" }
            if name == "br" { return "\n" }
            var text = (node.children ?? []).map(preformatted).joined()
            if ["div", "p", "li", "tr"].contains(name), !text.hasSuffix("\n") {
                text += "\n"
            }
            return text
        default:
            return ""
        }
    }

    /// class 里的 language-swift、lang-js，GitHub 的 highlight-source-python
    private static func codeLanguage(_ pre: XMLElement) -> String {
        var elements: [XMLElement] = [pre]
        elements += (pre.children ?? []).compactMap { $0 as? XMLElement }.filter { tag($0) == "code" }
        if let parent = pre.parent as? XMLElement { elements.append(parent) }
        for element in elements {
            var tokens = (attribute("class", of: element) ?? "").split(separator: " ").map(String.init)
            if let lang = attribute("lang", of: element) ?? attribute("data-lang", of: element) { tokens.append("language-" + lang) }
            for token in tokens {
                for prefix in ["language-", "lang-", "highlight-source-"] where token.hasPrefix(prefix) {
                    let name = token.dropFirst(prefix.count).lowercased()
                    if !name.isEmpty, name.count <= 20, name.allSatisfy({ $0.isLetter || $0.isNumber || "+#-_".contains($0) }) {
                        return name
                    }
                }
            }
        }
        return ""
    }

    private static func table(_ element: XMLElement) -> String? {
        var rows: [[String]] = []
        func collect(_ node: XMLElement) {
            for case let child as XMLElement in node.children ?? [] {
                switch tag(child) {
                case "tr":
                    let cells = (child.children ?? []).compactMap { $0 as? XMLElement }
                        .filter { ["td", "th"].contains(tag($0) ?? "") }
                        .map { singleLine(blocks(in: $0).joined(separator: " ")) }
                    if !cells.isEmpty { rows.append(cells) }
                case "thead", "tbody", "tfoot":
                    collect(child)
                default:
                    continue
                }
            }
        }
        collect(element)
        let width = rows.map(\.count).max() ?? 0
        guard width > 0 else { return nil }
        let padded = rows.map { $0 + Array(repeating: "", count: width - $0.count) }
        return TableConverter.render(padded, as: .markdown)
    }

    // MARK: - 行内元素

    private static func inlineChildren(_ element: XMLElement) -> String {
        (element.children ?? []).map(inline).joined()
    }

    private static func inline(_ node: XMLNode) -> String {
        switch node.kind {
        case .text:
            return escape(collapse(node.stringValue ?? ""))
        case .element:
            guard let element = node as? XMLElement, let name = tag(element), !skippedTags.contains(name) else { return "" }
            return inline(element, name: name)
        default:
            return ""
        }
    }

    private static func inline(_ element: XMLElement, name: String) -> String {
        switch name {
        case "br":
            return "\n"
        case "img":
            return image(element)
        case "a":
            return link(element)
        case "strong", "b":
            // 从 Google 文档复制出来的内容外面包着一层 font-weight:normal 的 <b>
            let style = normalizedStyle(element)
            let text = styled(inlineChildren(element), style: style, weight: false)
            return style.contains("font-weight:normal") || style.contains("font-weight:400") ? text : wrap(text, "**")
        case "em", "i", "cite", "dfn":
            return wrap(inlineChildren(element), "*")
        case "s", "del", "strike":
            return wrap(inlineChildren(element), "~~")
        case "code", "kbd", "samp", "tt":
            return inlineCode(element.stringValue ?? "")
        case "input":
            guard attribute("type", of: element)?.lowercased() == "checkbox" else { return "" }
            return element.attribute(forName: "checked") != nil ? "[x] " : "[ ] "
        case "q":
            return "“" + inlineChildren(element) + "”"
        default:
            let text = styled(inlineChildren(element), style: normalizedStyle(element))
            // 块级元素出现在行内元素里（不规范但常见）：前后换行
            return blockTags.contains(name) ? "\n" + text + "\n" : text
        }
    }

    private static func normalizedStyle(_ element: XMLElement) -> String {
        (attribute("style", of: element) ?? "").lowercased().replacingOccurrences(of: " ", with: "")
    }

    /// 用 style 写的粗体、斜体、删除线（Google 文档、Word 常见）
    private static func styled(_ text: String, style: String, weight: Bool = true) -> String {
        guard !style.isEmpty else { return text }
        var result = text
        if style.contains("line-through") {
            result = wrap(result, "~~")
        }
        if style.contains("font-style:italic") {
            result = wrap(result, "*")
        }
        if weight, let range = style.range(of: "font-weight:") {
            let value = style[range.upperBound...].prefix { $0 != ";" }
            if value == "bold" || value == "bolder" || (Int(value).map { $0 >= 600 } ?? false) {
                result = wrap(result, "**")
            }
        }
        return result
    }

    private static func link(_ element: XMLElement) -> String {
        let content = inlineChildren(element).replacingOccurrences(of: "\n", with: " ")
        guard let href = attribute("href", of: element)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !href.isEmpty, !href.hasPrefix("#"), !href.lowercased().hasPrefix("javascript:") else { return content }
        let text = content.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return content }
        let leading = String(content.prefix { $0 == " " })
        let trailing = String(content.reversed().prefix { $0 == " " })
        let body: String
        if "mailto:" + text == href {
            body = "<\(text)>"
        } else if text == escape(href), !href.contains(" ") {
            body = "<\(href)>"
        } else {
            body = "[\(text)](\(destination(href)))"
        }
        return leading + body + trailing
    }

    private static func image(_ element: XMLElement) -> String {
        let alt = collapse(attribute("alt", of: element) ?? "").trimmingCharacters(in: .whitespaces)
        guard let source = attribute("src", of: element)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !source.isEmpty, !source.hasPrefix("data:") else { return escape(alt) }
        let label = alt.replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
        return "![\(label)](\(destination(source)))"
    }

    /// 网址里有空格或者括号不成对时，用尖括号包起来
    private static func destination(_ url: String) -> String {
        let encoded = url.replacingOccurrences(of: " ", with: "%20")
        var depth = 0
        for character in encoded {
            if character == "(" { depth += 1 }
            if character == ")" { depth -= 1 }
            if depth < 0 { break }
        }
        return depth == 0 && !encoded.contains("<") && !encoded.contains(">") ? encoded : "<\(encoded)>"
    }

    static func inlineCode(_ raw: String) -> String {
        let text = collapse(raw)
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return text }
        var fence = "`"
        while text.contains(fence) { fence += "`" }
        let padded = text.hasPrefix("`") || text.hasSuffix("`") ? " \(text) " : text
        return fence + padded + fence
    }

    // MARK: - 文字处理

    /// 行内的空白（包括换行）合成一个空格，和浏览器显示的一样
    private static let whitespace = try! NSRegularExpression(pattern: #"[ \t\n\r\f\x{00A0}]+"#)

    private static func collapse(_ text: String) -> String {
        whitespace.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: " ")
    }

    /// 普通文字里会被当成 Markdown 语法的字符前面加反斜杠；单词中间的下划线（snake_case）不用转义
    static func escape(_ text: String) -> String {
        let characters = Array(text)
        var result = ""
        for (index, character) in characters.enumerated() {
            switch character {
            case "*", "`":
                result += "\\" + String(character)
            case "_":
                let before = index > 0 ? characters[index - 1] : " "
                let after = index + 1 < characters.count ? characters[index + 1] : " "
                let inWord = (before.isLetter || before.isNumber) && (after.isLetter || after.isNumber)
                result += inWord ? "_" : "\\_"
            case "<":
                let after = index + 1 < characters.count ? characters[index + 1] : " "
                result += after.isLetter || "/!?".contains(after) ? "\\<" : "<"
            default:
                result.append(character)
            }
        }
        return result
    }

    /// 粗体、斜体的标记要紧贴文字：「 粗体 」变成「 **粗体** 」，不然不生效
    static func wrap(_ text: String, _ marker: String) -> String {
        let core = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !core.isEmpty else { return text }
        let leading = String(text.prefix { $0 == " " || $0 == "\n" })
        let trailing = String(text.reversed().prefix { $0 == " " || $0 == "\n" }.reversed())
        return leading + marker + core + marker + trailing
    }

    private static func singleLine(_ text: String) -> String {
        text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
    }

    /// 段落：每行去掉首尾空格、连续的空格合成一个，行首会被当成标题、引用、列表的字符转义
    private static func cleanParagraph(_ text: String) -> String {
        text.components(separatedBy: "\n")
            .map { line in
                let collapsed = line.replacingOccurrences(of: #" {2,}"#, with: " ", options: .regularExpression)
                return escapeLineStart(collapsed.trimmingCharacters(in: .whitespaces))
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .newlines)
    }

    private static let lineStart = try! NSRegularExpression(pattern: #"^(#{1,6}(?=\s|$)|>|[-+](?=\s)|\d+(?=[.)]\s))"#)

    private static func escapeLineStart(_ line: String) -> String {
        guard let match = lineStart.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let range = Range(match.range, in: line) else { return line }
        let token = String(line[range])
        if token.first?.isNumber == true {
            // 「1. 」→「1\. 」
            return token + "\\" + line[range.upperBound...]
        }
        return "\\" + line
    }

    private static func trimBlankLines(_ text: String) -> String {
        var lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        while lines.first?.trimmingCharacters(in: .whitespaces).isEmpty == true { lines.removeFirst() }
        while lines.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { lines.removeLast() }
        return lines.joined(separator: "\n")
    }

    /// 去掉行尾空格，连续的空行只留一个
    static func tidy(_ markdown: String) -> String {
        var lines: [String] = []
        // 代码块里的内容原样保留
        var fence: String?
        for raw in markdown.components(separatedBy: "\n") {
            if let open = fence {
                lines.append(raw)
                if raw.trimmingCharacters(in: .whitespaces) == open { fence = nil }
                continue
            }
            let line = raw.replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                fence = String(trimmed.prefix { $0 == "`" })
            }
            if line.isEmpty, lines.last?.isEmpty ?? true { continue }
            lines.append(line)
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// 富文本（NSAttributedString）转 Markdown：按段落处理，行内按字体、链接、删除线分段
enum AttributedMarkdown {
    static func convert(_ attributed: NSAttributedString) -> String {
        let string = attributed.string as NSString
        let baseSize = bodyFontSize(attributed)
        var paragraphs: [String] = []
        var previousWasList = false
        string.enumerateSubstrings(in: NSRange(location: 0, length: string.length), options: .byParagraphs) { _, range, _, _ in
            let line = Self.paragraph(attributed, range: range, baseSize: baseSize)
            if line.isList, previousWasList {
                // 列表的各项之间不空行
                paragraphs[paragraphs.count - 1] += "\n" + line.text
            } else {
                paragraphs.append(line.text)
            }
            previousWasList = line.isList
        }
        return paragraphs.filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    private static func paragraph(_ attributed: NSAttributedString, range: NSRange, baseSize: CGFloat) -> (text: String, isList: Bool) {
        guard range.length > 0 else { return ("", false) }
        let style = attributed.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle
        var content = range
        // 列表项开头系统自动加的「\t•\t」「\t1.\t」不要
        let lists = style?.textLists ?? []
        let text = (attributed.string as NSString).substring(with: range)
        if !lists.isEmpty, let marker = text.range(of: #"^\t?[^\t]{1,8}\t"#, options: .regularExpression) {
            let length = NSRange(marker, in: text).length
            content = NSRange(location: range.location + length, length: range.length - length)
        }
        let body = inline(attributed, range: content)
        guard !body.trimmingCharacters(in: .whitespaces).isEmpty else { return ("", false) }
        if let list = lists.last {
            let depth = String(repeating: "  ", count: lists.count - 1)
            let format = list.markerFormat.rawValue
            let isOrdered = ["decimal", "alpha", "roman", "octal", "hex"].contains { format.contains($0) }
            let number = attributed.itemNumber(in: list, at: range.location)
            return (depth + (isOrdered ? "\(number). " : "- ") + body, true)
        }
        if let level = headingLevel(attributed, range: content, baseSize: baseSize) {
            let plain = (attributed.string as NSString).substring(with: content).trimmingCharacters(in: .whitespaces)
            return (String(repeating: "#", count: level) + " " + HTMLToMarkdown.escape(plain), false)
        }
        return (body, false)
    }

    /// 正文字号：字数最多的那个字号
    private static func bodyFontSize(_ attributed: NSAttributedString) -> CGFloat {
        var counts: [CGFloat: Int] = [:]
        attributed.enumerateAttribute(.font, in: NSRange(location: 0, length: attributed.length)) { value, range, _ in
            let size = (value as? NSFont)?.pointSize ?? 12
            counts[size, default: 0] += range.length
        }
        return counts.max { $0.value < $1.value }?.key ?? 12
    }

    /// 整段粗体、字号比正文大 20% 以上的当标题
    private static func headingLevel(_ attributed: NSAttributedString, range: NSRange, baseSize: CGFloat) -> Int? {
        guard range.length <= 200 else { return nil }
        var allBold = true
        var size: CGFloat = 0
        attributed.enumerateAttribute(.font, in: range) { value, _, _ in
            guard let font = value as? NSFont else { allBold = false; return }
            if !font.fontDescriptor.symbolicTraits.contains(.bold) { allBold = false }
            size = max(size, font.pointSize)
        }
        guard allBold, size >= baseSize * 1.2 else { return nil }
        if size >= baseSize * 1.8 { return 1 }
        if size >= baseSize * 1.4 { return 2 }
        return 3
    }

    /// 一段格式相同的文字
    private struct Run: Equatable {
        var bold = false
        var italic = false
        var strike = false
        var code = false
        var link: String?
    }

    private static func inline(_ attributed: NSAttributedString, range: NSRange) -> String {
        let string = attributed.string as NSString
        // 字体、颜色之类的属性一变就会分段，先把格式相同的相邻片段合起来
        var runs: [(format: Run, text: String)] = []
        attributed.enumerateAttributes(in: range) { attributes, runRange, _ in
            let traits = (attributes[.font] as? NSFont)?.fontDescriptor.symbolicTraits ?? []
            var format = Run()
            format.code = traits.contains(.monoSpace)
            format.bold = traits.contains(.bold)
            format.italic = traits.contains(.italic)
            format.strike = (attributes[.strikethroughStyle] as? Int ?? 0) != 0
            if let link = attributes[.link] {
                format.link = (link as? URL)?.absoluteString ?? (link as? String)
            }
            let text = string.substring(with: runRange).replacingOccurrences(of: "\u{2028}", with: "\n")
            if let last = runs.last, last.format == format {
                runs[runs.count - 1].text += text
            } else {
                runs.append((format, text))
            }
        }
        return runs.map { run -> String in
            var text: String
            if run.format.code {
                text = HTMLToMarkdown.inlineCode(run.text)
            } else {
                text = HTMLToMarkdown.escape(run.text)
                if run.format.strike { text = HTMLToMarkdown.wrap(text, "~~") }
                if run.format.italic { text = HTMLToMarkdown.wrap(text, "*") }
                if run.format.bold { text = HTMLToMarkdown.wrap(text, "**") }
            }
            if let url = run.format.link, !url.isEmpty, !run.text.trimmingCharacters(in: .whitespaces).isEmpty {
                text = "[\(text)](\(url.replacingOccurrences(of: " ", with: "%20")))"
            }
            return text
        }.joined()
    }
}
