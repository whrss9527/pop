import SwiftUI
import Translation

/// 卡片的通用外框：标题栏 + 关闭按钮 + 内容。
struct CardContainer<Content: View>: View {
    let title: String
    var subtitle: String?
    let onClose: () -> Void
    @ViewBuilder let content: Content

    static var width: CGFloat { 380 }
    static var shadowPadding: CGFloat { 12 }

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
        .padding(14)
        .frame(width: Self.width, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.1), lineWidth: 1))
        .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
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
    var onCopy: (String) -> Void
    var onMore: (() -> Void)?
    var onClose: () -> Void

    var body: some View {
        CardContainer(title: card.title, onClose: onClose) {
            AdaptiveText(text: card.body, monospaced: card.monospaced)
            if let detail = card.detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            HStack(spacing: 8) {
                if let copyText = card.copyText {
                    Button("复制") { onCopy(copyText) }
                        .keyboardShortcut("c", modifiers: .command)
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
    var onCopy: (String) -> Void
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
            HStack(spacing: 8) {
                if let translated = model.translatedText {
                    Button("复制译文") { onCopy(translated) }
                        .keyboardShortcut("c", modifiers: .command)
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
        case .needsDownload:
            VStack(alignment: .leading, spacing: 6) {
                Text("需要先下载「\(model.pairDescription)」的离线语言包。")
                    .font(.callout)
                Button("去下载语言包…", action: onDownload)
                    .controlSize(.small)
            }
        case .done(let translated):
            AdaptiveText(text: translated)
        case .failed(let message):
            Text(message)
                .font(.callout)
                .foregroundStyle(.red)
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
