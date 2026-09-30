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
    /// 几段排在一起时（翻译对比），长文本的滚动区域矮一些
    var compact = false

    var body: some View {
        let content = Text(text)
            .font(monospaced ? .system(size: 12, design: .monospaced) : .body)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        if Self.isLong(text, compact: compact) {
            ScrollView {
                content.padding(.trailing, 6)
            }
            .frame(height: compact ? 120 : 280)
        } else {
            content.fixedSize(horizontal: false, vertical: true)
        }
    }

    static func isLong(_ text: String, compact: Bool = false) -> Bool {
        let lines = text.filter { $0 == "\n" }.count
        if compact {
            return text.count > 240 || lines > 6
        }
        return text.count > 600 || lines > 14
    }
}

struct ResultCardView: View {
    let card: ResultCard
    var onAction: (CardAction) -> Void
    var onMore: (() -> Void)?
    var onClose: () -> Void
    /// 上次选的分段（比如 JSON 转代码时选的语言），下次默认还是它
    @AppStorage("pop.lastCardTab") private var lastTab = ""

    private var currentTab: ResultCard.Tab? {
        card.tabs.first { $0.title == lastTab } ?? card.tabs.first
    }

    var body: some View {
        // 文本对比、代码每一行比较长，卡片放宽一些
        CardContainer(title: card.title, width: card.diff == nil && card.tabs.isEmpty ? 380 : 520, onClose: onClose) {
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
            if let tab = currentTab {
                Picker("", selection: Binding(get: { tab.title }, set: { lastTab = $0 })) {
                    ForEach(card.tabs) { Text($0.title).tag($0.title) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                AdaptiveText(text: tab.text, monospaced: true)
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
                } else if let tab = currentTab {
                    Button("复制 \(tab.title)") { onAction(.copy(tab.text)) }
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
        /// 联网的引擎一边收一边显示
        case partial(String)
        case done(String)
        /// 引擎还没设置好（没填 DeepL 的 Key、AI 用不了），说明怎么设置
        case unavailable(String)
        case failed(String)
    }

    /// 卡片上看一个引擎的译文，或者几个引擎的放在一起对比
    enum Mode: Hashable {
        case single(TranslationEngine)
        case compare
    }

    let text: String
    let sourceCode: String?
    /// 译成哪种语言；卡片上可以临时换
    @Published private(set) var targetCode: String
    @Published private(set) var mode: Mode
    /// 各个引擎的结果：换了引擎再换回来直接显示，换目标语言时清空
    @Published private(set) var results: [TranslationEngine: Phase] = [:]
    /// 系统翻译的会话配置，交给卡片上的 .translationTask 执行
    @Published private(set) var configuration: TranslationSession.Configuration?

    private let services: TranslationServices
    private var tasks: [TranslationEngine: Task<Void, Never>] = [:]
    /// 换目标语言后，之前的请求回来了也不用
    private var generation = 0

    /// engine 是默认用的引擎；它现在用不了（没填 Key 之类）时先用系统翻译
    init(text: String, sourceLanguage: String?, targetLanguage: String, engine: TranslationEngine = .system,
         services: TranslationServices = .systemOnly) {
        self.text = text
        sourceCode = sourceLanguage
        targetCode = targetLanguage
        self.services = services
        mode = .single(services.unavailableReason(engine) == nil ? engine : .system)
    }

    /// 正在看的引擎；对比时是 nil
    var engine: TranslationEngine? {
        if case .single(let engine) = mode {
            return engine
        }
        return nil
    }

    var pairDescription: String {
        "\(LanguageOption.name(for: sourceCode)) → \(LanguageOption.name(for: targetCode))"
    }

    func phase(of engine: TranslationEngine) -> Phase {
        results[engine] ?? .checking
    }

    /// 正在看的引擎的状态
    var phase: Phase {
        phase(of: engine ?? .system)
    }

    /// 正在看的引擎翻译好的译文；对比时是 nil（每一家的译文单独复制）
    var translatedText: String? {
        guard let engine, case .done(let translated) = phase(of: engine) else { return nil }
        return translated
    }

    /// 卡片出现时开始翻译
    func start() {
        runMissing()
    }

    /// 换一种目标语言重新翻译
    func switchTarget(to code: String) {
        guard code != targetCode else { return }
        targetCode = code
        generation += 1
        for task in tasks.values {
            task.cancel()
        }
        tasks = [:]
        results = [:]
        configuration = nil
        runMissing()
    }

    /// 换引擎，或者切到对比：翻译过的直接显示，没翻译过的开始翻译
    func switchMode(to newMode: Mode) {
        guard newMode != mode else { return }
        mode = newMode
        runMissing()
    }

    /// 等正在跑的翻译都结束（测试用）
    func waitUntilFinished() async {
        for task in tasks.values {
            await task.value
        }
    }

    private func runMissing() {
        let engines: [TranslationEngine]
        switch mode {
        case .single(let engine):
            engines = [engine]
        case .compare:
            engines = TranslationEngine.allCases
        }
        for engine in engines where results[engine] == nil {
            run(engine)
        }
    }

    private func run(_ engine: TranslationEngine) {
        if let reason = services.unavailableReason(engine) {
            results[engine] = .unavailable(reason)
            return
        }
        let generation = self.generation
        if engine == .system {
            results[engine] = .checking
            tasks[engine] = Task { [weak self] in
                await self?.prepareSystem(generation: generation)
            }
            return
        }
        results[engine] = .translating
        let services = self.services
        let text = self.text
        let target = targetCode
        tasks[engine] = Task { [weak self] in
            var output = ""
            do {
                let stream = try await services.translate(engine, text, target)
                for try await piece in stream {
                    output += piece
                    guard let self, self.generation == generation else { return }
                    self.results[engine] = .partial(output)
                }
                guard let self, self.generation == generation else { return }
                let translated = output.trimmingCharacters(in: .whitespacesAndNewlines)
                self.results[engine] = translated.isEmpty ? .failed(String(localized: "\(engine.title) 没有返回译文")) : .done(translated)
            } catch {
                guard let self, self.generation == generation, !Task.isCancelled else { return }
                self.results[engine] = .failed(TranslationModel.describe(error))
            }
        }
    }

    /// 系统翻译先确认语言包已经装好。没装好时不在浮窗里弹系统下载框（非激活面板里显示不正常），而是引导去设置页下载。
    private func prepareSystem(generation: Int) async {
        let status = await services.checkSystem(text, sourceCode, targetCode)
        guard self.generation == generation else { return }
        switch status {
        case .installed:
            results[.system] = .translating
            configuration = TranslationSession.Configuration(source: sourceCode.map { Locale.Language(identifier: $0) },
                                                             target: Locale.Language(identifier: targetCode))
        case .needsDownload:
            results[.system] = .needsDownload
        case .unsupported:
            results[.system] = .failed(String(localized: "系统翻译暂不支持「\(pairDescription)」"))
        case .failed(let message):
            results[.system] = .failed(message)
        }
    }

    func translate(with session: TranslationSession) async {
        let generation = self.generation
        do {
            let response = try await session.translate(text)
            guard self.generation == generation else { return }
            results[.system] = .done(response.targetText)
        } catch {
            guard self.generation == generation else { return }
            results[.system] = .failed(String(localized: "翻译失败：\(error.localizedDescription)"))
        }
    }

    private static func describe(_ error: Error) -> String {
        if let failure = error as? DeepLClient.Failure {
            return failure.message
        }
        return AIClient.describe(error)
    }
}

struct TranslationCardView: View {
    @ObservedObject var model: TranslationModel
    /// 原文是在可以编辑的地方选中的文字时，才能「替换原文」
    var canReplace: Bool
    var onAction: (CardAction) -> Void
    var onMore: (() -> Void)?
    var onDownload: () -> Void
    /// 去设置里把引擎设置好（DeepL 的 Key 在「翻译」，AI 在「AI」）
    var onOpenSettings: ((SettingsTab) -> Void)? = nil
    var onClose: () -> Void

    var body: some View {
        CardContainer(title: String(localized: "翻译"), subtitle: model.pairDescription, onClose: onClose) {
            HStack(spacing: 8) {
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
                Picker("翻译引擎", selection: modeBinding) {
                    ForEach(TranslationEngine.allCases) { engine in
                        Text(engine.title).tag(TranslationModel.Mode.single(engine))
                    }
                    Text("对比").tag(TranslationModel.Mode.compare)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .fixedSize()
                .help("换一个翻译引擎，或者把几家的译文放在一起对比")
            }
            .font(.callout)
            Text(model.text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            Divider()
            if model.mode == .compare {
                comparison
            } else {
                result(model.phase, engine: model.engine ?? .system, compact: false)
                    .animation(Motion.content, value: model.phase)
            }
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
                    if VocabularyStore.isWordLike(model.text) {
                        Button("加入生词本") {
                            onAction(.addToVocabulary(word: model.text, translation: translated, source: model.sourceCode,
                                                      target: model.targetCode))
                        }
                        .help("把这个词和译文存到生词本，之后可以复习")
                    }
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
            model.start()
        }
    }

    private var modeBinding: Binding<TranslationModel.Mode> {
        Binding(get: { model.mode }, set: { model.switchMode(to: $0) })
    }

    /// 几家的译文一段接一段排下来，每一段可以单独复制、替换原文
    private var comparison: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(TranslationEngine.allCases) { engine in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(engine.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        if case .done(let translated) = model.phase(of: engine) {
                            Button("复制") { onAction(.copy(translated)) }
                            if canReplace {
                                Button("替换原文") { onAction(.replace(translated)) }
                            }
                        }
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    result(model.phase(of: engine), engine: engine, compact: true)
                }
            }
        }
        .animation(Motion.content, value: model.results)
    }

    @ViewBuilder
    private func result(_ phase: TranslationModel.Phase, engine: TranslationEngine, compact: Bool) -> some View {
        switch phase {
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
        case .partial(let translated):
            AdaptiveText(text: translated, compact: compact)
                .foregroundStyle(.secondary)
        case .done(let translated):
            AdaptiveText(text: translated, compact: compact)
                .transition(.opacity)
        case .unavailable(let message):
            VStack(alignment: .leading, spacing: 6) {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if let onOpenSettings {
                    Button("去设置…") { onOpenSettings(engine == .ai ? .ai : .translation) }
                        .controlSize(.small)
                }
            }
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
