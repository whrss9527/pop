import AppKit
import ImageIO
import UniformTypeIdentifiers
import Vision

/// 证件照：抠出人像，换成白底、蓝底或红底，按人脸的位置裁成一寸、二寸。全在本机处理。
enum IDPhoto {
    enum Background: String, CaseIterable, Identifiable {
        case white
        case blue
        case red

        var id: String { rawValue }

        var title: String {
            switch self {
            case .white: return "白底"
            case .blue: return "蓝底"
            case .red: return "红底"
            }
        }

        /// 证件照常用的底色
        var rgb: (red: CGFloat, green: CGFloat, blue: CGFloat) {
            switch self {
            case .white: return (255, 255, 255)
            case .blue: return (67, 142, 219)
            case .red: return (255, 0, 0)
            }
        }

        var cgColor: CGColor {
            CGColor(srgbRed: rgb.red / 255, green: rgb.green / 255, blue: rgb.blue / 255, alpha: 1)
        }
    }

    enum Size: String, CaseIterable, Identifiable {
        case original
        case smallOneInch
        case oneInch
        case largeOneInch
        case smallTwoInch
        case twoInch

        var id: String { rawValue }

        var title: String {
            switch self {
            case .original: return "原尺寸"
            case .smallOneInch: return "小一寸"
            case .oneInch: return "一寸"
            case .largeOneInch: return "大一寸"
            case .smallTwoInch: return "小二寸"
            case .twoInch: return "二寸"
            }
        }

        /// 300 dpi 下的像素：小一寸 22×32、一寸 25×35、大一寸 33×48、小二寸 35×45、二寸 35×49 毫米
        var pixels: (width: Int, height: Int)? {
            switch self {
            case .original: return nil
            case .smallOneInch: return (260, 378)
            case .oneInch: return (295, 413)
            case .largeOneInch: return (390, 567)
            case .smallTwoInch: return (413, 531)
            case .twoInch: return (413, 579)
            }
        }
    }

    /// 存好的文件：照片，和（选了冲印排版时）6 寸相纸上排好的那张
    struct Saved: Equatable {
        var photo: URL
        var sheet: URL?
        /// 相纸上排了几张
        var copies: Int
    }

    /// 抠好的人像：和原图一样大、背景透明；face 是人脸的位置（像素，左上角为原点）
    struct Cutout {
        var image: CGImage
        var face: CGRect?
    }

    struct Failure: LocalizedError, Equatable {
        let message: String

        var errorDescription: String? { message }
    }

