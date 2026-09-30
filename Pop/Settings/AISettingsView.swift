import SwiftUI

/// 「设置 → AI」：接口地址、API Key、模型，以及测试连接。
struct AISettingsView: View {
    @EnvironmentObject private var store: SettingsStore
    @State private var apiKey = ""
    @State private var keyLoaded = false
    @State private var test: TestState = .idle
    /// 系统内置的模型：不支持的系统上不显示这个选项
    @State private var onDevice = OnDeviceModel.status

    enum TestState: Equatable {
        case idle
        case testing
        case succeeded(String)
        case failed(String)
    }

    var body: some View {
        Form {
            if onDevice != .unsupported {
                Section {
                    Picker("使用", selection: store.binding(\.ai.provider)) {
                        ForEach(AIProvider.allCases) { provider in
                            Text(provider.title).tag(provider)
                        }
                    }
                    .pickerStyle(.segmented)
                    if store.settings.ai.provider == .onDevice, case .unavailable(let reason) = onDevice {
                        Label(reason, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                } header: {
                    Text("模型")
                } footer: {
                    Text("系统内置的模型是 macOS 自带的 Apple 智能，在这台 Mac 上处理，不联网，也不用填接口；能处理的内容比较短，长的只取前面一部分。它用不了的时候自动改用下面填的接口。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                TextField("接口地址", text: store.binding(\.ai.baseURL), prompt: Text("https://api.openai.com/v1"))
                SecureField("API Key", text: $apiKey, prompt: Text("本机运行的服务可以不填"))
                    .onSubmit(saveKey)
                TextField("模型", text: store.binding(\.ai.model), prompt: Text("比如 gpt-4o-mini"))
                HStack(spacing: 8) {
                    Button("保存并测试", action: runTest)
                        .disabled(test == .testing || AIService.backend(for: store.settings.ai, onDevice: onDevice) == .unavailable)
                    testStatus
                    Spacer()
                }
            } header: {
                Text("AI 接口")
            } footer: {
                Text("填写兼容 OpenAI Chat Completions 的接口，地址写到 /v1 为止；在本机运行的模型服务也可以（比如 `http://localhost:11434/v1`）。接口地址和模型会随设置通过 iCloud 同步，API Key 只保存在这台 Mac 的钥匙串里。")
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
        .onChange(of: store.settings.ai.isConfigured) { _, configured in
            // 看不到上面的选项时（不支持系统内置的模型），填好接口就是要用接口
            if configured, onDevice == .unsupported, store.settings.ai.provider != .custom {
                store.update { $0.ai.provider = .custom }
            }
        }
        .onAppear {
            onDevice = OnDeviceModel.status
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
        let key = apiKey
        let status = onDevice
        Task {
            do {
                let reply = try await AIService.complete([.user("只回复「好」这一个字。")], settings: ai, onDevice: status, key: { key })
                test = .succeeded(String(reply.trimmingCharacters(in: .whitespacesAndNewlines).prefix(30)))
            } catch {
                test = .failed(AIClient.describe(error))
            }
        }
    }
}
