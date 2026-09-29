import AppKit
import SwiftUI

/// AI 卡片的状态：发出请求、一段段收到回答、停止、重新生成。
@MainActor
final class AIChatModel: ObservableObject {
    enum Phase: Equatable {
        /// 还没发请求，等用户选指令或者提问
        case idle
        case running
        case done
        case failed(String)
    }

    /// 选中的文字
    let source: String
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var output = ""
    /// 这次请求的名字：润色、总结……或者自定义插件的名称
    @Published private(set) var label: String?
    @Published private(set) var activeAction: AIAction?
    @Published var question = ""

    private let settings: AppSettings
    private let keyProvider: () -> String?
    private var task: Task<Void, Never>?
    private var lastMessages: [AIClient.Message] = []

    init(source: String, settings: AppSettings, keyProvider: @escaping () -> String? = AIKeyStore.read) {
        self.source = source
        self.settings = settings
        self.keyProvider = keyProvider
    }

    var isConfigured: Bool { settings.ai.isConfigured }
    var canRegenerate: Bool { !lastMessages.isEmpty && phase != .running }

    func run(_ action: AIAction) {
        let translation = settings.translation
        let answerLanguage = LanguageOption.name(for: translation.foreignTarget)
        let isChinese = ScriptProfile(source).isChinese
        let target = LanguageOption.name(for: isChinese ? translation.chineseTarget : translation.foreignTarget)
        activeAction = action
        start(label: action.title,
              messages: AIPrompt.messages(instruction: action.instruction(answerLanguage: answerLanguage, translationTarget: target),
                                          text: source))
    }

    /// 自定义插件：指令里已经填好了选中的文字
    func run(prompt: String, label: String) {
        activeAction = nil
        start(label: label, messages: [.system(AIPrompt.system), .user(prompt)])
    }

    /// 用输入框里的问题提问
    func ask() {
        let text = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        activeAction = nil
        question = ""
        start(label: text, messages: AIPrompt.messages(instruction: text, text: source))
    }

    func regenerate() {
        guard canRegenerate else { return }
        start(label: label, messages: lastMessages)
    }

    func stop() {
        task?.cancel()
        task = nil
        if phase == .running {
            phase = output.isEmpty ? .idle : .done
        }
    }

    /// ⌘1–⌘4 执行对应的指令
    func handleKey(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
              let characters = event.charactersIgnoringModifiers, let digit = Int(characters),
              AIAction.allCases.indices.contains(digit - 1) else { return false }
        run(AIAction.allCases[digit - 1])
        return true
    }

    private func start(label: String?, messages: [AIClient.Message]) {
        task?.cancel()
        self.label = label
        lastMessages = messages
        output = ""
        guard settings.ai.isConfigured else {
            phase = .failed(AIClient.describe(AIClient.Failure.notConfigured))
            return
        }
        let ai = settings.ai
        let keyProvider = self.keyProvider
        phase = .running
        task = Task { [weak self] in
            // 读钥匙串时系统可能弹窗请用户允许，不放在主线程上等
            let key = await runInBackground { keyProvider() ?? "" }
            guard !Task.isCancelled else { return }
            let configuration = AIClient.Configuration(baseURL: ai.baseURL, apiKey: key, model: ai.model)
            do {
                let request = try AIClient.makeRequest(configuration, messages: messages)
                for try await piece in AIClient.stream(request) {
                    guard let self, !Task.isCancelled else { return }
                    self.output += piece
                }
                guard let self, !Task.isCancelled else { return }
                self.phase = .done
            } catch {
                guard let self, !Task.isCancelled, !(error is CancellationError) else { return }
                self.phase = .failed(AIClient.describe(error))
            }
        }
    }
}

struct AICardView: View {
    @ObservedObject var model: AIChatModel
    /// 原文是在可以编辑的地方选中的文字时，才能「替换原文」
    var canReplace: Bool
    /// 打开卡片时把光标放进提问框
    var focusQuestion = false
    var onAction: (CardAction) -> Void
    var onMore: (() -> Void)?
    var onOpenSettings: () -> Void
    var onClose: () -> Void
    @FocusState private var questionFocused: Bool

    var body: some View {
        CardContainer(title: "AI", subtitle: model.label, width: 420, onClose: onClose) {
            Text(model.source)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            HStack(spacing: 6) {
                ForEach(AIAction.allCases) { action in
                    Button(action.title) { model.run(action) }
                        .buttonStyle(.bordered)
                        .tint(model.activeAction == action ? Color.accentColor : nil)
                        .help("⌘\((AIAction.allCases.firstIndex(of: action) ?? 0) + 1)")
                }
                Spacer(minLength: 0)
            }
            .controlSize(.small)
            TextField("就这段文字提问，回车发送", text: $model.question)
                .textFieldStyle(.roundedBorder)
                .focused($questionFocused)
                .onSubmit { model.ask() }
            Divider()
            result
                .animation(Motion.content, value: model.phase)
            buttons
        }
        .onAppear {
            if focusQuestion {
                questionFocused = true
            }
        }
        .onDisappear {
            model.stop()
        }
    }

    @ViewBuilder
    private var result: some View {
        switch model.phase {
        case .idle:
            if model.isConfigured {
                Text("选一个指令，或者直接提问。选中的文字会发给「设置 → AI」里填写的服务。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                notConfigured
            }
        case .running where model.output.isEmpty:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("思考中…")
                    .foregroundStyle(.secondary)
            }
            .transition(.opacity)
        case .running, .done:
            AIOutputText(text: model.output, isStreaming: model.phase == .running)
        case .failed(let message):
            VStack(alignment: .leading, spacing: 6) {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                Button("打开 AI 设置…", action: onOpenSettings)
                    .controlSize(.small)
            }
            .transition(.opacity)
        }
    }

    private var notConfigured: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("还没有设置 AI 接口。在「设置 → AI」里填写接口地址、API Key 和模型后就能用。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("打开 AI 设置…", action: onOpenSettings)
                .controlSize(.small)
        }
    }

    private var buttons: some View {
        HStack(spacing: 8) {
            if !model.output.isEmpty {
                Button("复制") { onAction(.copy(model.output)) }
                if canReplace {
                    Button("替换原文") { onAction(.replace(model.output)) }
                        .keyboardShortcut(.return, modifiers: .command)
                        .help("用结果替换选中的文字（⌘↩）")
                }
                Button("贴到屏幕") { onAction(.pinText(model.output)) }
            }
            if model.phase == .running {
                Button("停止") { model.stop() }
            } else if model.canRegenerate {
                Button("重新生成") { model.regenerate() }
            }
            if let onMore {
                Button("更多功能", action: onMore)
            }
            Spacer()
        }
        .controlSize(.small)
    }
}

/// AI 的回答：粗体、斜体、行内代码按 Markdown 显示；很长时放进滚动区域，生成过程中跟着滚到最后。
struct AIOutputText: View {
    let text: String
    let isStreaming: Bool

    var body: some View {
        let content = Text(Self.attributed(text))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        if AdaptiveText.isLong(text) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        content.padding(.trailing, 6)
                        Color.clear
                            .frame(height: 1)
                            .id(Self.bottom)
                    }
                }
                .frame(height: 280)
                .onChange(of: text) {
                    if isStreaming {
                        proxy.scrollTo(Self.bottom, anchor: .bottom)
                    }
                }
            }
        } else {
            content.fixedSize(horizontal: false, vertical: true)
        }
    }

    private static let bottom = "bottom"

    static func attributed(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}
