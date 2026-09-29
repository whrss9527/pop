import SwiftUI
import UniformTypeIdentifiers
import Translation

/// 卡片的通用外框：标题栏 + 关闭按钮 + 内容。
struct CardContainer<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    var width: CGFloat = 380
    let onClose: () -> Void
    @ViewBuilder let content: Content

    /// 给玻璃的阴影和弹出时的缩放留的边距
    static var shadowPadding: CGFloat { 18 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.headline)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("关闭（Esc）")
            }
            content
        }
        .padding(16)
        .frame(width: width, alignment: .leading)
        .glassSurface(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(Self.shadowPadding)
    }
}

/// 长文本放进固定高度的滚动区域，短文本按内容自适应高度。
struct AdaptiveText: View {
    let text: String
    var monospaced = false

    var body: some View {
        let content = Text(text)
            .font(monospaced ? .system(size: 12, design: .monospaced) : .body)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        if Self.isLong(text) {
            ScrollView {
                content.padding(.trailing, 6)
            }
            .frame(height: 280)
        } else {
            content.fixedSize(horizontal: false, vertical: true)
        }
    }

    static func isLong(_ text: String) -> Bool {
        text.count > 600 || text.filter { $0 == "\n" }.count > 14
    }
}

struct ResultCardView: View {
    let card: ResultCard
    var onAction: (CardAction) -> Void
    var onMore: (() -> Void)?
    var onClose: () -> Void

    var body: some View {
        // 文本对比的每一行比较长，卡片放宽一些
        CardContainer(title: card.title, width: card.diff == nil ? 380 : 520, onClose: onClose) {
            if let hex = card.swatchHex, let color = ColorValue.parse(hex) {
                ColorSwatch(color: color)
            }
            if !card.palette.isEmpty {
                PaletteStrip(hexes: card.palette) { onAction(.copy($0)) }
            }
            if let data = card.image, let image = NSImage(data: data) {
                // 按住拖动可以把图片拖到聊天、邮件、文稿里
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 220)
                    .onDrag {
                        NSItemProvider(item: data as NSData, typeIdentifier: UTType.png.identifier)
                    }
            }
            if !card.body.isEmpty {
                AdaptiveText(text: card.body, monospaced: card.monospaced)
            }
            if let diff = card.diff {
                TextDiffView(result: diff)
            }
            if let markdown = card.markdown, let rich = MarkdownRichText.renderForDisplay(markdown) {
                RichTextPreview(text: rich, width: 348)
            }
            if !card.rows.isEmpty {
                ResultRowsView(rows: card.rows, replaceable: card.rowsReplaceable, lineLimit: card.rowLineLimit,
                               onAction: onAction)
            }
            if let detail = card.detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            FlowLayout(spacing: 8) {
                if let copyText = card.copyText {
                    Button("复制") { onAction(.copy(copyText)) }
                        .keyboardShortcut("c", modifiers: .command)
                }
                if let replaceText = card.replaceText {
                    Button("替换原文") { onAction(.replace(replaceText)) }
                        .keyboardShortcut(.return, modifiers: .command)
                        .help("把结果粘贴回原来的 App，替换选中的文字（⌘↩）")
                }
                ForEach(card.buttons) { button in
                    Button(button.title) { onAction(button.action) }
                }
                if let onMore {
                    Button("更多功能", action: onMore)
                }
            }
            .controlSize(.small)
        }
    }
}

/// 多行结果（编码转换、进制转换、哈希……），每行可以单独复制或替换原文。
struct ResultRowsView: View {
    let rows: [ResultCard.Row]
    let replaceable: Bool
    var lineLimit = 4
    let onAction: (CardAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(row.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(width: 76, alignment: .leading)
                    Text(row.value)
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(lineLimit)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button {
                        onAction(.copy(row.value))
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .help("复制")
                    if replaceable {
                        Button {
                            onAction(.replace(row.value))
                        } label: {
                            Image(systemName: "arrow.uturn.backward")
                        }
                        .buttonStyle(.borderless)
                        .help("粘贴回原来的 App（替换选中的文字）")
                    }
                }
            }
        }
    }
}

/// 排好版的富文本（只读，可以选中复制），太长时在固定高度里滚动
struct RichTextPreview: View {
    let text: NSAttributedString
    let width: CGFloat

    private var height: CGFloat {
        let bounds = text.boundingRect(with: CGSize(width: width - 10, height: .greatestFiniteMagnitude),
                                       options: [.usesLineFragmentOrigin, .usesFontLeading])
        return min(max(ceil(bounds.height) + 12, 40), 320)
    }

    var body: some View {
        RichTextView(text: text)
            .frame(width: width, height: height)
    }
}

private struct RichTextView: NSViewRepresentable {
    let text: NSAttributedString

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.autohidesScrollers = true
        if let textView = scroll.documentView as? NSTextView {
            textView.isEditable = false
            textView.isSelectable = true
            textView.drawsBackground = false
            textView.textContainerInset = NSSize(width: 0, height: 4)
            textView.textStorage?.setAttributedString(text)
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView, textView.attributedString() != text else { return }
        textView.textStorage?.setAttributedString(text)
    }
}

/// 一排色块，下面写着色值，点一下复制
struct PaletteStrip: View {
    let hexes: [String]
    let onCopy: (String) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(hexes.enumerated()), id: \.offset) { _, hex in
                if let color = ColorValue.parse(hex) {
                    Button {
                        onCopy(hex)
                    } label: {
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(color.swiftUIColor)
                                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1))
                                .frame(height: 44)
                            Text(hex)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("复制 \(hex)")
                }
            }
        }
    }
}

