import SwiftUI

/// 「设置 → AI」：接口地址、API Key、模型，以及测试连接。
struct AISettingsView: View {
    @EnvironmentObject private var store: SettingsStore
    @State private var apiKey = ""
    @State private var keyLoaded = false
    @State private var test: TestState = .idle

    enum TestState: Equatable {
        case idle
        case testing
        case succeeded(String)
        case failed(String)
    }

    var body: some View {
        Form {
            Section {
                TextField("接口地址", text: store.binding(\.ai.baseURL), prompt: Text("https://api.openai.com/v1"))
                SecureField("API Key", text: $apiKey, prompt: Text("本机运行的服务可以不填"))
                    .onSubmit(saveKey)
                TextField("模型", text: store.binding(\.ai.model), prompt: Text("比如 gpt-4o-mini"))
                HStack(spacing: 8) {
                    Button("保存并测试", action: runTest)
                        .disabled(test == .testing || !store.settings.ai.isConfigured)
                    testStatus
                    Spacer()
                }
            } header: {
                Text("AI 接口")
            } footer: {
                Text("填写兼容 OpenAI Chat Completions 的接口，地址写到 /v1 为止；在本机运行的模型服务也可以（比如 http://localhost:11434/v1）。接口地址和模型会随设置通过 iCloud 同步，API Key 只保存在这台 Mac 的钥匙串里。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Label("选中文字后用「AI 助手」提问，或者让 AI 润色、总结、解释、翻译；结果可以复制、替换原文、贴到屏幕上。", systemImage: "sparkles")
                Label("「AI 润色」「AI 总结」「AI 解释」可以在「功能」里打开，放到圆盘上一划就执行。", systemImage: "circle.circle")
                Label("在「功能 → 我的插件」里新建「AI 指令」类型的插件，写上自己的指令（{text} 换成选中的文字）。", systemImage: "puzzlepiece.extension")
            } header: {
                Text("怎么用")
            }

            Section {
                Text("只有在你使用 AI 功能时，Pop 才会把选中的文字发给上面填写的服务，不会在后台发送任何内容。服务怎么处理这些文字，以服务方的隐私政策为准。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } header: {
                Text("隐私")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            guard !keyLoaded else { return }
            apiKey = AIKeyStore.read() ?? ""
            keyLoaded = true
        }
        .onDisappear(perform: saveKey)
    }

    @ViewBuilder
    private var testStatus: some View {
        switch test {
        case .idle:
            EmptyView()
        case .testing:
            ProgressView()
                .controlSize(.small)
        case .succeeded(let reply):
            Label("连接正常：\(reply)", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .lineLimit(1)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .lineLimit(3)
        }
    }

    private func saveKey() {
        guard keyLoaded else { return }
        AIKeyStore.save(apiKey)
    }

    private func runTest() {
        saveKey()
        test = .testing
        let ai = store.settings.ai
        let configuration = AIClient.Configuration(baseURL: ai.baseURL, apiKey: apiKey, model: ai.model)
        Task {
            do {
                let reply = try await AIClient.complete(configuration, messages: [.user("只回复「好」这一个字。")])
                test = .succeeded(String(reply.trimmingCharacters(in: .whitespacesAndNewlines).prefix(30)))
            } catch {
                test = .failed(AIClient.describe(error))
            }
        }
    }
}
