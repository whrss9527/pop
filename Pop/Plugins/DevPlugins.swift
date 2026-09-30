import AppKit

// MARK: - 链接解析

struct LinkInspectPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.linkInspect, name: String(localized: "链接解析"), symbol: "link",
                          summary: String(localized: "拆开链接的协议、主机、路径和每个参数（解码后），去掉 utm_source 这类跟踪参数"), accepts: [.url])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let url = content.url, url.scheme?.lowercased() != "mailto" else { return .failure(String(localized: "没有识别到链接")) }
        let clean = LinkInspector.cleaned(url)?.absoluteString
        var buttons: [CardButton] = []
        if let clean {
            buttons.append(CardButton(title: String(localized: "复制干净的链接"), action: .copy(clean)))
        }
        var detail = clean == nil ? String(localized: "这个链接里没有跟踪参数") : String(localized: "上面是去掉跟踪参数后的链接，可以直接替换原文")
        if LinkExpander.isShortLink(url) {
            // 只有点了才访问短链接服务
            buttons.insert(CardButton(title: String(localized: "展开短链接"), action: .expandLink(url)), at: 0)
            detail += String(localized: "；这是短链接，点「展开短链接」会访问一次它的服务器，看最后跳到哪里")
        }
        return .card(ResultCard(title: String(localized: "链接解析"), body: clean ?? "", detail: detail,
                                monospaced: true, replaceText: clean, rows: LinkInspector.rows(for: url), rowLineLimit: 2,
                                buttons: buttons))
    }
}

// MARK: - 代码截图

struct CodeImagePlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.codeImage, name: String(localized: "代码截图"), symbol: "chevron.left.forwardslash.chevron.right",
                          summary: String(localized: "把选中的代码画成一张图片（深色编辑器、语法着色、渐变背景），可以复制、存储或贴到屏幕上"),
                          accepts: [.text], maxLength: 20_000)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text, let png = CodeImage.render(text) else { return .failure(String(localized: "没能画出这段代码")) }
        return .card(ResultCard(title: String(localized: "代码截图"), detail: String(localized: "按住拖动预览图也能拖到别的 App 里"), image: png, buttons: [
            CardButton(title: String(localized: "复制图片"), action: .copyImage(png)),
            CardButton(title: String(localized: "存储"), action: .saveImage(png, name: ImageFiles.timestampedName(String(localized: "Pop 代码")))),
            CardButton(title: String(localized: "贴到屏幕"), action: .pinImage(png)),
        ]))
    }
}

// MARK: - Cron

struct CronPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.cron, name: String(localized: "Cron 表达式"), symbol: "clock.arrow.circlepath",
                          summary: String(localized: "把 cron 表达式（比如 */15 9-17 * * 1-5）说成中文，列出接下来几次运行的时间"),
                          accepts: [.text], maxLength: 120, check: .cron)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text, let cron = CronExpression(text) else { return .failure(String(localized: "不是有效的 cron 表达式")) }
        let calendar = Calendar.current
        let runs = cron.nextRuns(after: Date(), count: 5, calendar: calendar)
        let formatter = DateFormatter()
        formatter.locale = Localization.locale
        formatter.dateFormat = "yyyy-MM-dd HH:mm EEE"
        let rows = runs.enumerated().map { index, date in
            ResultCard.Row(label: String(localized: "第 \(index + 1) 次"), value: formatter.string(from: date))
        }
        return .card(ResultCard(title: String(localized: "Cron 表达式"), body: cron.summary,
                                detail: runs.isEmpty ? String(localized: "五年内都不会运行") : String(localized: "接下来几次（本机时区 \(calendar.timeZone.identifier)）"),
                                copyText: cron.summary, rows: rows))
    }
}

// MARK: - JWT

struct JWTPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.jwtDecode, name: String(localized: "JWT 解码"), symbol: "key",
                          summary: String(localized: "解码选中的 JWT，列出签发者、过期时间等声明（只解码，不验证签名）"), accepts: [.text],
                          pattern: JWTDecoder.pattern)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text, let token = JWTDecoder.decode(text) else { return .failure(String(localized: "不是有效的 JWT")) }
        return .card(ResultCard(title: "JWT", body: token.payload, detail: String(localized: "只是解码，没有验证签名"), monospaced: true,
                                copyText: token.payload, rows: JWTDecoder.rows(for: token),
                                buttons: [CardButton(title: String(localized: "复制头部"), action: .copy(token.header))]))
    }
}

