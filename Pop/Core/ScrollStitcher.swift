import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 滚动截图的拼接：每收到一屏，和上一屏比出往下滚了几行，把新露出来的几行接到长图下面。
/// 区域顶上、底下不跟着滚的部分（工具栏、输入框）比对时不算；长图开头是第一屏的，结尾是最后一屏的。
struct ScrollStitcher {
    /// 一屏里每一行的指纹
    struct Fingerprint: Equatable {
        /// 像素一样指纹就一样（最右边一小条不算：滚动的时候滚动条在那里动）
        var rows: [UInt64]
        /// 这一行是不是一片纯色：空白行放在哪儿都对得上，不拿来判断滚了多少
        var plain: [Bool]
    }

    enum Step: Equatable {
        /// 和上一屏一样，没滚
        case unchanged
        /// 往下滚了这么多行，接上了
        case appended(Int)
        /// 对不上（滚得太快、往回滚了，或者内容整个变了），这一屏不要
        case lost
        /// 长图到上限了
        case full
    }

    /// 长图最多这么多像素高
    static let maxHeight = 20_000
    /// 最右边这么多像素不算进指纹（区域比这宽很多时）
    static let ignoredRightEdge = 40
    /// 重叠的部分至少这么多行对得上，才算接上了
    static let minimumScore = 0.8

    let width: Int
    let frameHeight: Int
    /// 长图最多多高
    let heightLimit: Int
    private let space: CGColorSpace
    /// 长图的像素，一行接一行，最上面一行在最前面
    private var pixels: [UInt32]
    private var last: Fingerprint
    /// 长图现在多高（像素）
    private(set) var height: Int
    /// 接上了几帧（算上第一帧）
    private(set) var frames = 1

    init?(first: CGImage, maxHeight: Int = ScrollStitcher.maxHeight) {
        var space = Self.rgbSpace(of: first)
        var bytes = Self.rgba(first, space: space)
        if bytes == nil, let sRGB = CGColorSpace(name: CGColorSpace.sRGB) {
            space = sRGB
            bytes = Self.rgba(first, space: sRGB)
        }
        guard let bytes, first.width > 0, first.height > 0 else { return nil }
        width = first.width
        frameHeight = first.height
        heightLimit = maxHeight
        self.space = space
        pixels = bytes
        last = Self.fingerprint(bytes, width: first.width, height: first.height)
        height = first.height
    }

    /// 收到新的一屏
    mutating func add(_ image: CGImage) -> Step {
        guard image.width == width, image.height == frameHeight, let bytes = Self.rgba(image, space: space) else { return .lost }
        let next = Self.fingerprint(bytes, width: width, height: frameHeight)
        guard let found = Self.offset(from: last, to: next) else { return .lost }
        let rows = found.rows
        let footer = found.footer
        // 没滚（最多是光标闪了、按钮高亮了这类小变化）：还是跟上一次接上的那一屏比
        guard rows > 0 else { return .unchanged }
        guard height + rows <= heightLimit else { return .full }
        // 长图结尾是上一屏底下没动的几行：去掉，接上新露出来的几行和这一屏底下的部分
        pixels.removeLast(footer * width)
        pixels.append(contentsOf: bytes[((frameHeight - footer - rows) * width)...])
        height += rows
        last = next
        frames += 1
        return .appended(rows)
    }

    /// 拼好的长图
    func makeImage() -> CGImage? {
        let data = pixels.withUnsafeBytes { Data($0) }
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4, space: space,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider,
                       decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    // MARK: - 比对

    /// 从上一屏到这一屏往下滚了几行（0 表示没滚）、底下有几行没动；对不上时返回 nil
    static func offset(from previous: Fingerprint, to next: Fingerprint) -> (rows: Int, footer: Int)? {
        let count = previous.rows.count
        guard count > 0, next.rows.count == count, previous.plain.count == count, next.plain.count == count else { return nil }
        if previous.rows == next.rows { return (0, 0) }
        // 顶上、底下一样的几行是不跟着滚的部分（上下都是空白的几行也算在里面，不影响比对）
        var header = 0
        while header < count, previous.rows[header] == next.rows[header] {
            header += 1
        }
        var footer = 0
        while footer < count - header, previous.rows[count - 1 - footer] == next.rows[count - 1 - footer] {
            footer += 1
        }
        let top = header
        let bottom = count - footer
        let band = bottom - top
        // 对不上时，变了的只是窄窄一条（光标、按钮高亮）就当没滚
        let unchangedOrLost: (rows: Int, footer: Int)? = band <= count / 4 ? (0, 0) : nil
        let overlap = max(4, band / 8)
        guard band > overlap else { return unchangedOrLost }

        // 可能滚了多少：拿这一屏靠上的几行有内容的行，去上一屏里找一样的行
        var positions: [UInt64: [Int]] = [:]
        for index in top..<bottom where !previous.plain[index] {
            positions[previous.rows[index], default: []].append(index)
        }
        var candidates: Set<Int> = [0]
        var anchors = 0
        for index in top..<bottom where !next.plain[index] {
            for match in positions[next.rows[index]] ?? [] {
                let distance = match - index
                if distance >= 0, distance <= band - overlap {
                    candidates.insert(distance)
                }
            }
            anchors += 1
            if anchors == 32 { break }
        }

        // 每个候选都比一遍重叠的部分，对得上的行最多的那个就是；一样多时取滚得少的
        var best: (rows: Int, score: Double)?
        for distance in candidates.sorted() {
            var compared = 0
            var matched = 0
            for index in top..<(bottom - distance) {
                let same = next.rows[index] == previous.rows[index + distance]
                // 两边都是同一种纯色的行说明不了什么
                if same && next.plain[index] { continue }
                compared += 1
                if same { matched += 1 }
            }
            guard compared >= 3 else { continue }
            let score = Double(matched) / Double(compared)
            if score >= minimumScore, score > (best?.score ?? 0) + 0.000_001 {
                best = (distance, score)
            }
        }
        guard let best else { return unchangedOrLost }
        return (best.rows, footer)
    }

    /// 每一行的指纹
    static func fingerprint(_ pixels: [UInt32], width: Int, height: Int) -> Fingerprint {
        let columns = width > ignoredRightEdge * 4 ? width - ignoredRightEdge : width
        var rows = [UInt64](repeating: 0, count: height)
        var plain = [Bool](repeating: true, count: height)
        pixels.withUnsafeBufferPointer { buffer in
            for row in 0..<height {
                let start = row * width
                let first = buffer[start]
                var hash: UInt64 = 0xcbf2_9ce4_8422_2325
                var uniform = true
                for column in 0..<columns {
                    let value = buffer[start + column]
                    hash = (hash ^ UInt64(value)) &* 0x100_0000_01b3
                    if value != first {
                        uniform = false
                    }
                }
                rows[row] = hash
                plain[row] = uniform
            }
        }
        return Fingerprint(rows: rows, plain: plain)
    }

    // MARK: - 像素

    /// 按 RGBA 读出每个像素，第一行是图片最上面一行
    static func rgba(_ image: CGImage, space: CGColorSpace) -> [UInt32]? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }
        var pixels = [UInt32](repeating: 0, count: width * height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? pixels : nil
    }

