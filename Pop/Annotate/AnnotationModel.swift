import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

/// 标注里的一笔：箭头、方框、椭圆、画笔、文字、马赛克、序号。坐标都是图片上的点（左上角为原点）。
struct Annotation: Identifiable, Equatable {
    enum Kind: Equatable {
        case arrow
        case rectangle
        case ellipse
        case pen
        case text(String)
        case mosaic
        case counter(Int)
    }

    let id = UUID()
    var kind: Kind
    var points: [CGPoint]
    var color: AnnotationColor
    var lineWidth: CGFloat

    var start: CGPoint { points.first ?? .zero }
    var end: CGPoint { points.last ?? .zero }

    /// 起点和终点围成的矩形
    var bounds: CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
    }

    /// 太小的一笔（手抖点了一下）不要
    var isMeaningful: Bool {
        switch kind {
        case .text(let text): return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .counter: return true
        case .pen: return points.count > 1
        case .arrow: return hypot(end.x - start.x, end.y - start.y) >= 4
        case .rectangle, .ellipse, .mosaic: return bounds.width >= 3 && bounds.height >= 3
        }
    }

    /// 箭头、方框、椭圆、画笔的线条（马赛克、文字、序号另外画）
    var strokePath: Path? {
        switch kind {
        case .arrow:
            return Self.arrowPath(from: start, to: end, lineWidth: lineWidth)
        case .rectangle:
            return Path(roundedRect: bounds, cornerRadius: lineWidth)
        case .ellipse:
            return Path(ellipseIn: bounds)
        case .pen:
            var path = Path()
            path.addLines(points)
            return path
        case .text, .mosaic, .counter:
            return nil
        }
    }

    /// 箭头：一条线加上终点处的两撇，箭头大小跟着线宽变
    static func arrowPath(from start: CGPoint, to end: CGPoint, lineWidth: CGFloat) -> Path {
        var path = Path()
        path.move(to: start)
        path.addLine(to: end)
        let angle = atan2(end.y - start.y, end.x - start.x)
        let length = max(lineWidth * 4, 12)
        for offset in [CGFloat.pi * 5 / 6, -CGFloat.pi * 5 / 6] {
            path.move(to: end)
            path.addLine(to: CGPoint(x: end.x + cos(angle + offset) * length, y: end.y + sin(angle + offset) * length))
        }
        return path
    }
}

enum AnnotationColor: String, CaseIterable, Identifiable {
    case red, orange, yellow, green, blue, black, white

    var id: String { rawValue }

    var nsColor: NSColor {
        switch self {
        case .red: return NSColor(srgbRed: 0.93, green: 0.22, blue: 0.2, alpha: 1)
        case .orange: return NSColor(srgbRed: 1, green: 0.58, blue: 0, alpha: 1)
        case .yellow: return NSColor(srgbRed: 1, green: 0.84, blue: 0.04, alpha: 1)
        case .green: return NSColor(srgbRed: 0.2, green: 0.78, blue: 0.35, alpha: 1)
        case .blue: return NSColor(srgbRed: 0, green: 0.48, blue: 1, alpha: 1)
        case .black: return .black
        case .white: return .white
        }
    }

    var color: Color { Color(nsColor: nsColor) }

    /// 序号圆圈里的数字用的颜色
    var contrasting: Color {
        switch self {
        case .yellow, .white: return .black
        default: return .white
        }
    }
}

/// 截图四周加的背景：渐变色、圆角和阴影，适合发到文档、社交网络里
enum AnnotationBackground: String, CaseIterable, Identifiable {
    case sky, sunset, mint, grape, graphite, paper

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sky: return "晴空"
        case .sunset: return "晚霞"
        case .mint: return "薄荷"
        case .grape: return "葡萄"
        case .graphite: return "石墨"
        case .paper: return "纸白"
        }
    }

    /// 从左上到右下的两种颜色
    var nsColors: [NSColor] {
        switch self {
        case .sky: return [NSColor(srgbRed: 0.35, green: 0.62, blue: 1, alpha: 1), NSColor(srgbRed: 0.55, green: 0.36, blue: 0.96, alpha: 1)]
        case .sunset: return [NSColor(srgbRed: 1, green: 0.62, blue: 0.35, alpha: 1), NSColor(srgbRed: 0.94, green: 0.33, blue: 0.56, alpha: 1)]
        case .mint: return [NSColor(srgbRed: 0.36, green: 0.86, blue: 0.66, alpha: 1), NSColor(srgbRed: 0.16, green: 0.62, blue: 0.78, alpha: 1)]
        case .grape: return [NSColor(srgbRed: 0.78, green: 0.44, blue: 0.95, alpha: 1), NSColor(srgbRed: 0.36, green: 0.27, blue: 0.84, alpha: 1)]
        case .graphite: return [NSColor(srgbRed: 0.33, green: 0.35, blue: 0.4, alpha: 1), NSColor(srgbRed: 0.12, green: 0.13, blue: 0.16, alpha: 1)]
        case .paper: return [NSColor(srgbRed: 0.96, green: 0.96, blue: 0.97, alpha: 1), NSColor(srgbRed: 0.86, green: 0.87, blue: 0.9, alpha: 1)]
        }
    }

    var colors: [Color] { nsColors.map { Color(nsColor: $0) } }
}

