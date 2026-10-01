import AppKit
@testable import Pop

/// 插件包「切分图片」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopSplitImageEntry)
final class SplitImageEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [SplitImagePlugin()]
    }

    @MainActor static func didLoad(_ host: PluginHost.Registrar) {
        // CI 截图：一张海边的照片切九宫格
        host.addDemoScene(PluginHost.DemoScene(name: "splitImage", after: "cropImage", order: 2, delay: 1.4, hold: 0, show: { demo in
            guard let photo = SplitImagePlugin.demoPhoto() else { return nil }
            let model = SplitImageModel(image: photo, name: "海边.jpg", focus: CGRect(x: 640, y: 180, width: 220, height: 220), layout: .nine)
            demo.overlay.showCard(SplitImageView(model: model, onSplit: {}, onClose: {}), anchor: demo.center)
            return demo.cardRegion
        }))
    }
}

struct SplitImagePlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.splitImage, name: String(localized: "切分图片"), symbol: "square.grid.3x3",
                          summary: String(localized: "把选中的图片切成九宫格、四宫格（对准画面里的主体裁成正方形）或者横着三张，长图切成几页；按发出去的顺序编号，存在原图旁边的文件夹里"),
                          accepts: [.imageFile])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let url = content.files.first(where: ContentClassifier.isImageFile) else {
            return .failure(String(localized: "没有选中图片"))
        }
        let loaded: Result<(image: CGImage, photo: Bool, focus: CGRect?), ImageSplitter.Failure> = await runInBackground {
            do {
                let (image, photo) = try ImageSplitter.load(url)
                return .success((image, photo, SmartCrop.focus(of: image)))
            } catch let failure as ImageSplitter.Failure {
                return .failure(failure)
            } catch {
                return .failure(ImageSplitter.Failure(message: error.localizedDescription))
            }
        }
        switch loaded {
        case .failure(let failure):
            return .failure(failure.message)
        case .success(let source):
            return .present(PluginPresentation { session in
                let model = SplitImageModel(image: source.image, name: url.lastPathComponent, focus: source.focus)
                session.showCard(SplitImageView(model: model,
                                                onSplit: { Self.split(model, photo: source.photo, original: url, session: session) },
                                                onClose: { session.end() }))
            })
        }
    }

    /// 按原图切好存进文件夹，在访达里选中这个文件夹
    @MainActor static func split(_ model: SplitImageModel, photo: Bool, original: URL, session: PluginSession) {
        let image = model.image
        let plan = model.plan
        let layout = model.layout
        model.remember()
        session.end()
        Task { @MainActor in
            let result: Result<URL, ImageSplitter.Failure> = await runInBackground {
                do {
                    return .success(try ImageSplitter.split(image, plan: plan, photo: photo, beside: original, layout: layout))
                } catch let failure as ImageSplitter.Failure {
                    return .failure(failure)
                } catch {
                    return .failure(ImageSplitter.Failure(message: error.localizedDescription))
                }
            }
            switch result {
            case .failure(let failure):
                session.finish(toast: failure.message)
            case .success(let folder):
                NSWorkspace.shared.activateFileViewerSelecting([folder])
                session.finish(toast: String(localized: "切好了 \(plan.tiles.count) 张，存在「\(folder.lastPathComponent)」"))
            }
        }
    }

    /// 演示用的照片：傍晚的海边，1200×900
    static func demoPhoto() -> CGImage? {
        let width = 1200
        let height = 900
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // CGContext 的原点在左下角：天空在上，海在下
        let sky = [CGColor(srgbRed: 1, green: 0.70, blue: 0.42, alpha: 1), CGColor(srgbRed: 1, green: 0.54, blue: 0.48, alpha: 1),
                   CGColor(srgbRed: 0.48, green: 0.55, blue: 1, alpha: 1)]
        if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: sky as CFArray, locations: [0, 0.55, 1]) {
            context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: CGFloat(height)), end: CGPoint(x: 0, y: 360), options: [.drawsAfterEndLocation])
        }
        context.setFillColor(CGColor(srgbRed: 1, green: 0.95, blue: 0.77, alpha: 1))
        context.fillEllipse(in: CGRect(x: 640, y: 900 - 400, width: 220, height: 220))
        let sea = [CGColor(srgbRed: 0.21, green: 0.33, blue: 0.79, alpha: 1), CGColor(srgbRed: 0.16, green: 0.25, blue: 0.56, alpha: 1)]
        if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: sea as CFArray, locations: [0, 1]) {
            context.saveGState()
            context.clip(to: CGRect(x: 0, y: 0, width: width, height: 360))
            context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 360), end: .zero, options: [])
            context.restoreGState()
        }
        // 海面上几道反光
        context.setFillColor(CGColor(srgbRed: 1, green: 0.93, blue: 0.7, alpha: 0.55))
        for (index, width) in [180, 140, 100, 60].enumerated() {
            context.fill(CGRect(x: 750 - width / 2, y: 330 - index * 40, width: width, height: 8))
        }
        return context.makeImage()
    }
}
