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

    /// 文字的字号跟着线宽变
    static func fontSize(for lineWidth: CGFloat) -> CGFloat {
        max(lineWidth * 4, 14)
    }

    /// 序号圆圈的半径
    static func counterRadius(for lineWidth: CGFloat) -> CGFloat {
        max(lineWidth * 3, 11)
    }

    /// 画上所有标注，得到和原图同样像素大小的 PNG
    func renderPNG() -> Data? {
        commitText()
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
        guard let output = context.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: output).representation(using: .png, properties: [:])
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
