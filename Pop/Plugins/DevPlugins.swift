import AppKit

// MARK: - 链接解析

struct LinkInspectPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.linkInspect, name: "链接解析", symbol: "link",
                          summary: "拆开链接的协议、主机、路径和每个参数（解码后），去掉 utm_source 这类跟踪参数", accepts: [.url])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let url = content.url, url.scheme?.lowercased() != "mailto" else { return .failure("没有识别到链接") }
        let clean = LinkInspector.cleaned(url)?.absoluteString
        var buttons: [CardButton] = []
        if let clean {
            buttons.append(CardButton(title: "复制干净的链接", action: .copy(clean)))
        }
        return .card(ResultCard(title: "链接解析", body: clean ?? "",
                                detail: clean == nil ? "这个链接里没有跟踪参数" : "上面是去掉跟踪参数后的链接，可以直接替换原文",
                                monospaced: true, replaceText: clean, rows: LinkInspector.rows(for: url), rowLineLimit: 2,
                                buttons: buttons))
    }
}

// MARK: - JWT

struct JWTPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.jwtDecode, name: "JWT 解码", symbol: "key",
                          summary: "解码选中的 JWT，列出签发者、过期时间等声明（只解码，不验证签名）", accepts: [.text],
                          pattern: JWTDecoder.pattern)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text, let token = JWTDecoder.decode(text) else { return .failure("不是有效的 JWT") }
        return .card(ResultCard(title: "JWT", body: token.payload, detail: "只是解码，没有验证签名", monospaced: true,
                                copyText: token.payload, rows: JWTDecoder.rows(for: token),
                                buttons: [CardButton(title: "复制头部", action: .copy(token.header))]))
    }
}

// MARK: - Markdown 转富文本

struct MarkdownCopyPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.markdownCopy, name: "复制为富文本", symbol: "doc.richtext",
                          summary: "把选中的 Markdown 转成带格式的文字复制下来（标题、粗体、列表、链接……），粘贴到文稿、邮件、备忘录里保留格式",
                          accepts: [.text], pattern: MarkdownRichText.pattern)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text, let rich = MarkdownRichText.render(text) else {
            return .failure("没能转换这段 Markdown")
        }
        MarkdownRichText.copy(rich)
        return .done(toast: "已复制为富文本")
    }
}

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
