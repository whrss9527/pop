import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 把图片压到指定大小以内（比如网上报名要求照片不超过 200 KB）：存成 JPEG，先降低画质，还不够就缩小尺寸。
/// KB 按 1000 字节算，比按 1024 算严一点，两种要求都满足。
extension ImageConverter {
    /// 卡片上直接点的几档（字节）
    static let sizeLimits = [100_000, 200_000, 500_000, 1_000_000, 2_000_000]

    /// 「200 KB」「1 MB」
    static func sizeLabel(_ bytes: Int) -> String {
        guard bytes >= 1000 else { return "\(bytes) B" }
        guard bytes >= 1_000_000 else { return "\(bytes / 1000) KB" }
        let megabytes = Double(bytes) / 1_000_000
        if megabytes == megabytes.rounded() {
            return "\(Int(megabytes)) MB"
        }
        return String(format: "%.1f MB", megabytes)
    }

    /// 压到 limit 字节以内，另存一份「原名 200KB.jpg」；返回新文件和它的大小
    static func compress(_ url: URL, toBytes limit: Int) throws -> (url: URL, bytes: Int) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0,
              let full = uprightImage(source).flatMap(flattened) else {
            throw Failure(message: String(localized: "读不了「\(url.lastPathComponent)」"))
        }
        let longSide = Double(max(full.width, full.height))
        // 先在原尺寸上找画质；画质要降到太低时改成缩小尺寸，最后一档才允许画质很低
        let scales: [Double] = [1, 0.85, 0.7, 0.55, 0.4, 0.3, 0.2, 0.12]
        for (index, scale) in scales.enumerated() {
            let image = scale == 1 ? full : resized(full, maxSide: Int((longSide * scale).rounded()))
            guard let image else { continue }
            let lowest = index == scales.count - 1 ? 0.1 : 0.45
            guard let data = bestJPEG(image, limit: limit, lowestQuality: lowest) else { continue }
            let label = sizeLabel(limit).replacingOccurrences(of: " ", with: "")
            let output = FileNames.available(in: url.deletingLastPathComponent(),
                                             base: url.deletingPathExtension().lastPathComponent + " " + label, extension: "jpg")
            do {
                try data.write(to: output)
            } catch {
                throw Failure(message: String(localized: "存储「\(output.lastPathComponent)」失败"))
            }
            return (output, data.count)
        }
        throw Failure(message: String(localized: "「\(url.lastPathComponent)」压不到 \(sizeLabel(limit)) 以内"))
    }

    /// 不超过 limit 的最高画质（二分找 6 次）；最低画质也超了返回 nil
    static func bestJPEG(_ image: CGImage, limit: Int, lowestQuality: Double) -> Data? {
        if let top = jpegData(image, quality: 0.92), top.count <= limit {
            return top
        }
        guard var best = jpegData(image, quality: lowestQuality), best.count <= limit else { return nil }
        var low = lowestQuality
        var high = 0.92
        for _ in 0..<6 {
            let middle = (low + high) / 2
            guard let data = jpegData(image, quality: middle) else { break }
            if data.count <= limit {
                best = data
                low = middle
            } else {
                high = middle
            }
        }
        return best
    }

    static func jpegData(_ image: CGImage, quality: Double) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    /// 透明的地方铺成白色（JPEG 没有透明，不铺的话会变成黑色）
    static func flattened(_ image: CGImage) -> CGImage? {
        draw(image, width: image.width, height: image.height)
    }

    /// 等比缩小到最长的一边是 maxSide
    static func resized(_ image: CGImage, maxSide: Int) -> CGImage? {
        let scale = Double(maxSide) / Double(max(image.width, image.height, 1))
        guard scale < 1 else { return image }
        return draw(image, width: max(Int((Double(image.width) * scale).rounded()), 1),
                    height: max(Int((Double(image.height) * scale).rounded()), 1))
    }

    private static func draw(_ image: CGImage, width: Int, height: Int) -> CGImage? {
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        let canvas = CGRect(x: 0, y: 0, width: width, height: height)
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(canvas)
        context.interpolationQuality = .high
        context.draw(image, in: canvas)
        return context.makeImage()
    }
}