enum AnnotationTool: String, CaseIterable, Identifiable {
    case arrow, rectangle, ellipse, pen, text, mosaic, counter

    var id: String { rawValue }

    var title: String {
        switch self {
        case .arrow: return "箭头"
        case .rectangle: return "方框"
        case .ellipse: return "椭圆"
        case .pen: return "画笔"
        case .text: return "文字"
        case .mosaic: return "马赛克"
        case .counter: return "序号"
        }
    }

    var symbol: String {
        switch self {
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .pen: return "scribble"
        // textformat 在中文系统上显示成「格式」两个字，这里用带光标的字符
        case .text: return "character.cursor.ibeam"
        case .mosaic: return "checkerboard.rectangle"
        case .counter: return "1.circle"
        }
    }

    /// 快捷键：A 箭头、R 方框、O 椭圆、P 画笔、T 文字、M 马赛克、N 序号
    var key: Character {
        switch self {
        case .arrow: return "a"
        case .rectangle: return "r"
        case .ellipse: return "o"
        case .pen: return "p"
        case .text: return "t"
        case .mosaic: return "m"
        case .counter: return "n"
        }
    }
}

/// 一张截图的标注：画了哪些、正在画哪一笔、撤销；最后合成一张 PNG。
@MainActor
final class AnnotationModel: ObservableObject {
    let image: CGImage
    /// 图片的大小（点）：像素除以屏幕倍率
    let size: CGSize
    /// 打了马赛克的整张图，马赛克区域从这里取
    let pixelated: CGImage?

    @Published private(set) var annotations: [Annotation] = []
    @Published var current: Annotation?
    @Published var tool: AnnotationTool = .arrow
    @Published var color: AnnotationColor = .red
    @Published var lineWidth: CGFloat = 4
    /// 正在输入的文字的位置
    @Published var textAnchor: CGPoint?
    @Published var textDraft = ""
    /// 四周加的背景；nil 表示不加
    @Published var background: AnnotationBackground?

    init(image: CGImage, pointSize: CGSize) {
        self.image = image
        size = pointSize
        pixelated = Self.pixelate(image)
    }

    var canUndo: Bool { !annotations.isEmpty }

    private var nextCounter: Int {
        annotations.reduce(0) { result, annotation in
            if case .counter(let number) = annotation.kind { return max(result, number) }
            return result
        } + 1
    }

    // MARK: - 画

    func begin(at point: CGPoint) {
        switch tool {
        case .text:
            commitText()
            textAnchor = point
            textDraft = ""
        case .counter:
            add(Annotation(kind: .counter(nextCounter), points: [point], color: color, lineWidth: lineWidth))
        default:
            let kind: Annotation.Kind
            switch tool {
            case .arrow: kind = .arrow
            case .rectangle: kind = .rectangle
            case .ellipse: kind = .ellipse
            case .mosaic: kind = .mosaic
            default: kind = .pen
            }
            current = Annotation(kind: kind, points: [point, point], color: color, lineWidth: lineWidth)
        }
    }

    func drag(to point: CGPoint) {
        guard var annotation = current else { return }
        if annotation.kind == .pen {
            annotation.points.append(point)
        } else {
            annotation.points = [annotation.start, point]
        }
        current = annotation
    }

    func end() {
        if let annotation = current {
            add(annotation)
        }
        current = nil
    }

    func commitText() {
        if let anchor = textAnchor {
            add(Annotation(kind: .text(textDraft), points: [anchor], color: color, lineWidth: lineWidth))
        }
        textAnchor = nil
        textDraft = ""
    }

    private func add(_ annotation: Annotation) {
        guard annotation.isMeaningful else { return }
        annotations.append(annotation)
    }

    func undo() {
        if textAnchor != nil {
            textAnchor = nil
            textDraft = ""
        } else if !annotations.isEmpty {
            annotations.removeLast()
        }
    }

    // MARK: - 合成

    /// 加背景时截图四周留的宽度（点）
    var backgroundPadding: CGFloat {
        max(24, (min(size.width, size.height) * 0.08).rounded())
    }

    /// 加背景时截图的圆角（点）
    static let backgroundCornerRadius: CGFloat = 10

    /// 合成后图片的大小（点）：加了背景时四周多出 backgroundPadding
    var outputSize: CGSize {
        guard background != nil else { return size }
        return CGSize(width: size.width + backgroundPadding * 2, height: size.height + backgroundPadding * 2)
    }

    /// 文字的字号跟着线宽变
    static func fontSize(for lineWidth: CGFloat) -> CGFloat {
        max(lineWidth * 4, 14)
    }

