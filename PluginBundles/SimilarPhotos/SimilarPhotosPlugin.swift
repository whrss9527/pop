import AppKit
@testable import Pop

/// 插件包「相似照片」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopSimilarPhotosEntry)
final class SimilarPhotosEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [SimilarPhotosPlugin()]
    }

    @MainActor static func didLoad(_ host: PluginHost.Registrar) {
        // CI 截图：几组画出来的示例照片（不碰真的文件）
        host.addDemoScene(PluginHost.DemoScene(name: "similarPhotos", after: "pdfPages", order: 6, delay: 1.4, hold: 0, show: { demo in
            let (photos, thumbnails) = SimilarPhotosPlugin.demo()
            let model = SimilarPhotosModel(title: String(localized: "照片"), photos: photos, sensitivity: .normal, recycle: { _ in [] })
            model.setThumbnails(thumbnails)
            demo.overlay.showCard(SimilarPhotosView(model: model, onReveal: { _ in }, onOpenTrash: {}, onClose: {}), anchor: demo.center)
            return demo.cardRegion
        }))
    }
}

struct SimilarPhotosPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.similarPhotos, name: String(localized: "相似照片"), symbol: "photo.stack",
                          summary: String(localized: "在选中的文件夹（或者几张图片）里找出连拍、重复存的、改过大小的相似照片，每组留最清楚的一张，其余的移到废纸篓"),
                          accepts: [.files], check: .custom(CustomContentCheck("similarPhotos") { subject in
                              let paths = subject.split(separator: "\n").map(String.init)
                              return paths.contains(where: FolderTree.isFolder)
                                  || paths.filter { PhotoSimilarity.isImage(URL(fileURLWithPath: $0)) }.count >= 2
                          }))

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        let folders = content.files.filter { FolderTree.isFolder($0.path(percentEncoded: false)) }
        let images = content.files.filter(PhotoSimilarity.isImage)
        guard !folders.isEmpty || images.count >= 2 else {
            return .failure(String(localized: "选中一个文件夹，或者至少两张图片"))
        }
        let title = folders.count == 1 && images.isEmpty ? folders[0].lastPathComponent : String(localized: "\(content.files.count) 项")
        return .present(PluginPresentation { session in
            let model = SimilarPhotosModel(title: title, recycle: { await Self.recycle($0) })
            session.showCard(SimilarPhotosView(model: model,
                                               onReveal: { NSWorkspace.shared.activateFileViewerSelecting([$0]) },
                                               onOpenTrash: {
                                                   if let trash = FileManager.default.urls(for: .trashDirectory, in: .userDomainMask).first {
                                                       NSWorkspace.shared.open(trash)
                                                   }
                                                   session.end()
                                               },
                                               onClose: { session.end() }))
            model.scan(folders + images)
        })
    }

    /// 移到废纸篓（和在访达里删除一样，可以「放回原处」），返回移走了的
    @MainActor static func recycle(_ urls: [URL]) async -> [URL] {
        await withCheckedContinuation { continuation in
            NSWorkspace.shared.recycle(urls) { trashed, _ in
                continuation.resume(returning: Array(trashed.keys))
            }
        }
    }

    /// 演示用：两组画出来的照片（傍晚的海边连拍三张、一张猫的照片和它缩小的一份），还有一张不像的
    static func demo() -> ([PhotoSimilarity.Photo], [URL: CGImage]) {
        let folder = URL(fileURLWithPath: "/Users/Shared/照片", isDirectory: true)
        var photos: [PhotoSimilarity.Photo] = []
        var thumbnails: [URL: CGImage] = [:]
        func add(_ name: String, _ image: CGImage?, width: Int, height: Int, bytes: Int64, sharpness: Double) {
            guard let image else { return }
            let url = folder.appending(path: name)
            photos.append(PhotoSimilarity.Photo(url: url, fingerprint: PhotoSimilarity.fingerprint(of: image), width: width, height: height,
                                                bytes: bytes, modified: nil, sharpness: sharpness))
            thumbnails[url] = image
        }
        add("IMG_2041.HEIC", scene(sun: 0.62, shift: 0), width: 4032, height: 3024, bytes: 2_400_000, sharpness: 820)
        add("IMG_2042.HEIC", scene(sun: 0.6, shift: 2), width: 4032, height: 3024, bytes: 2_300_000, sharpness: 410)
        add("IMG_2043.HEIC", scene(sun: 0.58, shift: 4), width: 4032, height: 3024, bytes: 2_350_000, sharpness: 640)
        add("猫.jpg", cat(), width: 3000, height: 3000, bytes: 1_800_000, sharpness: 500)
        add("猫 小.jpg", cat(), width: 1080, height: 1080, bytes: 240_000, sharpness: 500)
        add("文档扫描.png", stripes(), width: 2480, height: 3508, bytes: 900_000, sharpness: 900)
        return (photos, thumbnails)
    }

    private static func canvas(_ draw: (CGContext) -> Void) -> CGImage? {
        guard let context = CGContext(data: nil, width: 160, height: 160, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        draw(context)
        return context.makeImage()
    }

    /// 傍晚的海边：天空渐变、太阳、海
    private static func scene(sun: CGFloat, shift: CGFloat) -> CGImage? {
        canvas { context in
            let colors = [CGColor(srgbRed: 1, green: 0.7, blue: 0.42, alpha: 1), CGColor(srgbRed: 0.48, green: 0.55, blue: 1, alpha: 1)]
            if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: [0, 1]) {
                context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 160), end: CGPoint(x: 0, y: 60), options: [.drawsAfterEndLocation])
            }
            context.setFillColor(CGColor(srgbRed: 1, green: 0.95, blue: 0.77, alpha: 1))
            context.fillEllipse(in: CGRect(x: 70 + shift, y: 160 * sun, width: 30, height: 30))
            context.setFillColor(CGColor(srgbRed: 0.16, green: 0.27, blue: 0.62, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 160, height: 60))
        }
    }

    /// 一只橘猫：圆脸和两只耳朵
    private static func cat() -> CGImage? {
        canvas { context in
            context.setFillColor(CGColor(srgbRed: 0.93, green: 0.9, blue: 0.84, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 160, height: 160))
            context.setFillColor(CGColor(srgbRed: 0.95, green: 0.6, blue: 0.25, alpha: 1))
            context.fillEllipse(in: CGRect(x: 35, y: 25, width: 90, height: 85))
            for x: CGFloat in [42, 92] {
                context.move(to: CGPoint(x: x, y: 95))
                context.addLine(to: CGPoint(x: x + 13, y: 135))
                context.addLine(to: CGPoint(x: x + 26, y: 95))
                context.fillPath()
            }
            context.setFillColor(CGColor(gray: 0.15, alpha: 1))
            context.fillEllipse(in: CGRect(x: 60, y: 70, width: 9, height: 12))
            context.fillEllipse(in: CGRect(x: 91, y: 70, width: 9, height: 12))
        }
    }

    /// 文档扫描：白底上几行字
    private static func stripes() -> CGImage? {
        canvas { context in
            context.setFillColor(CGColor(gray: 0.98, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 160, height: 160))
            context.setFillColor(CGColor(gray: 0.3, alpha: 1))
            for row in 0..<9 {
                context.fill(CGRect(x: 20, y: 20 + row * 14, width: row % 3 == 2 ? 70 : 120, height: 6))
            }
        }
    }
}
