import CoreGraphics
import Foundation

/// CI 明确指定日志时记录窗口时序。主线程只取数字，编码和文件写入在独立队列。
@MainActor
final class OverlayDiagnostics {
    enum Event: String, Codable, Sendable {
        case presentBegin, hostingInstalled, initialFrameApplied, phaseShown, hidden
        case ghostCreated, ghostFinished, resizeRequested, resizeApplied
    }

    struct Entry: Codable, Sendable {
        let time: TimeInterval
        let sequence: Int
        let event: Event
        let window: Int
        let ghosts: Int
        let x: Double
        let y: Double
        let width: Double
        let height: Double
    }

    private let path: String?
    private let queue = DispatchQueue(label: "io.github.whrss9527.pop.overlay-diagnostics", qos: .utility)
    private var sequence = 0

    init(path: String? = OverlayDiagnostics.requestedPath(environment: ProcessInfo.processInfo.environment)) {
        self.path = path
    }

    nonisolated static func requestedPath(environment: [String: String]) -> String? {
        guard environment["POP_DEMO"] == "1",
              let path = environment["POP_OVERLAY_DIAGNOSTICS_LOG"], !path.isEmpty else { return nil }
        return path
    }

    func record(_ event: Event, window: Int, frame: @autoclosure () -> CGRect, ghosts: @autoclosure () -> Int) {
        guard let path else { return }
        let frame = frame()
        sequence += 1
        let entry = Entry(time: Date().timeIntervalSince1970, sequence: sequence, event: event,
                          window: window, ghosts: ghosts(), x: Double(frame.minX), y: Double(frame.minY),
                          width: Double(frame.width), height: Double(frame.height))
        queue.async {
            guard let data = try? JSONEncoder().encode(entry), let line = String(data: data, encoding: .utf8) else { return }
            LineLog.append(line, to: path)
        }
    }

    /// 测试等待已经提交的资料落盘；渲染流程不会等待这个队列。
    func flush() async {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume() }
        }
    }
}
