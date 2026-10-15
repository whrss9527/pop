import Foundation
import OSLog

/// 仅启动测试要求时记录阶段，正常运行不做计时或日志写入。
@MainActor
enum StartupTrace {
    private static let enabled = ProcessInfo.processInfo.environment["POP_STARTUP_TRACE"] == "1"
    private static let log = Logger(subsystem: "io.github.whrss9527.pop", category: "startup")

    struct Span {
        let phase: String
        let start: UInt64
    }

    static func begin(_ phase: String) -> Span? {
        guard enabled else { return nil }
        let span = Span(phase: phase, start: DispatchTime.now().uptimeNanoseconds)
        log.notice("begin \(phase, privacy: .public) uptime_ns=\(span.start, privacy: .public)")
        return span
    }

    static func end(_ span: Span?) {
        guard let span else { return }
        let now = DispatchTime.now().uptimeNanoseconds
        let milliseconds = Double(now &- span.start) / 1_000_000
        log.notice("end \(span.phase, privacy: .public) uptime_ns=\(now, privacy: .public) elapsed_ms=\(milliseconds, privacy: .public)")
    }

    static func measure<T>(_ phase: String, _ operation: () -> T) -> T {
        let span = begin(phase)
        defer { end(span) }
        return operation()
    }
}
