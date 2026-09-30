import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// macOS 26 自带的 Apple 智能模型：在这台 Mac 上处理，不联网，也不用填接口。
/// 用没有这个框架的 Xcode 编译，或者在更早的系统、不支持的 Mac 上运行时，当作不支持。
enum OnDeviceModel {
    /// 系统模型一次能处理的内容不多，选中的文字只取前面这么多字
    static let maxInputLength = 3000

    enum Status: Equatable {
        case available
        /// 系统或者这台 Mac 不支持：设置里不显示这个选项
        case unsupported
        /// 支持，但现在用不了（比如没打开 Apple 智能、模型还在下载），附上原因
        case unavailable(String)
    }

    enum Failure: LocalizedError, Equatable {
        case unsupported
        case generation(String)

        var errorDescription: String? {
            switch self {
            case .unsupported:
                return String(localized: "这台 Mac 上用不了系统内置的模型，可以在「设置 → AI」里改用自己填的接口。")
            case .generation(let message):
                return String(localized: "系统内置的模型出错了：\(message)")
            }
        }
    }

    static var status: Status {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let availability = SystemLanguageModel.default.availability
            if case .available = availability {
                return .available
            }
            if case .unavailable(.deviceNotEligible) = availability {
                return .unsupported
            }
            if case .unavailable(.appleIntelligenceNotEnabled) = availability {
                return .unavailable(String(localized: "要先在「系统设置 → Apple 智能与 Siri」里打开 Apple 智能"))
            }
            if case .unavailable(.modelNotReady) = availability {
                return .unavailable(String(localized: "系统模型还在下载，稍后再试"))
            }
            return .unavailable(String(localized: "系统模型现在用不了"))
        }
        #endif
        return .unsupported
    }

    /// 发给系统模型的一段话：指令和对话连在一起；太长的只取前面一部分
    static func prompt(from messages: [AIClient.Message], limit: Int = maxInputLength) -> (text: String, truncated: Bool) {
        let instructions = messages.filter { $0.role == "system" }.map(\.content)
        var request = messages.filter { $0.role != "system" }.map(\.content).joined(separator: "\n\n")
        let truncated = request.count > limit
        if truncated {
            request = String(request.prefix(limit))
        }
        return ((instructions + [request]).joined(separator: "\n\n"), truncated)
    }

    /// 流式产出新增的文字；取消迭代时生成也会停下
    static func stream(_ messages: [AIClient.Message]) -> AsyncThrowingStream<String, Error> {
        let request = prompt(from: messages)
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return AsyncThrowingStream { continuation in
                let task = Task {
                    do {
                        let session = LanguageModelSession()
                        var sent = ""
                        for try await snapshot in session.streamResponse(to: request.text) {
                            let text = snapshot.content
                            if text.hasPrefix(sent), text.count > sent.count {
                                continuation.yield(String(text.dropFirst(sent.count)))
                                sent = text
                            }
                        }
                        if request.truncated {
                            continuation.yield(String(localized: "\n\n（原文太长，只处理了前 \(OnDeviceModel.maxInputLength) 个字）"))
                        }
                        continuation.finish()
                    } catch is CancellationError {
                        continuation.finish(throwing: CancellationError())
                    } catch {
                        continuation.finish(throwing: Failure.generation(error.localizedDescription))
                    }
                }
                continuation.onTermination = { _ in
                    task.cancel()
                }
            }
        }
        #endif
        return AsyncThrowingStream { continuation in
            continuation.finish(throwing: Failure.unsupported)
        }
    }
}
