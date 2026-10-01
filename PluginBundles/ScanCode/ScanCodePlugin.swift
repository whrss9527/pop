import AppKit
@testable import Pop

/// 插件包「扫码」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopScanCodeEntry)
final class ScanCodeEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [ScanCodePlugin()]
    }
}

struct ScanCodePlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.scanCode, name: String(localized: "扫码"), symbol: "qrcode.viewfinder",
                          summary: String(localized: "框选屏幕上的二维码或条形码，识别里面的内容；链接可以直接打开，Wi-Fi 二维码列出密码"),
                          accepts: [], hidesOverlay: true)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        switch await ScreenCapture.selectRegion() {
        case .cancelled:
            return .done(toast: nil)
        case .failed(let message):
            return .failure(message)
        case .captured(let capture):
            let image = capture.image
            let messages = await runInBackground { QRCode.decode(image) }
            guard !messages.isEmpty else {
                return .failure(String(localized: "没有识别到二维码或条形码。框选时把整个码都框进去；如果框到的只有桌面背景，请在「系统设置 → 隐私与安全性 → 录屏与系统录音」里允许 Pop。"))
            }
            return .card(QRCode.card(for: messages))
        }
    }
}