    static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "bmp", "webp"]

    static func isImage(_ url: URL) -> Bool {
        imageExtensions.contains(url.pathExtension.lowercased())
    }

    /// 用 Vision 抠出人像（保持原图大小），再找出最大的一张脸。比较慢，放在后台调用
    static func cutout(_ image: CGImage) throws -> Cutout {
        let mask = VNGenerateForegroundInstanceMaskRequest()
        let faces = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([mask, faces])
        } catch {
            throw Failure(message: "抠图失败：\(error.localizedDescription)")
        }
        guard let observation = mask.results?.first, !observation.allInstances.isEmpty else {
            throw Failure(message: "照片里没有找到人像")
        }
        let buffer: CVPixelBuffer
        do {
            buffer = try observation.generateMaskedImage(ofInstances: observation.allInstances, from: handler, croppedToInstancesExtent: false)
        } catch {
            throw Failure(message: "抠图失败：\(error.localizedDescription)")
        }
        let output = CIImage(cvPixelBuffer: buffer)
        guard let cutout = CIContext().createCGImage(output, from: output.extent) else {
            throw Failure(message: "无法生成抠好的图片")
        }
        let largest = (faces.results ?? []).max { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height }
        let face = largest.map { pixelRect($0.boundingBox, width: cutout.width, height: cutout.height) }
        return Cutout(image: cutout, face: face)
    }

    /// Vision 的归一化坐标（左下角为原点）换成像素坐标（左上角为原点）
    static func pixelRect(_ box: CGRect, width: Int, height: Int) -> CGRect {
        let w = CGFloat(width)
        let h = CGFloat(height)
        return CGRect(x: box.minX * w, y: (1 - box.maxY) * h, width: box.width * w, height: box.height * h)
    }

    /// 裁剪框（像素，左上角为原点），宽高比是 aspect（宽 ÷ 高）。
    /// 有人脸时：脸（眉毛到下巴）大约占照片高度的 46%，脸的中心在从上往下 47% 的地方，左右居中；
    /// 框超出照片时按比例缩小，尽量让脸留在原来的位置。没有人脸时取中间最大的一块。
    static func cropRect(imageSize: CGSize, face: CGRect?, aspect: CGFloat) -> CGRect {
        let imageWidth = imageSize.width
        let imageHeight = imageSize.height
        var width: CGFloat
        var height: CGFloat
        var centerX: CGFloat
        var faceY: CGFloat
        if let face, face.width > 0, face.height > 0 {
            height = face.height / 0.46
            width = height * aspect
            centerX = face.midX
            faceY = face.midY
        } else {
            if imageWidth / imageHeight > aspect {
                height = imageHeight
                width = height * aspect
            } else {
                width = imageWidth
                height = width / aspect
            }
            centerX = imageWidth / 2
            faceY = imageHeight / 2 - height / 2 + height * 0.47
        }
        let fit = min(1, imageWidth / width, imageHeight / height)
        width *= fit
        height *= fit
        let left = min(max(centerX - width / 2, 0), imageWidth - width)
        let top = min(max(faceY - height * 0.47, 0), imageHeight - height)
        return CGRect(x: left, y: top, width: width, height: height)
    }

    /// 铺上底色，按尺寸裁好。maxSide 限制输出的长边（预览时用小一点的）
    static func compose(_ cutout: Cutout, background: Background, size: Size, maxSide: Int? = nil) -> CGImage? {
        let imageWidth = cutout.image.width
        let imageHeight = cutout.image.height
        guard imageWidth > 0, imageHeight > 0 else { return nil }
        var outputWidth = imageWidth
        var outputHeight = imageHeight
        var crop = CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight)
        if let target = size.pixels {
            outputWidth = target.width
            outputHeight = target.height
            crop = cropRect(imageSize: CGSize(width: imageWidth, height: imageHeight), face: cutout.face,
                            aspect: CGFloat(target.width) / CGFloat(target.height))
        }
        if let maxSide, max(outputWidth, outputHeight) > maxSide {
            let shrink = CGFloat(maxSide) / CGFloat(max(outputWidth, outputHeight))
            outputWidth = max(Int((CGFloat(outputWidth) * shrink).rounded()), 1)
            outputHeight = max(Int((CGFloat(outputHeight) * shrink).rounded()), 1)
        }
        guard crop.width > 0, crop.height > 0,
              let context = CGContext(data: nil, width: outputWidth, height: outputHeight, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(background.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: outputWidth, height: outputHeight))
        context.interpolationQuality = .high
        // 让裁剪框正好铺满输出：Core Graphics 的原点在左下角
        let scaleX = CGFloat(outputWidth) / crop.width
        let scaleY = CGFloat(outputHeight) / crop.height
        context.draw(cutout.image, in: CGRect(x: -crop.minX * scaleX, y: -(CGFloat(imageHeight) - crop.maxY) * scaleY,
                                              width: CGFloat(imageWidth) * scaleX, height: CGFloat(imageHeight) * scaleY))
        return context.makeImage()
    }

    /// 另存成 JPEG 放在原图旁边：「原名 蓝底 一寸.jpg」（suffix 是再加在后面的，比如「排版」），带 300 dpi 的打印尺寸
    static func save(_ image: CGImage, beside url: URL, background: Background, size: Size, suffix: String? = nil) throws -> URL {
        var base = url.deletingPathExtension().lastPathComponent + " " + background.title + (size == .original ? "" : " " + size.title)
        if let suffix {
            base += " " + suffix
        }
        let output = FileNames.available(in: url.deletingLastPathComponent(), base: base, extension: "jpg")
        guard let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw Failure(message: "存不了「\(output.lastPathComponent)」")
        }
        var properties: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.95]
        if size != .original {
            properties[kCGImagePropertyDPIWidth] = 300
            properties[kCGImagePropertyDPIHeight] = 300
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw Failure(message: "存不了「\(output.lastPathComponent)」")
        }
        return output
    }

    /// 6 寸相纸（4×6 英寸，300 dpi 下 1800×1200）上排满这张照片：横放、竖放哪种排得多用哪种，
    /// 四周留 30 像素、照片之间留 24 像素，每张外面画一圈浅灰的裁切线。照片太大一张都放不下时返回 nil
    static func printSheet(_ photo: CGImage) -> (image: CGImage, copies: Int)? {
        let long = 1800
        let short = 1200
        let margin = 30
        let gap = 24
        func grid(width: Int, height: Int) -> (columns: Int, rows: Int) {
            (max((width - 2 * margin + gap) / (photo.width + gap), 0), max((height - 2 * margin + gap) / (photo.height + gap), 0))
        }
        let landscape = grid(width: long, height: short)
        let portrait = grid(width: short, height: long)
        let useLandscape = landscape.columns * landscape.rows >= portrait.columns * portrait.rows
        let width = useLandscape ? long : short
        let height = useLandscape ? short : long
        let layout = useLandscape ? landscape : portrait
        guard layout.columns * layout.rows > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let gridWidth = layout.columns * photo.width + (layout.columns - 1) * gap
        let gridHeight = layout.rows * photo.height + (layout.rows - 1) * gap
        let left = (width - gridWidth) / 2
        let bottom = (height - gridHeight) / 2
        context.setStrokeColor(CGColor(gray: 0.78, alpha: 1))
        context.setLineWidth(1)
        for row in 0..<layout.rows {
            for column in 0..<layout.columns {
                let rect = CGRect(x: left + column * (photo.width + gap), y: bottom + row * (photo.height + gap),
                                  width: photo.width, height: photo.height)
                context.draw(photo, in: rect)
                context.stroke(rect.insetBy(dx: -1.5, dy: -1.5))
            }
        }
        guard let image = context.makeImage() else { return nil }
        return (image, layout.columns * layout.rows)
    }
}

