import CoreGraphics
import Foundation
import ImageIO
@testable import Pop

/// 两张图逐像素对比：先摆到同一块画布上，再找出不一样的像素，挨在一起的归成一处。
enum ImageDiff {
    /// 两张图怎么摆在一起比
    enum Alignment: Equatable {
        /// 一样大，直接比
        case same
        /// 宽高比一样、大小差得多（比如 1 倍和 2 倍的截图）：大的那张缩到小的那张的大小
        case scaled
        /// 其他情况：都按原来的大小，左上角对齐；只有一张盖到的地方算不一样
        case topLeft
    }

    /// 卡片上的四种看法
    enum Mode: String, CaseIterable, Identifiable {
        case sideBySide
        case swipe
        case overlay
        case difference

        var id: String { rawValue }

        var title: String {
            switch self {
            case .sideBySide: return String(localized: "并排")
            case .swipe: return String(localized: "滑动")
            case .overlay: return String(localized: "叠加")
            case .difference: return String(localized: "差异")
            }
        }
    }

    /// 画布最多这么多像素，再大就两张一起缩小（5K 屏幕的截图是 1470 万像素）
    static let maxPixels = 16_000_000
    /// 按这么大的格子（像素）把不一样的像素归成一处：相邻的格子里都有就算同一处
    static let tileSize = 16
    /// 「忽略细微差别」时，一格里不一样的像素少于这么多就当作杂点
    static let speckle = 4
    /// 差异图里标出不一样的像素用的颜色（sRGB）
    static let highlight: (red: UInt8, green: UInt8, blue: UInt8) = (255, 45, 85)

    /// 每个通道差多少以内算一样：默认只容下换算颜色时的误差；「忽略细微差别」时放宽，压缩图片带来的杂色不算
    static func tolerance(ignoringSubtle: Bool) -> Int {
        ignoringSubtle ? 40 : 2
    }

    struct Failure: Error, Equatable {
        let message: String
    }

    struct Canvas: Equatable {
        var width: Int
        var height: Int
        var alignment: Alignment
        /// 两张图在画布上的位置（像素，左上角为原点）
        var first: CGRect
        var second: CGRect
        /// 图太大，两张一起缩小了
        var reduced = false

        var bounds: CGRect { CGRect(x: 0, y: 0, width: width, height: height) }
    }

    /// 两张图（摆正后的像素大小）在画布上怎么摆
    static func canvas(_ first: CGSize, _ second: CGSize, maxPixels: Int = ImageDiff.maxPixels) -> Canvas {
        let a = CGSize(width: max(first.width.rounded(), 1), height: max(first.height.rounded(), 1))
        let b = CGSize(width: max(second.width.rounded(), 1), height: max(second.height.rounded(), 1))
        let ratioA = a.width / a.height
        let ratioB = b.width / b.height
        // 只差几个像素的（比如窗口宽了一点）不缩放：缩放会让每个像素都变一点，按原大小比更准
        let sizeRatio = max(a.width, b.width) / min(a.width, b.width)
        var size: CGSize
        var frameA: CGRect
        var frameB: CGRect
        let alignment: Alignment
        if a == b {
            alignment = .same
            size = a
            frameA = CGRect(origin: .zero, size: a)
            frameB = frameA
        } else if abs(ratioA - ratioB) <= 0.01 * ratioA, sizeRatio >= 1.2 {
            alignment = .scaled
            size = a.width * a.height <= b.width * b.height ? a : b
            frameA = CGRect(origin: .zero, size: size)
            frameB = frameA
        } else {
            alignment = .topLeft
            size = CGSize(width: max(a.width, b.width), height: max(a.height, b.height))
            frameA = CGRect(origin: .zero, size: a)
            frameB = CGRect(origin: .zero, size: b)
        }
        var reduced = false
        if size.width * size.height > CGFloat(maxPixels) {
            let scale = (CGFloat(maxPixels) / (size.width * size.height)).squareRoot()
            func shrink(_ rect: CGRect) -> CGRect {
                CGRect(x: 0, y: 0, width: max((rect.width * scale).rounded(.down), 1), height: max((rect.height * scale).rounded(.down), 1))
            }
            size = shrink(CGRect(origin: .zero, size: size)).size
            frameA = shrink(frameA)
            frameB = shrink(frameB)
            reduced = true
        }
        return Canvas(width: Int(size.width), height: Int(size.height), alignment: alignment, first: frameA, second: frameB,
                      reduced: reduced)
    }

