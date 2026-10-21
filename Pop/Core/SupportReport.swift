import Foundation

/// 只接受显式采集的诊断字段，不序列化设置、环境、钥匙串或剪贴板。
struct SupportReport: Sendable {
    let version: String
    let build: String
    let channel: String
    let system: String
    let chip: String
    let accessibility: Bool
    let screenRecording: Bool

    var feedbackURL: URL {
        var url = URLComponents(string: "https://github.com/whrss9527/pop/issues/new")!
        url.queryItems = [
            URLQueryItem(name: "template", value: "bug.yml"),
            URLQueryItem(name: "version", value: "Pop \(version) (\(build)), \(channel), macOS \(system)")
        ]
        return url.url!
    }

    func text(logs: [String], logsAvailable: Bool) -> String {
        [
            "Pop \(version) (\(build)) · \(channel)",
            "macOS \(system) · \(chip)",
            "Accessibility: \(accessibility ? "granted" : "missing")",
            "Screen Recording: \(screenRecording ? "granted" : "missing")",
            "Recent process logs (up to 200; last 24 hours; unrecognized content hidden):",
            logsAvailable ? (logs.isEmpty ? "No available entries." : logs.suffix(200).joined(separator: "\n")) : "Logs unavailable."
        ].joined(separator: "\n")
    }

    /// 默认隐藏正文，仅放行完全匹配的固定事件或数字。错误文本和插件输出可能包含密钥、路径或用户内容。
    static func safeLogMessage(_ message: String) -> String {
        let patterns = [
            #"\A鼠标手势取消：收起圆盘，不执行当前指向的功能\z"#,
            #"\A唤起：按下点 -?[0-9]+, -?[0-9]+\z"#,
            #"\Aloaded [0-9]+ plugins in [0-9]+(?:\.[0-9]+)? ms\z"#,
            #"\APop 已启动，版本 [0-9]+\.[0-9]+\.[0-9]+(?:-beta\.[0-9]+)?\z"#
        ]
        guard message.utf8.count <= 512,
              patterns.contains(where: { message.range(of: $0, options: .regularExpression) != nil }) else {
            return "[content hidden]"
        }
        return message
    }
}
