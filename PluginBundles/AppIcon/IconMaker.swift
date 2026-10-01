import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
@testable import Pop

/// 用一张图片生成 App 图标：macOS 的 .icns 和 Xcode 用的图标集、iOS 的 1024 图标、网站的 favicon 和几种尺寸的 PNG。
enum IconMaker {
    struct Failure: Error, Equatable {
        let message: String
    }

    /// macOS 图标的样子
    enum Style: String, CaseIterable, Identifiable {
        /// 圆角方块：1024 的画布里占 824 见方，四周留白，底下一点阴影（和系统自带 App 的图标一样大）
        case rounded
        /// 原样铺满方形
        case plain

        var id: String { rawValue }

        var title: String {
            switch self {
            case .rounded: return String(localized: "圆角方块")
            case .plain: return String(localized: "原样")
            }
        }
    }

    /// 图片四周留多少空
    enum Margin: String, CaseIterable, Identifiable {
        case off
        case narrow
        case wide

        var id: String { rawValue }

        var title: String {
            switch self {
            case .off: return String(localized: "不留")
            case .narrow: return String(localized: "窄")
            case .wide: return String(localized: "宽")
            }
        }

        /// 每边留出的比例
        var ratio: CGFloat {
            switch self {
            case .off: return 0
            case .narrow: return 0.1
            case .wide: return 0.2
            }
        }
    }

    /// 透明的地方（还有整张放进去时空出来的地方）垫什么颜色
    enum Fill: String, CaseIterable, Identifiable {
        case white
        case black
        case clear

        var id: String { rawValue }

        var title: String {
            switch self {
            case .white: return String(localized: "白色")
            case .black: return String(localized: "黑色")
            case .clear: return String(localized: "透明")
            }
        }

        var color: CGColor? {
            switch self {
            case .white: return CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
            case .black: return CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
            case .clear: return nil
            }
        }
    }

    /// 不是正方形的图片怎么放
    enum Fit: String, CaseIterable, Identifiable {
        /// 对准画面里的主体裁成正方形
        case crop
        /// 整张放进去，空出来的地方垫底色
        case whole

        var id: String { rawValue }

        var title: String {
            switch self {
            case .crop: return String(localized: "裁成正方形")
            case .whole: return String(localized: "整张放进去")
            }
        }
    }

    struct Options: Equatable {
        var style = Style.rounded
        var margin = Margin.off
        var fill = Fill.white
        var fit = Fit.crop
        var macOS = true
        var iOS = true
        var web = true

        var any: Bool { macOS || iOS || web }
    }

    /// 摆正方向的原图，记下画面的主体（裁成正方形时对准它）和有没有透明的地方
    struct Source {
        let image: CGImage
        /// 画面主体（像素，左上角为原点）；正方形的图不用找
        let focus: CGRect?
        let hasTransparency: Bool

        var size: CGSize {
            CGSize(width: image.width, height: image.height)
        }

        /// 宽高差不到 2% 的算正方形
        var isSquare: Bool {
            abs(image.width - image.height) * 50 <= max(image.width, image.height)
        }

        /// 用到的那一块（像素，左上角为原点）：裁切时（还有差一点点就是正方形时）是对准主体的正方形，否则是整张图
        func region(_ fit: Fit) -> CGRect {
            guard isSquare || fit == .crop else { return CGRect(origin: .zero, size: size) }
            return SmartCrop.cropRect(imageSize: size, ratio: 1, focus: focus)
        }

        /// 缩小一份给卡片预览用，主体的位置跟着缩
        func shrunk(toAbout side: CGFloat) -> Source {
            let small = IconMaker.shrink(image, toAbout: side)
            guard small.width != image.width else { return self }
            let scale = CGFloat(small.width) / CGFloat(image.width)
            let focus = self.focus.map { CGRect(x: $0.minX * scale, y: $0.minY * scale, width: $0.width * scale, height: $0.height * scale) }
            return Source(image: small, focus: focus, hasTransparency: hasTransparency)
        }
    }

    /// 写好的文件夹和一共写了几个文件
    struct Output: Equatable {
        let folder: URL
        let files: Int
    }

