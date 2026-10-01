import AppKit
@testable import Pop

/// 插件包「生成图标」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopAppIconEntry)
final class AppIconEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [AppIconPlugin()]
    }

    @MainActor static func didLoad(_ host: PluginHost.Registrar) {
        // CI 截图：一个透明底的示例标志，圆角方块、留窄边
        host.addDemoScene(PluginHost.DemoScene(name: "appIcon", after: "cropImage", order: 3, delay: 1.4, hold: 0, show: { demo in
            guard let logo = AppIconPlugin.demoLogo() else { return nil }
            var options = IconMaker.Options()
            options.margin = .narrow
            let model = AppIconModel(source: IconMaker.prepare(logo), name: "Logo.png", options: options)
            demo.overlay.showCard(AppIconView(model: model, onMake: {}, onClose: {}), anchor: demo.center)
            return demo.cardRegion
        }))
    }
}

struct AppIconPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.appIcon, name: String(localized: "生成图标"), symbol: "app.dashed",
                          summary: String(localized: "用选中的图片生成 App 图标：macOS 的 .icns 和 Xcode 用的图标集（圆角方块，和系统 App 的图标一样大）、iOS 的 1024 图标，还有网站的 favicon，存在原图旁边的文件夹里"),
                          accepts: [.imageFile])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let url = content.files.first(where: ContentClassifier.isImageFile) else {
            return .failure(String(localized: "没有选中图片"))
        }
        let loaded: Result<IconMaker.Source, IconMaker.Failure> = await runInBackground {
            do {
                return .success(try IconMaker.load(url))
            } catch let failure as IconMaker.Failure {
                return .failure(failure)
            } catch {
                return .failure(IconMaker.Failure(message: error.localizedDescription))
            }
        }
        switch loaded {
        case .failure(let failure):
            return .failure(failure.message)
        case .success(let source):
            return .present(PluginPresentation { session in
                let model = AppIconModel(source: source, name: url.lastPathComponent)
                session.showCard(AppIconView(model: model,
                                             onMake: { Self.make(model, original: url, session: session) },
                                             onClose: { session.end() }))
            })
        }
    }

    /// 在后台画好、写进文件夹，在访达里选中这个文件夹
    @MainActor static func make(_ model: AppIconModel, original: URL, session: PluginSession) {
        let source = model.source
        let options = model.options
        model.remember()
        session.end()
        Task { @MainActor in
            let result: Result<IconMaker.Output, IconMaker.Failure> = await runInBackground {
                do {
                    return .success(try IconMaker.write(source, options: options, beside: original))
                } catch let failure as IconMaker.Failure {
                    return .failure(failure)
                } catch {
                    return .failure(IconMaker.Failure(message: error.localizedDescription))
                }
            }
            switch result {
            case .failure(let failure):
                session.finish(toast: failure.message)
            case .success(let output):
                NSWorkspace.shared.activateFileViewerSelecting([output.folder])
                session.finish(toast: String(localized: "生成了 \(output.files) 个文件，存在「\(output.folder.lastPathComponent)」"))
            }
        }
    }

    /// 演示用的标志：透明底上一个渐变的圆，里面一个白色的对话气泡，1024 见方
    static func demoLogo() -> CGImage? {
        let side = 1024
        guard let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.clear(CGRect(x: 0, y: 0, width: side, height: side))
        let circle = CGRect(x: 32, y: 32, width: 960, height: 960)
        context.saveGState()
        context.addEllipse(in: circle)
        context.clip()
        let colors = [CGColor(srgbRed: 0.35, green: 0.40, blue: 1, alpha: 1), CGColor(srgbRed: 1, green: 0.42, blue: 0.62, alpha: 1)]
        if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: [0, 1]) {
            context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: CGFloat(side)), end: CGPoint(x: CGFloat(side), y: 0), options: [])
        }
        context.restoreGState()
        // 气泡：圆角矩形加一个小尾巴
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.addPath(CGPath(roundedRect: CGRect(x: 262, y: 382, width: 500, height: 340), cornerWidth: 120, cornerHeight: 120, transform: nil))
        context.fillPath()
        context.move(to: CGPoint(x: 360, y: 400))
        context.addLine(to: CGPoint(x: 330, y: 290))
        context.addLine(to: CGPoint(x: 470, y: 392))
        context.closePath()
        context.fillPath()
        // 气泡里三个点
        context.setFillColor(CGColor(srgbRed: 0.55, green: 0.42, blue: 0.95, alpha: 1))
        for x in [382, 512, 642] {
            context.fillEllipse(in: CGRect(x: x - 38, y: 514, width: 76, height: 76))
        }
        return context.makeImage()
    }
}