    // MARK: - 读图

    /// 卡片上显示用的小图长边最多这么多像素
    static let previewSide = 1200

    /// 两张图读出来、摆到画布上（画布大小的图，没盖到的地方是透明的）
    struct Prepared {
        let canvas: Canvas
        let first: CGImage
        let second: CGImage
        /// 卡片上显示用的小图
        let firstPreview: CGImage
        let secondPreview: CGImage
    }

    /// 对比的结果：说明、几处不一样、差异图
    struct Outcome {
        let summary: String
        let regions: Int
        let isIdentical: Bool
        let difference: CGImage?
        let differencePreview: CGImage?
    }

    static func prepare(_ firstURL: URL, _ secondURL: URL) throws -> Prepared {
        func source(_ url: URL) throws -> (CGImageSource, CGSize) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0,
                  let size = ImageStitcher.uprightSize(source) else {
                throw Failure(message: String(localized: "读不了「\(url.lastPathComponent)」"))
            }
            return (source, size)
        }
        let (sourceA, sizeA) = try source(firstURL)
        let (sourceB, sizeB) = try source(secondURL)
        let canvas = Self.canvas(sizeA, sizeB)
        guard let imageA = decode(sourceA, size: sizeA, fitting: canvas.first.size) else {
            throw Failure(message: String(localized: "读不了「\(firstURL.lastPathComponent)」"))
        }
        guard let imageB = decode(sourceB, size: sizeB, fitting: canvas.second.size) else {
            throw Failure(message: String(localized: "读不了「\(secondURL.lastPathComponent)」"))
        }
        return try prepare(imageA, imageB, canvas: canvas)
    }

    /// 已经读好的两张图摆到画布上（演示、测试用）
    static func prepare(_ first: CGImage, _ second: CGImage, canvas: Canvas? = nil) throws -> Prepared {
        let canvas = canvas ?? Self.canvas(CGSize(width: first.width, height: first.height),
                                           CGSize(width: second.width, height: second.height))
        guard let placedA = place(first, in: canvas.first, canvas: canvas),
              let placedB = place(second, in: canvas.second, canvas: canvas) else {
            throw Failure(message: String(localized: "图片太大，没能对比"))
        }
        return Prepared(canvas: canvas, first: placedA, second: placedB,
                        firstPreview: downscaled(placedA, maxSide: previewSide), secondPreview: downscaled(placedB, maxSide: previewSide))
    }

    /// 逐像素对比摆好的两张图，画出差异图
    static func outcome(_ prepared: Prepared, ignoringSubtle: Bool) -> Outcome {
        guard let first = pixels(of: prepared.first), let second = pixels(of: prepared.second) else {
            return Outcome(summary: String(localized: "图片太大，没能对比"), regions: 0, isIdentical: false, difference: nil, differencePreview: nil)
        }
        let result = compare(first, second, width: prepared.canvas.width, height: prepared.canvas.height, ignoringSubtle: ignoringSubtle)
        let difference = differenceImage(base: first, result: result)
        return Outcome(summary: summary(result), regions: result.regions.count, isIdentical: result.isIdentical,
                       difference: difference, differencePreview: difference.map { downscaled($0, maxSide: previewSide) })
    }

    /// 按需要的大小解码：不用缩放、方向也是正的就原样读出每个像素；否则让 ImageIO 摆正、缩小
    private static func decode(_ source: CGImageSource, size: CGSize, fitting target: CGSize) -> CGImage? {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let orientation = properties?[kCGImagePropertyOrientation] as? Int ?? 1
        if orientation == 1, size == target {
            return CGImageSourceCreateImageAtIndex(source, 0, nil)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(target.width, target.height),
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// 画成画布大小的一张图：放在 frame 那里（左上角为原点），别的地方透明
    private static func place(_ image: CGImage, in frame: CGRect, canvas: Canvas) -> CGImage? {
        guard let context = bitmap(width: canvas.width, height: canvas.height) else { return nil }
        context.interpolationQuality = .high
        // CGContext 的原点在左下角
        context.draw(image, in: CGRect(x: frame.minX, y: CGFloat(canvas.height) - frame.maxY, width: frame.width, height: frame.height))
        return context.makeImage()
    }

    private static func bitmap(width: Int, height: Int, data: UnsafeMutableRawPointer? = nil) -> CGContext? {
        CGContext(data: data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    /// 画布大小的图拆成 RGBA（sRGB、预乘透明度，第一行是最上面一行）
    static func pixels(of image: CGImage) -> [UInt8]? {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let drawn = data.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = bitmap(width: image.width, height: image.height, data: buffer.baseAddress) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        return drawn ? data : nil
    }

    // MARK: - 对比

    struct Result {
        var width: Int
        var height: Int
        /// 不一样的像素有多少
        var changed: Int
        /// 不一样的地方（像素，左上角为原点），从上到下、从左到右
        var regions: [CGRect]
        /// 每个像素是不是不一样，一行接一行（画差异图用）
        var mask: [Bool]

        var fraction: Double {
            let total = width * height
            return total == 0 ? 0 : Double(changed) / Double(total)
        }

        var isIdentical: Bool { changed == 0 }
    }

    static func compare(_ first: [UInt8], _ second: [UInt8], width: Int, height: Int, ignoringSubtle: Bool = false) -> Result {
        let count = width * height
        guard count > 0, first.count >= count * 4, second.count >= count * 4 else {
            return Result(width: width, height: height, changed: 0, regions: [], mask: [])
        }
        let tolerance = Self.tolerance(ignoringSubtle: ignoringSubtle)
        let tile = tileSize
        let columns = (width + tile - 1) / tile
        let rows = (height + tile - 1) / tile
        var mask = [Bool](repeating: false, count: count)
        // 每格里有几个不一样的像素，它们占的范围
        var counts = [Int](repeating: 0, count: columns * rows)
        var minX = [Int](repeating: Int.max, count: columns * rows)
        var minY = [Int](repeating: Int.max, count: columns * rows)
        var maxX = [Int](repeating: -1, count: columns * rows)
        var maxY = [Int](repeating: -1, count: columns * rows)
        var changed = 0
        first.withUnsafeBufferPointer { a in
            second.withUnsafeBufferPointer { b in
                for y in 0..<height {
                    let row = y * width
                    let tileRow = (y / tile) * columns
                    for x in 0..<width {
                        let i = (row + x) * 4
                        let difference = max(max(distance(a[i], b[i]), distance(a[i + 1], b[i + 1])),
                                             max(distance(a[i + 2], b[i + 2]), distance(a[i + 3], b[i + 3])))
                        guard difference > tolerance else { continue }
                        mask[row + x] = true
                        changed += 1
                        let cell = tileRow + x / tile
                        counts[cell] += 1
                        if x < minX[cell] { minX[cell] = x }
                        if x > maxX[cell] { maxX[cell] = x }
                        if y < minY[cell] { minY[cell] = y }
                        if y > maxY[cell] { maxY[cell] = y }
                    }
                }
            }
        }
        if ignoringSubtle {
            // 零星几个像素不一样的格子当作压缩带来的杂点
            for cell in counts.indices where counts[cell] > 0 && counts[cell] < speckle {
                for y in minY[cell]...maxY[cell] {
                    for x in minX[cell]...maxX[cell] where mask[y * width + x] {
                        mask[y * width + x] = false
                    }
                }
                changed -= counts[cell]
                counts[cell] = 0
            }
        }
        // 相邻（含斜着挨着）的格子归成一处
        var regions: [CGRect] = []
        var visited = [Bool](repeating: false, count: columns * rows)
        for start in counts.indices where counts[start] > 0 && !visited[start] {
            visited[start] = true
            var stack = [start]
            var box = (minX: Int.max, minY: Int.max, maxX: -1, maxY: -1)
            while let cell = stack.popLast() {
                box = (min(box.minX, minX[cell]), min(box.minY, minY[cell]), max(box.maxX, maxX[cell]), max(box.maxY, maxY[cell]))
                let column = cell % columns
                let row = cell / columns
                for dy in -1...1 {
                    for dx in -1...1 {
                        let x = column + dx
                        let y = row + dy
                        guard x >= 0, y >= 0, x < columns, y < rows else { continue }
                        let neighbor = y * columns + x
                        if counts[neighbor] > 0 && !visited[neighbor] {
                            visited[neighbor] = true
                            stack.append(neighbor)
                        }
                    }
                }
            }
            regions.append(CGRect(x: box.minX, y: box.minY, width: box.maxX - box.minX + 1, height: box.maxY - box.minY + 1))
        }
        regions = merged(regions).sorted { ($0.minY, $0.minX) < ($1.minY, $1.minX) }
        return Result(width: width, height: height, changed: changed, regions: regions, mask: mask)
    }

    @inline(__always)
    private static func distance(_ a: UInt8, _ b: UInt8) -> Int {
        a > b ? Int(a - b) : Int(b - a)
    }

    /// 框重叠的合成一个（L 形的一处可能把另一处框在里面）；太多处时不合并
    static func merged(_ regions: [CGRect]) -> [CGRect] {
        guard regions.count > 1, regions.count <= 400 else { return regions }
        var result = regions
        var changed = true
        while changed {
            changed = false
            outer: for i in result.indices {
                for j in result.indices where j > i && result[i].intersects(result[j]) {
                    result[i] = result[i].union(result[j])
                    result.remove(at: j)
                    changed = true
                    break outer
                }
            }
        }
        return result
    }

    // MARK: - 画图

    /// 差异图：第一张图褪成浅灰当底，不一样的像素涂成红色，每处外面画个框
    static func differenceImage(base: [UInt8], result: Result) -> CGImage? {
        let width = result.width
        let height = result.height
        guard width > 0, height > 0, base.count >= width * height * 4, result.mask.count == width * height,
              let context = bitmap(width: width, height: height), let target = context.data else { return nil }
        let pixels = target.bindMemory(to: UInt8.self, capacity: width * height * 4)
        let (red, green, blue) = highlight
        base.withUnsafeBufferPointer { base in
            for index in 0..<(width * height) {
                let i = index * 4
                if result.mask[index] {
                    pixels[i] = red
                    pixels[i + 1] = green
                    pixels[i + 2] = blue
                    pixels[i + 3] = 255
                    continue
                }
                // 预乘过透明度：叠在白底上就是「颜色 + (255 - 透明度)」
                let white = 255 - Int(base[i + 3])
                let gray = ((Int(base[i]) + white) * 299 + (Int(base[i + 1]) + white) * 587 + (Int(base[i + 2]) + white) * 114) / 1000
                // 褪成浅灰，红色才显眼
                let faded = UInt8(clamping: 255 - (255 - min(gray, 255)) * 35 / 100)
                pixels[i] = faded
                pixels[i + 1] = faded
                pixels[i + 2] = faded
                pixels[i + 3] = 255
            }
        }
        // 框：按图的大小定粗细，往外让开几个像素，不压住不一样的地方
        let line = max(2, (CGFloat(min(width, height)) / 300).rounded())
        context.setStrokeColor(CGColor(srgbRed: CGFloat(red) / 255, green: CGFloat(green) / 255, blue: CGFloat(blue) / 255, alpha: 0.9))
        context.setLineWidth(line)
        for region in result.regions {
            let box = region.insetBy(dx: -(line * 2), dy: -(line * 2))
            context.stroke(CGRect(x: box.minX, y: CGFloat(height) - box.maxY, width: box.width, height: box.height))
        }
        return context.makeImage()
    }

    /// 按卡片上的看法画一张图（复制、存储、贴到屏幕用）。两张图都是画布大小；split 是滑动时分界线的位置，opacity 是叠加时第二张的不透明度
    static func compose(_ mode: Mode, first: CGImage, second: CGImage, difference: CGImage?, split: Double, opacity: Double) -> CGImage? {
        let width = first.width
        let height = first.height
        let full = CGRect(x: 0, y: 0, width: width, height: height)
        switch mode {
        case .difference:
            return difference
        case .sideBySide:
            // 两张并排，中间留一道白缝
            let gap = max(8, width / 40)
            guard let context = bitmap(width: width * 2 + gap, height: height) else { return nil }
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width * 2 + gap, height: height))
            context.draw(first, in: full)
            context.draw(second, in: full.offsetBy(dx: CGFloat(width + gap), dy: 0))
            return context.makeImage()
        case .swipe:
            guard let context = bitmap(width: width, height: height) else { return nil }
            let edge = (CGFloat(width) * CGFloat(min(max(split, 0), 1))).rounded()
            context.draw(second, in: full)
            context.saveGState()
            context.clip(to: CGRect(x: 0, y: 0, width: edge, height: CGFloat(height)))
            context.draw(first, in: full)
            context.restoreGState()
            // 分界线：白线外面一圈淡淡的深色，深色、浅色的图上都看得清
            let line = max(2, (CGFloat(width) / 400).rounded())
            context.setFillColor(CGColor(gray: 0, alpha: 0.35))
            context.fill(CGRect(x: edge - line / 2 - 1, y: 0, width: line + 2, height: CGFloat(height)))
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: edge - line / 2, y: 0, width: line, height: CGFloat(height)))
            return context.makeImage()
        case .overlay:
            guard let context = bitmap(width: width, height: height) else { return nil }
            context.draw(first, in: full)
            context.setAlpha(CGFloat(min(max(opacity, 0), 1)))
            context.draw(second, in: full)
            return context.makeImage()
        }
    }

    /// 卡片上显示用的小图：长边不超过 maxSide
    static func downscaled(_ image: CGImage, maxSide: Int) -> CGImage {
        let longest = max(image.width, image.height)
        guard longest > maxSide else { return image }
        let scale = CGFloat(maxSide) / CGFloat(longest)
        let width = max(Int((CGFloat(image.width) * scale).rounded()), 1)
        let height = max(Int((CGFloat(image.height) * scale).rounded()), 1)
        guard let context = bitmap(width: width, height: height) else { return image }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }

    static func png(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    // MARK: - 说明

    /// 「3 处不一样，占 1.2% 的像素」
    static func summary(_ result: Result) -> String {
        guard !result.isIdentical else { return String(localized: "没有找到不一样的地方") }
        let count = result.regions.count
        return String(localized: "\(count) 处不一样，占 \(percent(result.fraction)) 的像素")
    }

    static func percent(_ fraction: Double) -> String {
        if fraction > 0 && fraction < 0.0001 { return "<0.01%" }
        let value = fraction * 100
        let digits = value >= 10 ? 0 : (value >= 1 ? 1 : 2)
        return String(format: "%.\(digits)f%%", value)
    }

    /// 两张图没法直接比时说一声怎么比的
    static func note(_ canvas: Canvas) -> String? {
        var parts: [String] = []
        switch canvas.alignment {
        case .same: break
        case .scaled: parts.append(String(localized: "两张图比例相同、大小不同：按小的那张的大小对比"))
        case .topLeft: parts.append(String(localized: "两张图大小不同：按左上角对齐"))
        }
        if canvas.reduced {
            // 尺寸不加千分位
            parts.append(String(localized: "图片太大，缩小到 \(String(canvas.width)) × \(String(canvas.height)) 对比"))
        }
        return parts.isEmpty ? nil : parts.joined(separator: String(localized: "；"))
    }
}