    /// .icns 里的每一种：类型和边长（像素）
    static let icnsEntries: [(type: String, side: Int)] = [
        ("icp4", 16), ("ic11", 32), ("icp5", 32), ("ic12", 64), ("ic07", 128),
        ("ic13", 256), ("ic08", 256), ("ic14", 512), ("ic09", 512), ("ic10", 1024),
    ]

    /// Xcode 图标集里 macOS 的每一种：点数和倍数
    static let macOSSlots: [(points: Int, scale: Int)] = [
        (16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2),
    ]

    /// favicon.ico 里放的几种边长
    static let faviconSides = [16, 32, 48]

    static func load(_ url: URL) throws -> Source {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0,
              let image = ImageConverter.uprightImage(source) else {
            throw Failure(message: String(localized: "读不了「\(url.lastPathComponent)」"))
        }
        return prepare(image)
    }

    static func prepare(_ image: CGImage) -> Source {
        let square = abs(image.width - image.height) * 50 <= max(image.width, image.height)
        return Source(image: image, focus: square ? nil : SmartCrop.focus(of: image), hasTransparency: hasTransparency(image))
    }

    /// 有没有透明（或半透明）的地方：缩到 64 见方，看每个像素的不透明度
    static func hasTransparency(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast:
            return false
        default:
            break
        }
        let side = 64
        guard let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data else { return false }
        context.clear(CGRect(x: 0, y: 0, width: side, height: side))
        // 不插值，每个点取原图的一个像素，边上不会混进透明
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        let pixels = data.bindMemory(to: UInt8.self, capacity: side * side * 4)
        return stride(from: 3, to: side * side * 4, by: 4).contains { pixels[$0] < 250 }
    }

    // MARK: - 画图标

    /// macOS 的图标：圆角方块（或者原样铺满）
    static func macOS(_ source: Source, side: Int, options: Options) -> CGImage? {
        guard options.style == .rounded else { return square(source, side: side, options: options) }
        guard let context = makeContext(side) else { return nil }
        let scale = CGFloat(side) / 1024
        let body = CGRect(x: 100 * scale, y: 100 * scale, width: 824 * scale, height: 824 * scale)
        // 阴影跟着画出来的东西走：先在透明图层里画好，整个图层投一次阴影（CGContext 的原点在左下角，往下是 y 变小）
        context.setShadow(offset: CGSize(width: 0, height: -10 * scale), blur: 20 * scale, color: CGColor(gray: 0, alpha: 0.3))
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        context.addPath(squircle(in: body))
        context.clip()
        if let fill = options.fill.color {
            context.setFillColor(fill)
            context.fill(body)
        }
        draw(source, fit: options.fit, in: body.insetBy(dx: body.width * options.margin.ratio, dy: body.height * options.margin.ratio),
             context: context)
        context.endTransparencyLayer()
        return context.makeImage()
    }

    /// 铺满的方形图标（iOS、网站用）。opaque 为 true 时透明的地方垫白色（iOS 的图标不能透明）
    static func square(_ source: Source, side: Int, options: Options, opaque: Bool = false) -> CGImage? {
        guard let context = makeContext(side) else { return nil }
        let canvas = CGRect(x: 0, y: 0, width: side, height: side)
        if let fill = options.fill.color ?? (opaque ? Fill.white.color : nil) {
            context.setFillColor(fill)
            context.fill(canvas)
        }
        draw(source, fit: options.fit, in: canvas.insetBy(dx: canvas.width * options.margin.ratio, dy: canvas.height * options.margin.ratio),
             context: context)
        return context.makeImage()
    }

    /// 圆角方块的轮廓：超椭圆 |x|⁵ + |y|⁵ = 1，和系统 App 图标的圆角差不多大，拐角的弧度是连续变化的
    static func squircle(in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        let steps = 360
        for step in 0..<steps {
            let angle = CGFloat(step) / CGFloat(steps) * 2 * .pi
            let x = rect.midX + rect.width / 2 * signedRoot(cos(angle))
            let y = rect.midY + rect.height / 2 * signedRoot(sin(angle))
            if step == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        path.closeSubpath()
        return path
    }

    private static func signedRoot(_ value: CGFloat) -> CGFloat {
        let root = pow(abs(value), 2 / 5)
        return value < 0 ? -root : root
    }

    /// 把用到的那一块按比例画进 rect（CGContext 坐标）：裁成正方形时正好铺满，整张放进去时居中
    private static func draw(_ source: Source, fit: Fit, in rect: CGRect, context: CGContext) {
        let region = source.region(fit)
        let whole = region.size == source.size
        guard let cropped = whole ? source.image : source.image.cropping(to: region) else { return }
        let width = CGFloat(cropped.width)
        let height = CGFloat(cropped.height)
        let scale = min(rect.width / width, rect.height / height)
        let drawn = CGRect(x: rect.midX - width * scale / 2, y: rect.midY - height * scale / 2, width: width * scale, height: height * scale)
        context.interpolationQuality = .high
        context.draw(shrink(cropped, toAbout: max(drawn.width, drawn.height)), in: drawn)
    }

    /// 缩小时一半一半地缩，最后一步再画到目标大小：缩到 16 像素的小图标也不会出锯齿
    static func shrink(_ image: CGImage, toAbout side: CGFloat) -> CGImage {
        var current = image
        while CGFloat(max(current.width, current.height)) > side * 2,
              let half = resized(current, width: max(current.width / 2, 1), height: max(current.height / 2, 1)) {
            current = half
        }
        return current
    }

    private static func resized(_ image: CGImage, width: Int, height: Int) -> CGImage? {
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    private static func makeContext(_ side: Int) -> CGContext? {
        let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        context?.clear(CGRect(x: 0, y: 0, width: side, height: side))
        return context
    }

    // MARK: - 文件格式

    static func png(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    /// .icns：文件头是「icns」和总长度，后面每一种尺寸一段：类型、这一段的长度、PNG（长度都是大端的 4 个字节）
    static func icns(_ entries: [(type: String, png: Data)]) -> Data {
        var body = Data()
        for entry in entries {
            body.append(contentsOf: Array(entry.type.utf8))
            appendBigEndian(UInt32(entry.png.count + 8), to: &body)
            body.append(entry.png)
        }
        var data = Data("icns".utf8)
        appendBigEndian(UInt32(body.count + 8), to: &data)
        data.append(body)
        return data
    }

    /// .ico：文件头、每张图一条目录（宽、高、颜色数、保留、色彩平面、位数、长度、位置，都是小端），后面接着每张图的 PNG
    static func ico(_ images: [(side: Int, png: Data)]) -> Data {
        var data = Data()
        appendLittleEndian(UInt16(0), to: &data)
        appendLittleEndian(UInt16(1), to: &data)
        appendLittleEndian(UInt16(images.count), to: &data)
        var offset = 6 + 16 * images.count
        for image in images {
            // 256 写成 0
            let side = UInt8(image.side >= 256 ? 0 : image.side)
            data.append(contentsOf: [side, side, 0, 0])
            appendLittleEndian(UInt16(1), to: &data)
            appendLittleEndian(UInt16(32), to: &data)
            appendLittleEndian(UInt32(image.png.count), to: &data)
            appendLittleEndian(UInt32(offset), to: &data)
            offset += image.png.count
        }
        for image in images {
            data.append(image.png)
        }
        return data
    }

    private static func appendBigEndian<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        withUnsafeBytes(of: value.bigEndian) { data.append(contentsOf: $0) }
    }

    private static func appendLittleEndian<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }

    /// Xcode 图标集的 Contents.json
    static func contentsJSON(_ images: [[String: String]]) -> Data {
        let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
        return (try? JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])) ?? Data()
    }

    // MARK: - 写文件

    /// 存进原图旁边的新文件夹「原名 图标」：macOS、iOS、网站各一个子文件夹。返回文件夹和写了几个文件
    static func write(_ source: Source, options: Options, beside original: URL) throws -> Output {
        guard options.any else { throw Failure(message: String(localized: "至少选一种要生成的图标")) }
        let name = original.deletingPathExtension().lastPathComponent
        let folder = FileNames.available(in: original.deletingLastPathComponent(), base: String(localized: "\(name) 图标"))
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        } catch {
            throw Failure(message: String(localized: "没能新建文件夹「\(folder.lastPathComponent)」：\(error.localizedDescription)"))
        }
        do {
            var files = 0
            if options.macOS {
                files += try writeMacOS(source, options: options, into: folder.appending(path: "macOS", directoryHint: .isDirectory))
            }
            if options.iOS {
                files += try writeIOS(source, options: options, into: folder.appending(path: "iOS", directoryHint: .isDirectory))
            }
            if options.web {
                files += try writeWeb(source, options: options, name: name,
                                      into: folder.appending(path: String(localized: "网站"), directoryHint: .isDirectory))
            }
            return Output(folder: folder, files: files)
        } catch {
            try? FileManager.default.removeItem(at: folder)
            if let failure = error as? Failure { throw failure }
            throw Failure(message: String(localized: "生成图标时出错了：\(error.localizedDescription)"))
        }
    }

    /// AppIcon.icns 和 AppIcon.appiconset（10 张 PNG 和 Contents.json）
    private static func writeMacOS(_ source: Source, options: Options, into folder: URL) throws -> Int {
        // 同样大小的只画一次（.icns 和图标集里有好几张一样大的）
        var cache: [Int: Data] = [:]
        func iconData(_ side: Int) throws -> Data {
            if let cached = cache[side] { return cached }
            guard let icon = Self.macOS(source, side: side, options: options), let encoded = Self.png(icon) else {
                throw Failure(message: String(localized: "画 \(String(side)) 像素的图标时出错了"))
            }
            cache[side] = encoded
            return encoded
        }
        let set = folder.appending(path: "AppIcon.appiconset", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
        try Self.icns(icnsEntries.map { ($0.type, try iconData($0.side)) }).write(to: folder.appending(path: "AppIcon.icns"))
        var images: [[String: String]] = []
        for slot in macOSSlots {
            let filename = "icon_\(slot.points)x\(slot.points)\(slot.scale == 2 ? "@2x" : "").png"
            try iconData(slot.points * slot.scale).write(to: set.appending(path: filename))
            images.append(["filename": filename, "idiom": "mac", "scale": "\(slot.scale)x", "size": "\(slot.points)x\(slot.points)"])
        }
        try contentsJSON(images).write(to: set.appending(path: "Contents.json"))
        return 2 + macOSSlots.count
    }

    /// AppIcon.appiconset：一张 1024 的不透明 PNG（新版 Xcode 按它生成别的尺寸，圆角由系统加）
    private static func writeIOS(_ source: Source, options: Options, into folder: URL) throws -> Int {
        let set = folder.appending(path: "AppIcon.appiconset", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
        guard let image = square(source, side: 1024, options: options, opaque: true), let data = png(image) else {
            throw Failure(message: String(localized: "画 \(String(1024)) 像素的图标时出错了"))
        }
        try data.write(to: set.appending(path: "AppIcon-1024.png"))
        try contentsJSON([["filename": "AppIcon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"]])
            .write(to: set.appending(path: "Contents.json"))
        return 2
    }

    /// favicon.ico（16、32、48）、16 和 32 的 PNG、苹果设备加到主屏幕用的 180、安卓用的 192 和 512，还有 site.webmanifest
    private static func writeWeb(_ source: Source, options: Options, name: String, into folder: URL) throws -> Int {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        func webData(_ side: Int, opaque: Bool = false) throws -> Data {
            guard let icon = Self.square(source, side: side, options: options, opaque: opaque), let encoded = Self.png(icon) else {
                throw Failure(message: String(localized: "画 \(String(side)) 像素的图标时出错了"))
            }
            return encoded
        }
        try Self.ico(faviconSides.map { ($0, try webData($0)) }).write(to: folder.appending(path: "favicon.ico"))
        try webData(16).write(to: folder.appending(path: "favicon-16x16.png"))
        try webData(32).write(to: folder.appending(path: "favicon-32x32.png"))
        // 加到主屏幕的图标透明的地方会变黑，垫上底色
        try webData(180, opaque: true).write(to: folder.appending(path: "apple-touch-icon.png"))
        try webData(192).write(to: folder.appending(path: "android-chrome-192x192.png"))
        try webData(512).write(to: folder.appending(path: "android-chrome-512x512.png"))
        let manifest: [String: Any] = [
            "name": name,
            "short_name": name,
            "icons": [192, 512].map { ["src": "/android-chrome-\($0)x\($0).png", "sizes": "\($0)x\($0)", "type": "image/png"] },
            "display": "standalone",
        ]
        let json = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try json.write(to: folder.appending(path: "site.webmanifest"))
        return 7
    }
}
