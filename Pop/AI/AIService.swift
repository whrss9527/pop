import Foundation

/// AI 功能用哪个模型：系统内置的（macOS 26 上能用时），或者「设置 → AI」里填的接口。
/// AI 卡片、AI 指令插件和设置里的测试都从这里发请求。
enum AIService {
    enum Backend: Equatable {
        case onDevice
        case custom
        /// 两个都用不了
        case unavailable
    }

    /// 选项回退：选了系统内置、但这台 Mac 现在用不了时，改用填好的接口；选了自己的接口就只用接口
    static func backend(for settings: AISettings, onDevice: OnDeviceModel.Status) -> Backend {
        switch settings.provider {
        case .onDevice:
            if onDevice == .available {
                return .onDevice
            }
            return settings.isConfigured ? .custom : .unavailable
        case .custom:
            return settings.isConfigured ? .custom : .unavailable
        }
    }

    static func backend(for settings: AISettings) -> Backend {
        backend(for: settings, onDevice: OnDeviceModel.status)
    }

    /// 没法用时给用户看的说明
    static func unavailableMessage(for settings: AISettings, onDevice: OnDeviceModel.Status) -> String {
        if settings.provider == .onDevice, case .unavailable(let reason) = onDevice {
            return String(localized: "系统内置的模型现在用不了：\(reason)。也可以在「设置 → AI」里改用自己填的接口。")
        }
        return AIClient.describe(AIClient.Failure.notConfigured)
    }

    /// 流式产出回答；key 只在用接口时读（读钥匙串可能弹窗，放在后台读）
    static func stream(_ messages: [AIClient.Message], settings: AISettings, onDevice: OnDeviceModel.Status = OnDeviceModel.status,
                       key: @escaping () -> String? = AIKeyStore.read) async throws -> AsyncThrowingStream<String, Error> {
        switch backend(for: settings, onDevice: onDevice) {
        case .onDevice:
            return OnDeviceModel.stream(messages)
        case .custom:
            let apiKey = await runInBackground { key() ?? "" }
            let configuration = AIClient.Configuration(baseURL: settings.baseURL, apiKey: apiKey, model: settings.model)
            return AIClient.stream(try AIClient.makeRequest(configuration, messages: messages))
        case .unavailable:
            throw Unavailable(message: unavailableMessage(for: settings, onDevice: onDevice))
        }
    }

    /// 一次拿到完整的回答
    static func complete(_ messages: [AIClient.Message], settings: AISettings, onDevice: OnDeviceModel.Status = OnDeviceModel.status,
                         key: @escaping () -> String? = AIKeyStore.read) async throws -> String {
        var result = ""
        for try await piece in try await stream(messages, settings: settings, onDevice: onDevice, key: key) {
            result += piece
        }
        return result
    }

    struct Unavailable: LocalizedError, Equatable {
        let message: String

        var errorDescription: String? { message }
    }
}
