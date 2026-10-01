import AppKit
@testable import Pop

/// 插件包「对比图片」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopCompareImagesEntry)
final class CompareImagesEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [CompareImagesPlugin()]
    }

    @MainActor static func didLoad(_ host: PluginHost.Registrar) {
        // CI 截图：示例截图改了三处当作新的一张，看差异
        host.addDemoScene(PluginHost.DemoScene(name: "compareImages", after: "cropImage", order: 1, delay: 1.4, hold: 0, show: { demo in
            guard let sample = OverlayDemo.sampleScreenshot(), let changed = CompareImagesPlugin.demoChanged(sample.image),
                  let prepared = try? ImageDiff.prepare(sample.image, changed) else { return nil }
            let outcome = await runInBackground { ImageDiff.outcome(prepared, ignoringSubtle: false) }
            let model = ImageCompareModel(prepared: prepared, outcome: outcome, firstName: "设置页 旧.png", secondName: "设置页 新.png",
                                          mode: .difference, ignoringSubtle: false)
            demo.overlay.showCard(ImageCompareView(model: model, onCopy: {}, onSave: {}, onPin: {}, onClose: {}), anchor: demo.center)
            return demo.cardRegion
        }))
    }
}

struct CompareImagesPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.compareImages, name: String(localized: "对比图片"), symbol: "square.split.2x1",
                          summary: String(localized: "对比选中的两张图片：并排、滑动分界线、半透明叠加，或者把不一样的像素标红、框出几处不同；改版前后的截图、设计稿和实现对照都用得上"),
                          accepts: [.files], check: .custom(CustomContentCheck("twoImageFiles") { subject in
                              // 圆盘按选中文件的路径（一行一个）检查
                              let paths = subject.components(separatedBy: "\n").filter { !$0.isEmpty }
                              return paths.count == 2 && paths.allSatisfy { ContentClassifier.isImageFile(URL(fileURLWithPath: $0)) }
                          }))

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard content.files.count == 2, content.files.allSatisfy(ContentClassifier.isImageFile) else {
            return .failure(String(localized: "选中两张图片才能对比"))
        }
        let (older, newer) = Self.ordered(content.files[0], content.files[1])
        let ignoring = ImageCompareModel.savedIgnoringSubtle
        let loaded: Result<(ImageDiff.Prepared, ImageDiff.Outcome), ImageDiff.Failure> = await runInBackground {
            do {
                let prepared = try ImageDiff.prepare(older, newer)
                return .success((prepared, ImageDiff.outcome(prepared, ignoringSubtle: ignoring)))
            } catch let failure as ImageDiff.Failure {
                return .failure(failure)
            } catch {
                return .failure(ImageDiff.Failure(message: error.localizedDescription))
            }
        }
        switch loaded {
        case .failure(let failure):
            return .failure(failure.message)
        case .success(let (prepared, outcome)):
            if outcome.isIdentical, prepared.canvas.alignment == .same, !ignoring {
                return .done(toast: String(localized: "两张图一模一样"))
            }
            return .present(PluginPresentation { session in
                let model = ImageCompareModel(prepared: prepared, outcome: outcome,
                                              firstName: older.lastPathComponent, secondName: newer.lastPathComponent)
                session.showCard(ImageCompareView(model: model,
                                                  onCopy: { Self.export(model, session: session) { .copyImage($0) } },
                                                  onSave: { Self.export(model, session: session) { .saveImage($0, name: ImageFiles.timestampedName(String(localized: "Pop 对比图"))) } },
                                                  onPin: { Self.export(model, session: session) { .pinImage($0) } },
                                                  onClose: { session.end() }))
            })
        }
    }

    /// 按修改时间排：旧的在前
    static func ordered(_ first: URL, _ second: URL) -> (old: URL, new: URL) {
        func modified(_ url: URL) -> Date {
            (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        }
        return modified(second) < modified(first) ? (second, first) : (first, second)
    }

    /// 按原图大小画好当前看到的样子，再复制、存储或者贴到屏幕
    @MainActor static func export(_ model: ImageCompareModel, session: PluginSession, action: @escaping (Data) -> CardAction) {
        Task { @MainActor in
            guard let png = await model.renderPNG() else {
                session.fail(String(localized: "没能画出这张图"))
                return
            }
            session.perform(action(png))
        }
    }

    /// 演示用的「新」截图：在示例截图上改三处（登录设备数、按钮颜色、多一个提示）
    static func demoChanged(_ image: CGImage) -> CGImage? {
        let width = image.width
        let height = image.height
        // 示例截图是 480×300 点，按屏幕倍率画的
        let scale = CGFloat(width) / 480
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        // 换成「点、左上角为原点」的坐标
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        func text(_ string: String, at point: CGPoint, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor) {
            NSAttributedString(string: string, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight),
                                                            .foregroundColor: color]).draw(at: point)
        }
        // 登录设备从 3 台变成 4 台
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 60, y: 150, width: 140, height: 22))
        text("登录设备：4 台", at: CGPoint(x: 64, y: 154), size: 13, color: .darkGray)
        // 按钮换成绿色
        context.setFillColor(NSColor(srgbRed: 0.2, green: 0.7, blue: 0.35, alpha: 1).cgColor)
        context.addPath(CGPath(roundedRect: CGRect(x: 300, y: 204, width: 116, height: 36), cornerWidth: 8, cornerHeight: 8, transform: nil))
        context.fillPath()
        text("保存更改", at: CGPoint(x: 330, y: 213), size: 14, weight: .medium, color: .white)
        // 标题旁边多一个「新」
        context.setFillColor(NSColor(srgbRed: 1, green: 0.23, blue: 0.19, alpha: 1).cgColor)
        context.addPath(CGPath(roundedRect: CGRect(x: 152, y: 62, width: 30, height: 18), cornerWidth: 9, cornerHeight: 9, transform: nil))
        context.fillPath()
        text("新", at: CGPoint(x: 160, y: 63), size: 11, weight: .semibold, color: .white)
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }
}