    /// 序号圆圈的半径
    static func counterRadius(for lineWidth: CGFloat) -> CGFloat {
        max(lineWidth * 3, 11)
    }

    /// 画上所有标注（加了背景时再套上背景），得到 PNG；截图部分和原图的像素大小一样
    func renderPNG() -> Data? {
        commitText()
        guard let annotated = composedImage() else { return nil }
        var output = annotated
        if let background {
            guard let withBackground = framed(annotated, in: background) else { return nil }
            output = withBackground
        }
        return NSBitmapImageRep(cgImage: output).representation(using: .png, properties: [:])
    }

    /// 原图加上所有标注
    private func composedImage() -> CGImage? {
        let width = image.width
        let height = image.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let pixelRect = CGRect(x: 0, y: 0, width: width, height: height)
        context.draw(image, in: pixelRect)
        // 换成「点、左上角为原点」的坐标，和屏幕上画的一样
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: CGFloat(width) / size.width, y: -CGFloat(height) / size.height)
        let graphics = NSGraphicsContext(cgContext: context, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        for annotation in annotations {
            draw(annotation, in: context)
        }
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }

    /// 截图放在渐变背景中间，圆角、带阴影
    private func framed(_ image: CGImage, in background: AnnotationBackground) -> CGImage? {
        let pixelsPerPoint = CGFloat(image.width) / max(size.width, 1)
        let padding = backgroundPadding
        let full = outputSize
        let width = Int((full.width * pixelsPerPoint).rounded())
        let height = Int((full.height * pixelsPerPoint).rounded())
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let gradient = CGGradient(colorsSpace: space, colors: background.nsColors.map(\.cgColor) as CFArray,
                                        locations: [0, 1]) else { return nil }
        // 下面用点做单位，原点在左下角
        context.scaleBy(x: pixelsPerPoint, y: pixelsPerPoint)
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: full.height), end: CGPoint(x: full.width, y: 0), options: [])
        let rect = CGRect(x: padding, y: padding, width: size.width, height: size.height)
        let path = CGPath(roundedRect: rect, cornerWidth: Self.backgroundCornerRadius, cornerHeight: Self.backgroundCornerRadius,
                          transform: nil)
        // 阴影的偏移和模糊不跟着坐标缩放，按像素算
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -6 * pixelsPerPoint), blur: 24 * pixelsPerPoint,
                          color: NSColor.black.withAlphaComponent(0.35).cgColor)
        context.addPath(path)
        context.setFillColor(NSColor.white.cgColor)
        context.fillPath()
        context.restoreGState()
        context.saveGState()
        context.addPath(path)
        context.clip()
        context.draw(image, in: rect)
        context.restoreGState()
        return context.makeImage()
    }

    private func draw(_ annotation: Annotation, in context: CGContext) {
        let color = annotation.color.nsColor.cgColor
        switch annotation.kind {
        case .mosaic:
            guard let pixelated else { return }
            context.saveGState()
            context.clip(to: annotation.bounds)
            // 这里的坐标是翻转过的，画图片要再翻回来
            context.translateBy(x: 0, y: size.height)
            context.scaleBy(x: 1, y: -1)
            context.draw(pixelated, in: CGRect(origin: .zero, size: size))
            context.restoreGState()
        case .text(let text):
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: Self.fontSize(for: annotation.lineWidth), weight: .semibold),
                .foregroundColor: annotation.color.nsColor,
            ]
            NSAttributedString(string: text, attributes: attributes).draw(at: annotation.start)
        case .counter(let number):
            let radius = Self.counterRadius(for: annotation.lineWidth)
            let circle = CGRect(x: annotation.start.x - radius, y: annotation.start.y - radius, width: radius * 2, height: radius * 2)
            context.setFillColor(color)
            context.fillEllipse(in: circle)
            let label = NSAttributedString(string: "\(number)", attributes: [
                .font: NSFont.systemFont(ofSize: radius * 1.1, weight: .bold),
                .foregroundColor: NSColor(annotation.color.contrasting),
            ])
            let labelSize = label.size()
            label.draw(at: CGPoint(x: annotation.start.x - labelSize.width / 2, y: annotation.start.y - labelSize.height / 2))
        case .arrow, .rectangle, .ellipse, .pen:
            guard let path = annotation.strokePath else { return }
            context.setStrokeColor(color)
            context.setLineWidth(annotation.lineWidth)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.addPath(path.cgPath)
            context.strokePath()
        }
    }

    /// 整张图打上马赛克（格子大小随图片大小变）
    private static func pixelate(_ image: CGImage) -> CGImage? {
        let input = CIImage(cgImage: image)
        let filter = CIFilter.pixellate()
        filter.inputImage = input.clampedToExtent()
        filter.scale = Float(max(Double(max(image.width, image.height)) / 60, 8))
        filter.center = CGPoint(x: 0, y: 0)
        guard let output = filter.outputImage?.cropped(to: input.extent) else { return nil }
        return CIContext().createCGImage(output, from: input.extent)
    }
}