// MARK: - Markdown 转富文本

struct MarkdownCopyPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.markdownCopy, name: String(localized: "复制为富文本"), symbol: "doc.richtext",
                          summary: String(localized: "把选中的 Markdown 转成带格式的文字复制下来（标题、粗体、列表、链接……），粘贴到文稿、邮件、备忘录里保留格式"),
                          accepts: [.text], pattern: MarkdownRichText.pattern)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text, let rich = MarkdownRichText.render(text) else {
            return .failure(String(localized: "没能转换这段 Markdown"))
        }
        MarkdownRichText.copy(rich)
        return .done(toast: String(localized: "已复制为富文本"))
    }
}

struct MarkdownPreviewPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.markdownPreview, name: String(localized: "Markdown 预览"), symbol: "doc.text.magnifyingglass",
                          summary: String(localized: "把选中的 Markdown 显示成排好版的样子（标题、列表、粗体、代码……），可以复制为富文本"),
                          accepts: [.text], pattern: MarkdownRichText.pattern)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text, MarkdownRichText.render(text) != nil else {
            return .failure(String(localized: "没能解析这段 Markdown"))
        }
        return .card(ResultCard(title: String(localized: "Markdown 预览"), markdown: text,
                                buttons: [CardButton(title: String(localized: "复制为富文本"), action: .copyRichText(text))]))
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

// MARK: - 转成 Markdown

struct ToMarkdownPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.toMarkdown, name: String(localized: "转成 Markdown"), symbol: "doc.plaintext",
                          summary: String(localized: "把网页、文档里选中的带格式文字转成 Markdown：标题、列表、链接、粗体、代码、表格"),
                          accepts: [.text], hidesOverlay: true)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        // 读选中内容时拿到的只是纯文字，这里带着格式重新拷贝一次（先收起浮窗，⌘C 才会发给原来的 App）
        guard let selection = await context.readRichSelection?() else {
            return .failure(String(localized: "没能拷贝选中的内容，确认文字还选着再试一次"))
        }
        guard let markdown = await runInBackground({ HTMLToMarkdown.convert(selection) }) else {
            return .failure(String(localized: "选中的内容没有带格式（标题、列表、链接这些），不用转换"))
        }
        return .card(ResultCard(title: String(localized: "转成 Markdown"), body: markdown, monospaced: true, copyText: markdown,
                                buttons: [CardButton(title: String(localized: "贴到屏幕"), action: .pinText(markdown))]))
    }
}

// MARK: - JSON 转代码

struct JSONTypesPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.jsonTypes, name: String(localized: "JSON 转代码"), symbol: "curlybraces.square",
                          summary: String(localized: "根据选中的 JSON 生成 TypeScript、Swift、Go、Kotlin 的类型定义"),
                          accepts: [.json], maxLength: JSONTypes.maxLength)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text, let output = await runInBackground({ JSONTypes.generate(text) }) else {
            return .failure(String(localized: "JSON 里没有对象，不用生成类型定义"))
        }
        let tabs = output.code.map { ResultCard.Tab(title: $0.language.rawValue, text: $0.text) }
        return .card(ResultCard(title: String(localized: "JSON 转代码"), detail: String(localized: "\(output.typeCount) 个类型；字段是否可选、能否为空按示例推断"),
                                tabs: tabs))
    }
}

// MARK: - 字符信息

struct CharInfoPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.charInfo, name: String(localized: "字符信息"), symbol: "character.magnify",
                          summary: String(localized: "查看每个字符的 Unicode 码点、名称和编码；找出并去掉零宽空格这类看不见的字符"),
                          accepts: [.text], maxLength: 100_000, check: .characters)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text else { return .failure(String(localized: "没有文字")) }
        return .card(await runInBackground { CharacterInspector.card(for: text) })
    }
}

// MARK: - 正则测试

struct RegexTestPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.regexTest, name: String(localized: "正则测试"), symbol: "asterisk.circle",
                          summary: String(localized: "在选中的文字里试正则表达式：实时标出每处匹配、列出分组，也可以试替换"),
                          accepts: [.text], maxLength: 200_000)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text else { return .failure(String(localized: "没有文字")) }
        return .regexTester(text: text)
    }
}
