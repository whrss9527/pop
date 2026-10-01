import CoreGraphics
import Foundation
@testable import Pop

/// 在截图上从一个点往上下左右找颜色变化的地方（界面元素的边），屏幕标尺用它量距离。
struct EdgeFinder {
    let width: Int
    let height: Int
    /// RGBA，每像素 4 字节，第 0 行在最上面
    private let pixels: [UInt8]
    /// 两个像素的 RGB 差（三个通道差的绝对值之和）超过它就算到了边
    var tolerance = 24

    init?(image: CGImage) {
        // 闭包里只用局部常量：属性还没全部赋值时不能在闭包里用 self
        let columns = image.width
        let rows = image.height
        guard columns > 0, rows > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: columns * rows * 4)
        let drawn = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(data: raw.baseAddress, width: columns, height: rows, bitsPerComponent: 8,
                                          bytesPerRow: columns * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: columns, height: rows))
            return true
        }
        guard drawn else { return nil }
        width = columns
        height = rows
        pixels = buffer
    }

    /// 从 (x, y) 往四个方向走，遇到颜色变化停下；返回停下的位置（像素，含起点这一侧最后一个同色像素）
    struct Span: Equatable {
        var left: Int
        var right: Int
        var top: Int
        var bottom: Int

        /// 左右边之间有多少像素
        var width: Int { right - left + 1 }
        var height: Int { bottom - top + 1 }
    }

    func span(atX x: Int, y: Int) -> Span? {
        guard (0..<width).contains(x), (0..<height).contains(y) else { return nil }
        let origin = color(x, y)
        func same(_ px: Int, _ py: Int) -> Bool {
            let other = color(px, py)
            return abs(other.0 - origin.0) + abs(other.1 - origin.1) + abs(other.2 - origin.2) <= tolerance
        }
        var left = x
        while left > 0, same(left - 1, y) { left -= 1 }
        var right = x
        while right < width - 1, same(right + 1, y) { right += 1 }
        var top = y
        while top > 0, same(x, top - 1) { top -= 1 }
        var bottom = y
        while bottom < height - 1, same(x, bottom + 1) { bottom += 1 }
        return Span(left: left, right: right, top: top, bottom: bottom)
    }

    private func color(_ x: Int, _ y: Int) -> (Int, Int, Int) {
        let index = (y * width + x) * 4
        return (Int(pixels[index]), Int(pixels[index + 1]), Int(pixels[index + 2]))
    }
}