struct ColorSwatch: View {
    let color: ColorValue

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(color.swiftUIColor)
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.15), lineWidth: 1))
            .frame(height: 40)
    }
}

extension ColorValue {
    var swiftUIColor: Color {
        Color(.sRGB, red: red / 255, green: green / 255, blue: blue / 255, opacity: alpha)
    }
}

// MARK: - 翻译

@MainActor
final class TranslationModel: ObservableObject {
    enum Phase: Equatable {
        case checking
        case needsDownload
        case translating
        case done(String)
        case failed(String)
    }

    let text: String
    let sourceCode: String?
    /// 译成哪种语言；卡片上可以临时换
    @Published private(set) var targetCode: String
    @Published private(set) var phase: Phase = .checking
    @Published private(set) var configuration: TranslationSession.Configuration?

    init(text: String, sourceLanguage: String?, targetLanguage: String) {
        self.text = text
        sourceCode = sourceLanguage
        targetCode = targetLanguage
    }

    /// 换一种目标语言重新翻译
    func switchTarget(to code: String) {
        guard code != targetCode else { return }
        targetCode = code
        configuration = nil
        phase = .checking
        Task {
            await prepare()
        }
    }

    var pairDescription: String {
        "\(LanguageOption.name(for: sourceCode)) → \(LanguageOption.name(for: targetCode))"
    }

    var translatedText: String? {
        if case .done(let text) = phase { return text }
        return nil
    }

    /// 先确认语言包已经装好。没装好时不在浮窗里弹系统下载框（非激活面板里显示不正常），而是引导去设置页下载。
    func prepare() async {
        guard phase == .checking else { return }
        let target = Locale.Language(identifier: targetCode)
        let source = sourceCode.map { Locale.Language(identifier: $0) }
        let availability = LanguageAvailability()
        let status: LanguageAvailability.Status
        if let source {
            status = await availability.status(from: source, to: target)
        } else {
            do {
                status = try await availability.status(for: text, to: target)
            } catch {
                phase = .failed("无法识别原文的语言")
                return
            }
        }
        switch status {
        case .installed:
            phase = .translating
            configuration = TranslationSession.Configuration(source: source, target: target)
        case .supported:
            phase = .needsDownload
        case .unsupported:
            phase = .failed("系统翻译暂不支持「\(pairDescription)」")
        @unknown default:
            phase = .failed("无法确认语言包状态")
        }
    }

    func translate(with session: TranslationSession) async {
        do {
            let response = try await session.translate(text)
            phase = .done(response.targetText)
        } catch {
            phase = .failed("翻译失败：\(error.localizedDescription)")
        }
    }
}

struct TranslationCardView: View {
    @ObservedObject var model: TranslationModel
    /// 原文是在可以编辑的地方选中的文字时，才能「替换原文」
    var canReplace: Bool
    var onAction: (CardAction) -> Void
    var onMore: (() -> Void)?
    var onDownload: () -> Void
    var onClose: () -> Void

    var body: some View {
        CardContainer(title: "翻译", subtitle: model.pairDescription, onClose: onClose) {
            HStack(spacing: 6) {
                Menu {
                    ForEach(LanguageOption.translationTargets) { option in
                        Button(option.name) { model.switchTarget(to: option.id) }
                            .disabled(option.id == model.targetCode)
                    }
                } label: {
                    Text("译成\(LanguageOption.name(for: model.targetCode))")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("换一种语言重新翻译")
                Spacer()
            }
            .font(.callout)
            Text(model.text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            Divider()
            result
                .animation(Motion.content, value: model.phase)
            FlowLayout(spacing: 8) {
                if let translated = model.translatedText {
                    Button("复制译文") { onAction(.copy(translated)) }
                        .keyboardShortcut("c", modifiers: .command)
                    if canReplace {
                        Button("替换原文") { onAction(.replace(translated)) }
                            .keyboardShortcut(.return, modifiers: .command)
                            .help("用译文替换选中的文字（⌘↩）")
                    }
                    Button("贴到屏幕") { onAction(.pinText(translated)) }
                        .help("把译文贴在屏幕最前面，边看原文边对照")
                    Button("朗读") { Speaker.shared.speak(translated, language: model.targetCode) }
                }
                if let onMore {
                    Button("更多功能", action: onMore)
                }
            }
            .controlSize(.small)
        }
        .translationTask(model.configuration) { session in
            await model.translate(with: session)
        }
        .task {
            await model.prepare()
        }
    }

    @ViewBuilder
    private var result: some View {
        switch model.phase {
        case .checking, .translating:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("翻译中…")
                    .foregroundStyle(.secondary)
            }
            .transition(.opacity)
        case .needsDownload:
            VStack(alignment: .leading, spacing: 6) {
                Text("需要先下载「\(model.pairDescription)」的离线语言包。")
                    .font(.callout)
                Button("去下载语言包…", action: onDownload)
                    .controlSize(.small)
            }
            .transition(.opacity)
        case .done(let translated):
            AdaptiveText(text: translated)
                .transition(.opacity)
        case .failed(let message):
            Text(message)
                .font(.callout)
                .foregroundStyle(.red)
                .transition(.opacity)
        }
    }
}

/// 从翻译卡片跳到设置页下载语言包时，告诉设置页要下载哪一对语言。
@MainActor
final class TranslationDownloadRequest: ObservableObject {
    @Published var source = "en"
    @Published var target = "zh-Hans"
    /// 设置页出现（或已经显示）时自动开始下载
    @Published var pendingAutoStart = false

    var pairKey: String { "\(source)>\(target)" }

    func request(source: String?, target: String) {
        if let source {
            self.source = source
        }
        self.target = target
        pendingAutoStart = true
    }
}
