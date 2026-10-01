import AppKit
@testable import Pop

/// 插件包「截图美化」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopBeautifyEntry)
final class BeautifyEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [BeautifyPlugin()]
    }

    @MainActor static func didLoad(_ host: PluginHost.Registrar) {
        // CI 截图：示例截图放在天蓝的背景上，中等留白，圆角加阴影
        host.addDemoScene(PluginHost.DemoScene(name: "beautify", after: "cropImage", delay: 1.4, hold: 0, show: { demo in
            guard let sample = OverlayDemo.sampleScreenshot() else { return nil }
            let model = BeautifyModel(image: sample.image, options: ScreenshotBeautifier.Options())
            await model.prepare()
            demo.overlay.showCard(BeautifyView(model: model, onCopy: {}, onSave: {}, onPin: {}, onClose: {}), anchor: demo.center)
            return demo.cardRegion
        }))
    }
}

struct BeautifyPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.beautify, name: String(localized: "截图美化"), symbol: "wand.and.stars",
                          summary: String(localized: "给截图加上渐变背景、留白、圆角和阴影，可以补成 1:1、4:3、16:9，发文章、做演示更好看；选中图片就用它，没选中就先框选屏幕上的一块"),
                          accepts: [], hidesOverlay: true, optionalContent: true)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        let image: CGImage
        if case .image(let data) = content.selection, let decoded = TextRecognizer.cgImage(from: data) {
            image = decoded
        } else if let url = content.files.first(where: ContentClassifier.isImageFile), let decoded = TextRecognizer.cgImage(contentsOf: url) {
            image = decoded
        } else {
            switch await ScreenCapture.selectRegion() {
            case .cancelled:
                return .done(toast: nil)
            case .failed(let message):
                return .failure(message)
            case .captured(let capture):
                image = capture.image
            }
        }
        return .present(PluginPresentation { session in
            let model = BeautifyModel(image: image)
            session.showCard(BeautifyView(model: model,
                                          onCopy: { Self.export(model, session: session) { .copyImage($0) } },
                                          onSave: { Self.export(model, session: session) { .saveImage($0, name: ImageFiles.timestampedName(String(localized: "Pop 截图"))) } },
                                          onPin: { Self.export(model, session: session) { .pinImage($0) } },
                                          onClose: { session.end() }))
        })
    }

    /// 按原图大小画好，再复制、存储或者贴到屏幕
    @MainActor static func export(_ model: BeautifyModel, session: PluginSession, action: @escaping (Data) -> CardAction) {
        Task { @MainActor in
            guard let png = await model.renderPNG() else {
                session.fail(String(localized: "没能画出这张图"))
                return
            }
            session.perform(action(png))
        }
    }
}