    /// 截图原来的颜色空间（比如 Display P3），不是 RGB 的换成 sRGB
    private static func rgbSpace(of image: CGImage) -> CGColorSpace {
        if let space = image.colorSpace, space.model == .rgb {
            return space
        }
        return CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    }

    // MARK: - 长图的其他用处

    /// 长图切成几段（识别文字用，太高的图一次识别不准）：每段最多 maxHeight 像素，尽量切在空白的行上，免得把一行字切成两半
    static func sections(of image: CGImage, maxHeight: Int = 2400) -> [CGImage] {
        guard image.height > maxHeight, maxHeight > 0,
              let pixels = rgba(image, space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()) else {
            return [image]
        }
        let rows = fingerprint(pixels, width: image.width, height: image.height)
        var cuts = [0]
        var start = 0
        while image.height - start > maxHeight {
            let limit = start + maxHeight
            var cut = limit
            // 从预定的地方往上找一行空白，最多找四分之一段
            var row = limit
            while row > start + maxHeight * 3 / 4 {
                if rows.plain[row] {
                    cut = row
                    break
                }
                row -= 1
            }
            cuts.append(cut)
            start = cut
        }
        cuts.append(image.height)
        var result: [CGImage] = []
        for index in 0..<(cuts.count - 1) {
            let rect = CGRect(x: 0, y: cuts[index], width: image.width, height: cuts[index + 1] - cuts[index])
            if let section = image.cropping(to: rect) {
                result.append(section)
            }
        }
        return result
    }

    /// 一段一段识别长图里的文字，接在一起
    static func recognizeText(_ png: Data) throws -> String {
        guard let image = TextRecognizer.cgImage(from: png) else { return "" }
        var parts: [String] = []
        for section in sections(of: image) {
            let text = try TextRecognizer.recognizeLines(in: section)
            if !text.isEmpty {
                parts.append(text)
            }
        }
        return parts.joined(separator: "\n")
    }

    /// 长图有几屏高：「2.5」「1」「12」
    static func screensText(height: Int, frameHeight: Int) -> String {
        let screens = Double(height) / Double(max(frameHeight, 1))
        if screens >= 10 {
            return String(Int(screens.rounded()))
        }
        let tenths = Int((screens * 10).rounded())
        return tenths % 10 == 0 ? String(tenths / 10) : "\(tenths / 10).\(tenths % 10)"
    }

    /// 结果卡片：卡片里可以上下滚动看完整的长图
    static func card(_ image: CGImage, frameHeight: Int) -> ResultCard? {
        guard let png = pngData(image, maxWidth: nil) else { return nil }
        let size = "\(image.width) × \(image.height)"
        let screens = screensText(height: image.height, frameHeight: frameHeight)
        let detail = image.height > frameHeight
            ? String(localized: "拼好了一张 \(size) 像素的长图，约 \(screens) 屏高；按住拖动预览图也能拖到别的 App 里")
            : String(localized: "没有滚动，只截了一屏（\(size) 像素）；按住拖动预览图也能拖到别的 App 里")
        let buttons = [
            CardButton(title: String(localized: "复制图片"), action: .copyImage(png)),
            CardButton(title: String(localized: "存储"), action: .saveImage(png, name: ImageFiles.timestampedName(String(localized: "Pop 滚动截图")))),
            CardButton(title: String(localized: "识别文字"), action: .recognizeImageText(png)),
        ]
        return ResultCard(title: String(localized: "滚动截图"), detail: detail, image: png,
                          imagePreview: pngData(image, maxWidth: 720), buttons: buttons)
    }

    /// 存成 PNG；给了 maxWidth 时按宽度缩小（预览用）
    static func pngData(_ image: CGImage, maxWidth: Int?) -> Data? {
        var output = image
        if let maxWidth, image.width > maxWidth {
            let height = max(1, Int((Double(image.height) * Double(maxWidth) / Double(image.width)).rounded()))
            guard let context = CGContext(data: nil, width: maxWidth, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: rgbSpace(of: image), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                return nil
            }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: maxWidth, height: height))
            guard let scaled = context.makeImage() else { return nil }
            output = scaled
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, output, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}