/// 证件照卡片：换底色、换尺寸时预览跟着变；抠图只做一次
@MainActor
final class IDPhotoModel: ObservableObject {
    let file: URL
    @Published var background: IDPhoto.Background {
        didSet {
            UserDefaults.standard.set(background.rawValue, forKey: Self.backgroundKey)
            render()
        }
    }
    @Published var size: IDPhoto.Size {
        didSet { render() }
    }
    /// 另存一张 6 寸相纸上排好的，拿去冲印
    @Published var printSheet: Bool {
        didSet { UserDefaults.standard.set(printSheet, forKey: Self.printSheetKey) }
    }
    @Published private(set) var preview: CGImage?
    /// 抠图失败、没找到人脸时的说明
    @Published private(set) var message: String?
    @Published private(set) var cutout: IDPhoto.Cutout?
    private var generation = 0

    static let backgroundKey = "pop.idPhoto.background"
    static let printSheetKey = "pop.idPhoto.printSheet"

    /// cutout 不为空时直接用（演示和测试），否则在后台抠图
    init(file: URL, cutout: IDPhoto.Cutout? = nil, size: IDPhoto.Size = .oneInch) {
        self.file = file
        background = UserDefaults.standard.string(forKey: Self.backgroundKey).flatMap(IDPhoto.Background.init(rawValue:)) ?? .blue
        self.size = size
        printSheet = UserDefaults.standard.bool(forKey: Self.printSheetKey)
        if let cutout {
            accept(cutout)
        } else {
            load()
        }
    }

    var canSave: Bool { cutout != nil }

    private func load() {
        let file = self.file
        Task { [weak self] in
            let result = await runInBackground { () -> Result<IDPhoto.Cutout, IDPhoto.Failure> in
                guard let image = TextRecognizer.cgImage(contentsOf: file) else {
                    return .failure(IDPhoto.Failure(message: "读不了这张照片"))
                }
                do {
                    return .success(try IDPhoto.cutout(image))
                } catch {
                    return .failure((error as? IDPhoto.Failure) ?? IDPhoto.Failure(message: error.localizedDescription))
                }
            }
            guard let self else { return }
            switch result {
            case .success(let cutout):
                self.accept(cutout)
            case .failure(let failure):
                self.message = failure.message
            }
        }
    }

    private func accept(_ cutout: IDPhoto.Cutout) {
        self.cutout = cutout
        message = cutout.face == nil ? "没有找到人脸，一寸、二寸按照片中间裁剪" : nil
        render()
    }

    private func render() {
        guard let cutout else { return }
        generation += 1
        let current = generation
        let background = self.background
        let size = self.size
        Task { [weak self] in
            let image = await runInBackground { IDPhoto.compose(cutout, background: background, size: size, maxSide: 640) }
            guard let self, current == self.generation else { return }
            self.preview = image
        }
    }

    /// 按现在选的底色和尺寸生成原大的照片，另存到原图旁边；选了冲印排版（原尺寸除外）再存一张 6 寸相纸
    func save() async throws -> IDPhoto.Saved {
        guard let cutout else { throw IDPhoto.Failure(message: "还没抠好图") }
        let file = self.file
        let background = self.background
        let size = self.size
        let wantsSheet = printSheet && size != .original
        let result = await runInBackground { () -> Result<IDPhoto.Saved, IDPhoto.Failure> in
            guard let image = IDPhoto.compose(cutout, background: background, size: size) else {
                return .failure(IDPhoto.Failure(message: "无法生成照片"))
            }
            do {
                var saved = IDPhoto.Saved(photo: try IDPhoto.save(image, beside: file, background: background, size: size), sheet: nil, copies: 0)
                if wantsSheet, let sheet = IDPhoto.printSheet(image) {
                    saved.sheet = try IDPhoto.save(sheet.image, beside: file, background: background, size: size, suffix: "排版")
                    saved.copies = sheet.copies
                }
                return .success(saved)
            } catch {
                return .failure((error as? IDPhoto.Failure) ?? IDPhoto.Failure(message: error.localizedDescription))
            }
        }
        return try result.get()
    }
}
