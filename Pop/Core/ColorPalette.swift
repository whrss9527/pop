import CoreGraphics
import Foundation

/// 从图片里挑出主要的几种颜色，按面积从大到小排。
enum ColorPalette {
    struct Swatch: Equatable {
        /// 0–255
        var red: Int
        var green: Int
        var blue: Int
        /// 占图片（不算透明部分）的比例，0–1
        var share: Double

        var hex: String { String(format: "#%02X%02X%02X", red, green, blue) }
    }

    /// 缩小到这么大再统计，大图也很快
    private static let sampleSide = 96
    /// 两种颜色离得比这近就算同一种（RGB 空间的距离）
    private static let minimumDistance = 28.0

    static func extract(from image: CGImage, count: Int = 6) -> [Swatch] {
        guard count > 0, let pixels = samplePixels(image) else { return [] }

        // 先按每个通道 16 级分桶，统计每个桶的像素数和颜色总和
        var bins = [Bin](repeating: Bin(), count: 4096)
        var total = 0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Int(pixels[index + 3])
            guard alpha >= 128 else { continue }
            // 预乘了透明度，还原回来
            let red = min(Int(pixels[index]) * 255 / alpha, 255)
            let green = min(Int(pixels[index + 1]) * 255 / alpha, 255)
            let blue = min(Int(pixels[index + 2]) * 255 / alpha, 255)
            let key = (red >> 4) << 8 | (green >> 4) << 4 | (blue >> 4)
            bins[key].add(red: red, green: green, blue: blue)
            total += 1
        }
        guard total > 0 else { return [] }
        let populated = bins.indices.filter { bins[$0].count > 0 }.sorted {
            bins[$0].count != bins[$1].count ? bins[$0].count > bins[$1].count : $0 < $1
        }

        // 从像素最多的桶开始挑种子，和已有的离得够远才算新颜色
        var centers: [RGB] = []
        for key in populated {
            let color = bins[key].mean
            if centers.allSatisfy({ $0.distance(to: color) > minimumDistance }) {
                centers.append(color)
                if centers.count == count * 2 { break }
            }
        }

        // 再用几轮 k-means 把每种颜色调到它那一群像素的平均值
        var weights = [Int](repeating: 0, count: centers.count)
        for _ in 0..<8 {
            var sums = [Bin](repeating: Bin(), count: centers.count)
            for key in populated {
                let nearest = nearestIndex(to: bins[key].mean, in: centers)
                sums[nearest].merge(bins[key])
            }
            for index in centers.indices where sums[index].count > 0 {
                centers[index] = sums[index].mean
            }
            weights = sums.map(\.count)
        }

        // 太接近的颜色合并，按面积排序，去掉零星的颜色
        var merged: [(color: RGB, weight: Int)] = []
        for (color, weight) in zip(centers, weights).sorted(by: { $0.1 > $1.1 }) where weight > 0 {
            if let index = merged.firstIndex(where: { $0.color.distance(to: color) < minimumDistance * 0.7 }) {
                let combined = merged[index].weight + weight
                merged[index].color = merged[index].color.blended(with: color, weight: Double(weight) / Double(combined))
                merged[index].weight = combined
            } else {
                merged.append((color, weight))
            }
        }
        return merged
            .sorted { $0.weight > $1.weight }
            .filter { Double($0.weight) / Double(total) >= 0.01 }
            .prefix(count)
            .map { Swatch(red: Int($0.color.red.rounded()), green: Int($0.color.green.rounded()),
                          blue: Int($0.color.blue.rounded()), share: Double($0.weight) / Double(total)) }
    }

    // MARK: - 内部

    private struct RGB {
        var red: Double
        var green: Double
        var blue: Double

        func distance(to other: RGB) -> Double {
            let dr = red - other.red
            let dg = green - other.green
            let db = blue - other.blue
            return (dr * dr + dg * dg + db * db).squareRoot()
        }

        func blended(with other: RGB, weight: Double) -> RGB {
            RGB(red: red + (other.red - red) * weight,
                green: green + (other.green - green) * weight,
                blue: blue + (other.blue - blue) * weight)
        }
    }

    private struct Bin {
        var count = 0
        var red = 0
        var green = 0
        var blue = 0

        var mean: RGB {
            let n = Double(max(count, 1))
            return RGB(red: Double(red) / n, green: Double(green) / n, blue: Double(blue) / n)
        }

        mutating func add(red: Int, green: Int, blue: Int) {
            count += 1
            self.red += red
            self.green += green
            self.blue += blue
        }

        mutating func merge(_ other: Bin) {
            count += other.count
            red += other.red
            green += other.green
            blue += other.blue
        }
    }

    private static func nearestIndex(to color: RGB, in centers: [RGB]) -> Int {
        var best = 0
        var bestDistance = Double.infinity
        for (index, center) in centers.enumerated() {
            let distance = center.distance(to: color)
            if distance < bestDistance {
                best = index
                bestDistance = distance
            }
        }
        return best
    }

    /// 缩小后的 sRGB 像素（RGBA，预乘透明度）
    private static func samplePixels(_ image: CGImage) -> [UInt8]? {
        guard image.width > 0, image.height > 0 else { return nil }
        let scale = min(1, Double(sampleSide) / Double(max(image.width, image.height)))
        let width = max(Int((Double(image.width) * scale).rounded()), 1)
        let height = max(Int((Double(image.height) * scale).rounded()), 1)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? pixels : nil
    }
}
