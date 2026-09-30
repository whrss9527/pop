import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

extension ImageStitcher {
    /// 动图里每张停几秒
    static let gifFrameDelay: Double = 1
    /// 动图最长的一边不超过多少像素
    static let gifMaxSide: CGFloat = 800

    /// 按顺序把几张图片合成一张循环播放的 GIF，存在第一张旁边，返回新文件的位置。
    /// 画面大小按第一张（最长边不超过 800），其余的等比缩放放在正中，空出来的地方填白色
    static func animate(_ urls: [URL], frameDelay: Double = gifFrameDelay) throws -> URL {
        guard urls.count >= 2 else { throw Failure(message: "至少选两张图片") }
        guard urls.count <= maxCount else { throw Failure(message: "一次最多合成 \(maxCount) 张") }
        var sources: [CGImageSource] = []
        var sizes: [CGSize] = []
        for url in urls {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0,
                  let size = uprightSize(source) else {
                throw Failure(message: "读不了「\(url.lastPathComponent)」")
            }
            sources.append(source)
            sizes.append(size)
        }
        let canvas = fitted(sizes[0], maxSide: gifMaxSide)
        let first = urls[0]
        let output = FileNames.available(in: first.deletingLastPathComponent(),
                                         base: first.deletingPathExtension().lastPathComponent + " 动图", extension: "gif")
        guard let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.gif.identifier as CFString, urls.count, nil) else {
            throw Failure(message: "这台 Mac 不支持存成 GIF")
        }
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        let frameProperties = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: frameDelay,
                                                               kCGImagePropertyGIFUnclampedDelayTime: frameDelay]] as CFDictionary
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        for (index, source) in sources.enumerated() {
            let frame = aspectFit(sizes[index], in: canvas)
            // 按需要的大小解码（照片按方向摆正）
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: max(frame.width, frame.height),
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
                  let context = CGContext(data: nil, width: Int(canvas.width), height: Int(canvas.height), bitsPerComponent: 8,
                                          bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
                throw Failure(message: "读不了「\(urls[index].lastPathComponent)」")
            }
            context.interpolationQuality = .high
            context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            context.fill(CGRect(origin: .zero, size: canvas))
            context.draw(image, in: frame)
            guard let frameImage = context.makeImage() else { throw Failure(message: "合成动图失败") }
            CGImageDestinationAddImage(destination, frameImage, frameProperties)
        }
        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: output)
            throw Failure(message: "存储「\(output.lastPathComponent)」失败")
        }
        return output
    }

    /// 等比缩小到最长的一边不超过 maxSide（不放大），取整
    static func fitted(_ size: CGSize, maxSide: CGFloat) -> CGSize {
        let scale = min(1, maxSide / max(size.width, size.height, 1))
        return CGSize(width: max((size.width * scale).rounded(), 1), height: max((size.height * scale).rounded(), 1))
    }

    /// 等比缩放后放在 canvas 正中的位置
    static func aspectFit(_ size: CGSize, in canvas: CGSize) -> CGRect {
        let scale = min(canvas.width / max(size.width, 1), canvas.height / max(size.height, 1))
        let width = max((size.width * scale).rounded(), 1)
        let height = max((size.height * scale).rounded(), 1)
        return CGRect(x: ((canvas.width - width) / 2).rounded(), y: ((canvas.height - height) / 2).rounded(), width: width, height: height)
    }
}
