import AppKit

/// Markdown 转成富文本：标题、粗体、斜体、删除线、行内代码、代码块、链接、列表、引用。
enum MarkdownRichText {
    /// 看起来像 Markdown：标题、列表、引用、粗体、行内代码、链接
    static let pattern = #"(^|\n) {0,3}(#{1,6} |[-*+] |\d+\. |> )|\*\*[^*\n]+\*\*|__[^_\n]+__|`[^`\n]+`|\[[^\]\n]+\]\([^)\n]+\)"#

    static func render(_ markdown: String, baseSize: CGFloat = 13) -> NSAttributedString? {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .full,
                                                              failurePolicy: .returnPartiallyParsedIfPossible)
        guard let parsed = try? AttributedString(markdown: markdown, options: options) else { return nil }
        let plain: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: baseSize)]
        let result = NSMutableAttributedString()
        // 同一段里的文字有相同的块信息；换了就是新的一段（段落、标题、列表项、引用、代码块）
        var currentIntent: PresentationIntent?
        var started = false
        for run in parsed.runs {
            let intent = run.presentationIntent
            let block = intent.map(Block.init) ?? Block()
            if !started || intent != currentIntent {
                if started {
                    result.append(NSAttributedString(string: "\n", attributes: plain))
                }
                if let prefix = block.prefix {
                    result.append(NSAttributedString(string: prefix, attributes: plain))
                }
                currentIntent = intent
                started = true
            }
            var font = block.headerLevel.map { NSFont.systemFont(ofSize: headerSize(level: $0, base: baseSize), weight: .bold) }
                ?? NSFont.systemFont(ofSize: baseSize)
            let inline = run.inlinePresentationIntent ?? []
            if block.isCode || inline.contains(.code) {
                font = NSFont.monospacedSystemFont(ofSize: baseSize - 1, weight: .regular)
            }
            if inline.contains(.stronglyEmphasized) {
                font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
            }
            if inline.contains(.emphasized) {
                font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
            }
            var attributes: [NSAttributedString.Key: Any] = [.font: font]
            if inline.contains(.strikethrough) {
                attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            }
            if block.isQuote {
                attributes[.foregroundColor] = NSColor.secondaryLabelColor
            }
            if let link = run.link {
                attributes[.link] = link
            }
            var text = String(parsed[run.range].characters)
            // 代码块末尾自带换行，段落之间的换行由上面统一加
            if block.isCode, text.hasSuffix("\n") {
                text.removeLast()
            }
            result.append(NSAttributedString(string: text, attributes: attributes))
        }
        return result
    }

    /// 显示用：没有指定颜色的文字用系统的文字颜色，深色外观下也看得清（复制出去的不加）
    static func renderForDisplay(_ markdown: String) -> NSAttributedString? {
        guard let rendered = render(markdown) else { return nil }
        let result = NSMutableAttributedString(attributedString: rendered)
        let range = NSRange(location: 0, length: result.length)
        result.enumerateAttribute(.foregroundColor, in: range, options: []) { value, subrange, _ in
            if value == nil {
                result.addAttribute(.foregroundColor, value: NSColor.labelColor, range: subrange)
            }
        }
        return result
    }

    /// 复制到剪贴板：RTF（文稿、邮件、备忘录）、HTML（网页里的编辑器）和纯文本
    static func copy(_ text: NSAttributedString) {
        let range = NSRange(location: 0, length: text.length)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let rtf = try? text.data(from: range, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]) {
            pasteboard.setData(rtf, forType: .rtf)
        }
        if let html = try? text.data(from: range, documentAttributes: [.documentType: NSAttributedString.DocumentType.html]) {
            pasteboard.setData(html, forType: .html)
        }
        pasteboard.setString(text.string, forType: .string)
    }

    private static func headerSize(level: Int, base: CGFloat) -> CGFloat {
        switch level {
        case 1: return base + 9
        case 2: return base + 5
        case 3: return base + 2
        default: return base
        }
    }

    /// 一段文字所在的块：标题、列表项、引用、代码块
    private struct Block {
        var headerLevel: Int?
        var prefix: String?
        var isQuote = false
        var isCode = false

        init() {}

        init(_ intent: PresentationIntent) {
            var ordinal: Int?
            var ordered = false
            var listDepth = 0
            for component in intent.components {
                switch component.kind {
                case .header(let level):
                    headerLevel = level
                case .listItem(let number):
                    ordinal = ordinal ?? number
                case .orderedList:
                    ordered = listDepth == 0 ? true : ordered
                    listDepth += 1
                case .unorderedList:
                    listDepth += 1
                case .blockQuote:
                    isQuote = true
                case .codeBlock:
                    isCode = true
                default:
                    break
                }
            }
            if let ordinal {
                let indent = String(repeating: "    ", count: max(listDepth - 1, 0))
                prefix = indent + (ordered ? "\(ordinal). " : "• ")
            } else if isQuote {
                prefix = "▎"
            }
        }
    }
}
