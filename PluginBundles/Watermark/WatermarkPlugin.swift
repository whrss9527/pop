import AppKit
@testable import Pop

/// 插件包「加水印」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopWatermarkEntry)
final class WatermarkEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [WatermarkPlugin()]
    }

    @MainActor static func didLoad(_ host: PluginHost.Registrar) {
        // CI 截图：示例截图上铺一层「仅供办理业务使用」
        host.addDemoScene(PluginHost.DemoScene(name: "watermark", after: "toolbar", delay: 0.6, hold: 0, show: { demo in
            guard let capture = OverlayDemo.sampleScreenshot() else { return nil }
            let image = FileManager.default.temporaryDirectory.appending(path: "pop-demo/证件照片.png")
            try? FileManager.default.createDirectory(at: image.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard (try? capture.png.write(to: image)) != nil else { return nil }
            let watermark = WatermarkModel(files: [image], text: ImageWatermark.defaultText, opacity: 0.35)
            demo.overlay.showCard(WatermarkView(model: watermark, onApply: {}, onClose: {}), anchor: demo.center)
            return demo.cardRegion
        }))
    }
}

struct WatermarkPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.watermark, name: String(localized: "加水印"), symbol: "signature",
                          summary: String(localized: "给选中的图片或 PDF 斜着铺满一层半透明的文字（比如「仅供办理业务使用」），另存一份放在原文件旁边"),
                          accepts: [.files], pattern: #"(?im)\.(pdf|jpe?g|png|heic|heif|tiff?|gif|bmp|webp)$"#)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        let files = Self.files(in: content)
        guard !files.isEmpty else { return .failure(String(localized: "没有选中图片或 PDF")) }
        return .present(PluginPresentation { session in
            // 改文字和浓淡时看预览，确认后每张图另存一份
            let model = WatermarkModel(files: files)
            session.showCard(WatermarkView(model: model,
                                           onApply: { Self.apply(model, session: session) },
                                           onClose: { session.end() }))
        })
    }

    /// 选中的文件里能加水印的：图片和 PDF
    static func files(in content: ClassifiedContent) -> [URL] {
        content.files.filter { ContentClassifier.isImageFile($0) || ImageWatermark.isPDF($0) }
    }

    /// 每个文件另存一份加了水印的，好了在访达里选中
    @MainActor static func apply(_ model: WatermarkModel, session: PluginSession) {
        let files = model.files
        let text = model.text
        let opacity = model.opacity
        let hasPDF = model.hasPDF
        model.remember()
        session.end()
        Task { @MainActor in
            let result = await runInBackground { () -> (outputs: [URL], failures: [String]) in
                var outputs: [URL] = []
                var failures: [String] = []
                for file in files {
                    do {
                        outputs.append(try ImageWatermark.watermark(file, text: text, opacity: opacity))
                    } catch {
                        failures.append((error as? ImageWatermark.Failure)?.message ?? error.localizedDescription)
                    }
                }
                return (outputs, failures)
            }
            if !result.outputs.isEmpty {
                NSWorkspace.shared.activateFileViewerSelecting(result.outputs)
            }
            let message: String
            if let failure = result.failures.first {
                message = result.outputs.isEmpty ? failure : String(localized: "加好了 \(result.outputs.count) 个，\(result.failures.count) 个失败：\(failure)")
            } else {
                message = hasPDF ? String(localized: "已给 \(result.outputs.count) 个文件加上水印") : String(localized: "已给 \(result.outputs.count) 张图片加上水印")
            }
            session.finish(toast: message)
        }
    }
}
