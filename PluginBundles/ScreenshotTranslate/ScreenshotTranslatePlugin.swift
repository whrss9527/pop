import AppKit
@testable import Pop

/// 插件包「截图翻译」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopScreenshotTranslateEntry)
final class ScreenshotTranslateEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [ScreenshotTranslatePlugin()]
    }
}

struct ScreenshotTranslatePlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.screenshotTranslate, name: String(localized: "截图翻译"), symbol: "translate",
                          summary: String(localized: "框选屏幕上的一块区域，识别里面的文字并翻译（离线）"), accepts: [], hidesOverlay: true)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        switch await ScreenCapture.recognizeRegion() {
        case .cancelled:
            return .done(toast: nil)
        case .failed(let message):
            return .failure(message)
        case .text(let text):
            // 识别结果按屏幕上的行断开，先接成段落再翻译，译文才通顺
            let paragraphs = TextCleanup.joinLines(text) ?? text
            return .translate(text: paragraphs, language: ContentClassifier.dominantLanguage(paragraphs))
        }
    }
}
