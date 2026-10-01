import AppKit
import CoreGraphics
@testable import Pop

/// 截图美化：把截图放在渐变背景上，四周留白，可以加圆角和阴影、按比例补齐，画成一张 PNG。
/// 发文章、做演示、贴到社交平台时，截图不再是光秃秃的一块。背景和截图标注用的是同一套渐变。
enum ScreenshotBeautifier {
    enum Padding: String, CaseIterable, Identifiable {
        case small
        case medium
        case large

        var id: String { rawValue }

        var title: String {
            switch self {
            case .small: return String(localized: "小")
            case .medium: return String(localized: "中")
            case .large: return String(localized: "大")
            }
        }

        /// 留白占截图长边的比例
        var fraction: CGFloat {
            switch self {
            case .small: return 0.05
            case .medium: return 0.09
            case .large: return 0.14
            }
        }
    }

    enum Ratio: String, CaseIterable, Identifiable {
        case auto
        case square
        case fourThree
        case sixteenNine

        var id: String { rawValue }

        var title: String {
            switch self {
            case .auto: return String(localized: "自动")
            case .square: return "1:1"
            case .fourThree: return "4:3"
            case .sixteenNine: return "16:9"
            }
        }

        /// 宽 ÷ 高；自动时按截图加上留白的样子
        var value: CGFloat? {
            switch self {
            case .auto: return nil
            case .square: return 1
            case .fourThree: return 4.0 / 3.0
            case .sixteenNine: return 16.0 / 9.0
            }
        }
    }

    struct Options: Equatable {
        /// 没有背景时是透明的
        var background: AnnotationBackground? = .sky
        var padding = Padding.medium
        var ratio = Ratio.auto
        var corners = true
        var shadow = true

        /// 存在 UserDefaults 里的键（卸载插件时一起删掉，见 PluginCatalog）
        static let keys = ["pop.beautify.background", "pop.beautify.padding", "pop.beautify.ratio", "pop.beautify.corners", "pop.beautify.shadow"]

        /// 上次用的样子
        static var saved: Options {
            let defaults = UserDefaults.standard
            var options = Options()
            if let raw = defaults.string(forKey: keys[0]) { options.background = AnnotationBackground(rawValue: raw) }
            if let raw = defaults.string(forKey: keys[1]), let value = Padding(rawValue: raw) { options.padding = value }
            if let raw = defaults.string(forKey: keys[2]), let value = Ratio(rawValue: raw) { options.ratio = value }
            if defaults.object(forKey: keys[3]) != nil { options.corners = defaults.bool(forKey: keys[3]) }
            if defaults.object(forKey: keys[4]) != nil { options.shadow = defaults.bool(forKey: keys[4]) }
            return options
        }

        func save() {
            let defaults = UserDefaults.standard
            defaults.set(background?.rawValue ?? "clear", forKey: Self.keys[0])
            defaults.set(padding.rawValue, forKey: Self.keys[1])
            defaults.set(ratio.rawValue, forKey: Self.keys[2])
            defaults.set(corners, forKey: Self.keys[3])
            defaults.set(shadow, forKey: Self.keys[4])
        }
    }

    /// 画布：截图加上四周的留白，再按比例把短的那一边补齐
    static func canvasSize(for image: CGSize, options: Options) -> CGSize {
        let padding = (max(image.width, image.height) * options.padding.fraction).rounded()
        var size = CGSize(width: image.width + padding * 2, height: image.height + padding * 2)
        if let ratio = options.ratio.value {
            if size.width / size.height < ratio {
                size.width = (size.height * ratio).rounded()
            } else {
                size.height = (size.width / ratio).rounded()
            }
        }
        return size
    }

    /// 截图在画布正中的位置
    static func imageRect(for image: CGSize, in canvas: CGSize) -> CGRect {
        CGRect(x: ((canvas.width - image.width) / 2).rounded(), y: ((canvas.height - image.height) / 2).rounded(),
               width: image.width, height: image.height)
    }

    /// 圆角半径：按截图短边的 2.5%，至少 8 像素
    static func cornerRadius(for image: CGSize) -> CGFloat {
        max(8, (min(image.width, image.height) * 0.025).rounded())
    }

    static func render(_ image: CGImage, options: Options) -> CGImage? {
        let imageSize = CGSize(width: image.width, height: image.height)
        let canvas = canvasSize(for: imageSize, options: options)
        guard let context = CGContext(data: nil, width: Int(canvas.width), height: Int(canvas.height), bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        if let background = options.background,
           let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: background.nsColors.map(\.cgColor) as CFArray,
                                     locations: [0, 1]) {
            // 左上到右下（Core Graphics 的原点在左下角）
            context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: canvas.height), end: CGPoint(x: canvas.width, y: 0), options: [])
        }
        let rect = imageRect(for: imageSize, in: canvas)
        let radius = options.corners ? cornerRadius(for: imageSize) : 0
        let shape = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        if options.shadow {
            // 先用同样的形状铺一层投出阴影，再把截图画在上面
            let blur = max(imageSize.width, imageSize.height) * 0.03
            context.saveGState()
            context.setShadow(offset: CGSize(width: 0, height: -blur * 0.35), blur: blur, color: CGColor(gray: 0, alpha: 0.38))
            context.addPath(shape)
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fillPath()
            context.restoreGState()
        }
        context.saveGState()
        context.addPath(shape)
        context.clip()
        context.draw(image, in: rect)
        context.restoreGState()
        return context.makeImage()
    }

    static func png(_ image: CGImage) -> Data? {
        NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    /// 缩小到长边不超过 maxSide 像素（预览用，改选项时画得快）
    static func downscaled(_ image: CGImage, maxSide: CGFloat) -> CGImage {
        let longest = CGFloat(max(image.width, image.height))
        guard longest > maxSide else { return image }
        let scale = maxSide / longest
        let width = Int((CGFloat(image.width) * scale).rounded())
        let height = Int((CGFloat(image.height) * scale).rounded())
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }
}
