import AppKit
@testable import Pop

/// 插件包「滚动截图」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopScrollCaptureEntry)
final class ScrollCaptureEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [ScrollCapturePlugin()]
    }

    @MainActor static func willUninstall() {
        if ScrollCapture.shared.isCapturing {
            ScrollCapture.shared.cancel()
        }
    }
}

struct ScrollCapturePlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.scrollCapture, name: String(localized: "滚动截图"), symbol: "scroll",
                          summary: String(localized: "框选一块区域，一边往下滚动一边截，拼成一张长图；网页、聊天记录、长文档都能截全，还能接着识别文字。正在截的时候再用一次就是完成"),
                          accepts: [], hidesOverlay: true)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        let capture = ScrollCapture.shared
        if capture.isCapturing {
            capture.finish()
            return .done(toast: nil)
        }
        guard CGPreflightScreenCaptureAccess() else {
            // 第一次会弹出系统的授权提示
            _ = CGRequestScreenCaptureAccess()
            return .failure(ScreenRecording.permissionHint)
        }
        guard let selection = await RegionPicker.pick(for: .scrollCapture) else { return .done(toast: nil) }
        do {
            try await capture.start(selection)
            return .done(toast: nil)
        } catch {
            return .failure((error as? ScrollCapture.Failure)?.message ?? error.localizedDescription)
        }
    }
}
