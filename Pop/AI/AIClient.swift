import Foundation

/// 调用兼容 OpenAI Chat Completions 接口的服务：拼请求、解析流式返回（SSE）。
/// 只在用户主动使用 AI 功能时才会把选中的文字发给设置里填写的服务。
enum AIClient {
    struct Message: Codable, Equatable {
        var role: String
        var content: String

        static func system(_ content: String) -> Message { Message(role: "system", content: content) }
        static func user(_ content: String) -> Message { Message(role: "user", content: content) }
    }

    struct Configuration: Equatable {
        var baseURL: String
        var apiKey: String
        var model: String
    }

    enum Failure: LocalizedError, Equatable {
        case notConfigured
        case invalidURL
        case http(status: Int, message: String)
        case emptyResponse

        var errorDescription: String? {
            switch self {
            case .notConfigured:
                return String(localized: "还没有设置 AI 接口，请在「设置 → AI」里填写接口地址和模型。")
            case .invalidURL:
                return String(localized: "接口地址无效，需要以 https:// 或 http:// 开头。")
            case .http(let status, let message):
                let hint: String
                switch status {
                case 401, 403: hint = String(localized: "API Key 不对或者没有权限")
                case 404: hint = String(localized: "接口地址或模型名称不对")
                case 429: hint = String(localized: "请求太频繁或者额度用完了")
                case 500...599: hint = String(localized: "服务暂时出错了")
                default: hint = String(localized: "请求失败")
                }
                return message.isEmpty ? String(localized: "\(hint)（\(status)）") : String(localized: "\(hint)（\(status)）：\(message)")
            case .emptyResponse:
                return String(localized: "服务没有返回内容。")
            }
        }
    }

    /// 接口地址到 /v1 为止（比如 https://api.openai.com/v1），也接受已经写到 /chat/completions 的完整地址。
    static func endpoint(_ baseURL: String) -> URL? {
        var base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") {
            base.removeLast()
        }
        if !base.hasSuffix("/chat/completions") {
            base += "/chat/completions"
        }
        guard let url = URL(string: base), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              url.host?.isEmpty == false else { return nil }
        return url
    }

    private struct RequestBody: Encodable {
        let model: String
        let messages: [Message]
        let stream: Bool
    }

    static func makeRequest(_ configuration: Configuration, messages: [Message], stream: Bool = true) throws -> URLRequest {
        let model = configuration.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty, !configuration.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Failure.notConfigured
        }
        guard let url = endpoint(configuration.baseURL) else { throw Failure.invalidURL }
        var request = URLRequest(url: url, timeoutInterval: 90)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(stream ? "text/event-stream" : "application/json", forHTTPHeaderField: "Accept")
        let key = configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder().encode(RequestBody(model: model, messages: messages, stream: stream))
        return request
    }

    // MARK: - 解析返回

    enum StreamEvent: Equatable {
        case delta(String)
        case done
    }

    private struct StreamChunk: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable {
                let content: String?
            }

            let delta: Delta?
        }

        let choices: [Choice]?
    }

    private struct Completion: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                let content: String?
            }

            let message: Message?
        }

        let choices: [Choice]?
    }

    private struct ErrorBody: Decodable {
        struct Detail: Decodable {
            let message: String?
        }

        let error: Detail?
        let message: String?
    }

    /// 流式返回的一行：`data: {...}` 里的 choices[0].delta.content；`data: [DONE]` 表示结束。
    /// 其他行（空行、注释、只有角色没有文字的片段）返回 nil。
    static func parseStreamLine(_ line: String) -> StreamEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("data:") else { return nil }
        let payload = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" {
            return .done
        }
        guard let chunk = try? JSONDecoder().decode(StreamChunk.self, from: Data(payload.utf8)),
              let content = chunk.choices?.first?.delta?.content, !content.isEmpty else { return nil }
        return .delta(content)
    }

    /// 不支持流式的服务一次返回完整结果
    static func parseCompletion(_ data: Data) -> String? {
        guard let completion = try? JSONDecoder().decode(Completion.self, from: data),
              let content = completion.choices?.first?.message?.content, !content.isEmpty else { return nil }
        return content
    }

    /// 出错时服务返回的说明：{"error": {"message": "..."}} 或 {"message": "..."}
    static func errorMessage(from data: Data) -> String {
        if let body = try? JSONDecoder().decode(ErrorBody.self, from: data),
           let message = body.error?.message ?? body.message, !message.isEmpty {
            return String(message.prefix(300))
        }
        return String(decoding: data.prefix(300), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - 请求

    /// 流式请求：每收到一段文字就产出一段。取消迭代时请求也会被取消。
    static func stream(_ request: URLRequest, session: URLSession = .shared) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await session.bytes(for: request)
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    guard (200..<300).contains(status) else {
                        let body = try await collect(bytes, limit: 64_000)
                        throw Failure.http(status: status, message: errorMessage(from: body))
                    }
                    if response.mimeType?.contains("event-stream") == true {
                        var received = false
                        for try await line in bytes.lines {
                            guard let event = parseStreamLine(line) else { continue }
                            // [DONE]：结束
                            guard case .delta(let text) = event else { break }
                            received = true
                            continuation.yield(text)
                        }
                        guard received else { throw Failure.emptyResponse }
                        continuation.finish()
                    } else {
                        let body = try await collect(bytes, limit: 4_000_000)
                        guard let text = parseCompletion(body) else {
                            throw Failure.emptyResponse
                        }
                        continuation.yield(text)
                        continuation.finish()
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    /// 一次拿到完整的回答（结果要复制、替换原文时用）
    static func complete(_ configuration: Configuration, messages: [Message], session: URLSession = .shared) async throws -> String {
        let request = try makeRequest(configuration, messages: messages)
        var result = ""
        for try await piece in stream(request, session: session) {
            result += piece
        }
        return result
    }

    /// 给用户看的错误说明
    static func describe(_ error: Error) -> String {
        if let failure = error as? Failure {
            return failure.errorDescription ?? String(localized: "请求失败")
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return String(localized: "网络连接断开了。")
            case .timedOut:
                return String(localized: "请求超时了，服务可能太忙，稍后再试。")
            case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                return String(localized: "连不上接口地址，请检查「设置 → AI」里的地址。")
            case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate:
                return String(localized: "和接口地址建立安全连接失败。")
            case .appTransportSecurityRequiresSecureConnection:
                return String(localized: "这个地址需要用 https://（只有本机和局域网的服务可以用 http://）。")
            default:
                break
            }
        }
        return error.localizedDescription
    }

    private static func collect(_ bytes: URLSession.AsyncBytes, limit: Int) async throws -> Data {
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            if data.count >= limit { break }
        }
        return data
    }
}
