import Foundation

/// 专用演示诊断的实验条件，普通启动和完整截图演示均保持原行为。
enum OverlayRenderProbe: String {
    case baseline
    case noGhost = "no-ghost"
    case legacyGlass = "legacy-glass"

    static func selected(in environment: [String: String]) -> Self? {
        guard environment["POP_DEMO"] == "1", environment["POP_RENDER_PROBE"] == "1" else { return nil }
        return Self(rawValue: environment["POP_RENDER_PROBE_VARIANT"] ?? "")
    }

    static let current = selected(in: ProcessInfo.processInfo.environment)
}
