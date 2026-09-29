import SwiftUI
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
        CardContainer(title: card.title, onClose: onClose) {
            if let hex = card.swatchHex, let color = ColorValue.parse(hex) {
                ColorSwatch(color: color)
            }
            if let data = card.image, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 200, height: 200)
                    .frame(maxWidth: .infinity)
            }
            if !card.body.isEmpty {
                AdaptiveText(text: card.body, monospaced: card.monospaced)
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
            HStack(spacing: 8) {
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
                Spacer()
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

struct ColorSwatch: View {
    let color: ColorValue

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color(.sRGB, red: color.red / 255, green: color.green / 255, blue: color.blue / 255, opacity: color.alpha))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.15), lineWidth: 1))
            .frame(height: 40)
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
    let targetCode: String
    @Published private(set) var phase: Phase = .checking
    @Published private(set) var configuration: TranslationSession.Configuration?

    init(text: String, sourceLanguage: String?, targetLanguage: String) {
        self.text = text
        sourceCode = sourceLanguage
        targetCode = targetLanguage
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
            Text(model.text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            Divider()
            result
                .animation(Motion.content, value: model.phase)
            HStack(spacing: 8) {
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
                }
                if let onMore {
                    Button("更多功能", action: onMore)
                }
                Spacer()
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
