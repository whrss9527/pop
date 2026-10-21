import AppKit
import ApplicationServices
import OSLog

/// 按用户请求读取当前进程日志，不读取其他 App、文件日志或持久化设置。
enum SupportDiagnostics {
    @MainActor
    static func snapshot() -> SupportReport {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = ProcessInfo.processInfo.operatingSystemVersion
        var arm: Int32 = 0
        var size = MemoryLayout.size(ofValue: arm)
        let result = sysctlbyname("hw.optional.arm64", &arm, &size, nil, 0)
        return SupportReport(
            version: info["CFBundleShortVersionString"] as? String ?? "?",
            build: info["CFBundleVersion"] as? String ?? "?",
            channel: Distribution.isAppStore ? "App Store" : "GitHub",
            system: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
            chip: result == 0 ? (arm == 1 ? "Apple Silicon" : "Intel") : "unknown",
            accessibility: Permissions.isAccessibilityTrusted,
            screenRecording: CGPreflightScreenCaptureAccess()
        )
    }

    static func recentLogs() -> (lines: [String], available: Bool) {
        do {
            let store = try OSLogStore(scope: .currentProcessIdentifier)
            let position = store.position(date: Date().addingTimeInterval(-86400))
            let subsystem = Bundle.main.bundleIdentifier ?? "io.github.whrss9527.pop"
            let entries = try store.getEntries(at: position, matching: NSPredicate(format: "subsystem == %@", subsystem))
            var lines: [String] = []
            for case let entry as OSLogEntryLog in entries {
                // category 也不能直接信任：插件能自行写日志。
                let category = ["gesture", "plugins", "update", "startup"].contains(entry.category) ? entry.category : "other"
                let line = "\(entry.date.ISO8601Format()) [\(category)] \(SupportReport.safeLogMessage(entry.composedMessage))"
                if lines.count == 200 { lines.removeFirst() }
                lines.append(line)
            }
            return (lines, true)
        } catch {
            // 系统日志不可读时仍可复制基本诊断，不输出可能含用户路径的错误描述。
            return ([], false)
        }
    }
}
