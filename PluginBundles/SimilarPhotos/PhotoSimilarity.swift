import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
@testable import Pop

/// 找相似的照片：连拍、重复存的、改过大小或者重新压缩过的。
///
/// 每张照片算一个「差值指纹」：缩成 9×9 的灰度图，比较左右相邻、上下相邻两格的明暗（差不到 3 级的算一样亮），一共 128 位；
/// 两张照片指纹里不一样的位越少越像，少于门槛的归成一组。每组按像素多少、清晰程度、文件大小挑出最好的一张留着。
enum PhotoSimilarity {
    struct Fingerprint: Equatable {
        let horizontal: UInt64
        let vertical: UInt64

        /// 不一样的位数（0～128）
        func distance(to other: Fingerprint) -> Int {
            (horizontal ^ other.horizontal).nonzeroBitCount + (vertical ^ other.vertical).nonzeroBitCount
        }
    }

    struct Photo: Identifiable, Equatable {
        let url: URL
        let fingerprint: Fingerprint
        /// 宽 × 高
        let width: Int
        let height: Int
        let bytes: Int64
        let modified: Date?
        /// 清晰程度：边缘越多越清楚（拉普拉斯算子的方差）
        let sharpness: Double

        var id: URL { url }
        var pixels: Int { width * height }
    }

    /// 多像才算一组
    enum Sensitivity: String, CaseIterable, Identifiable {
        case strict
        case normal
        case loose

        var id: String { rawValue }

        var title: String {
            switch self {
            case .strict: return String(localized: "几乎一样")
            case .normal: return String(localized: "很像")
            case .loose: return String(localized: "有点像")
            }
        }

        /// 指纹里最多有几位不一样
        var threshold: Int {
            switch self {
            case .strict: return 6
            case .normal: return 14
            case .loose: return 24
            }
        }
    }

    struct Group: Identifiable, Equatable {
        /// 最好的在最前面
        let photos: [Photo]

        var id: URL { photos[0].url }
    }

    /// 最多看这么多张
    static let limit = 3000

    /// 文件夹里（包括子文件夹）的图片；隐藏文件和 App 这类包里面的不算
    static func imageFiles(in roots: [URL], limit: Int = PhotoSimilarity.limit) -> (urls: [URL], truncated: Bool) {
        var urls: [URL] = []
        var seen = Set<String>()
        func add(_ url: URL) -> Bool {
            guard isImage(url), seen.insert(url.standardizedFileURL.path(percentEncoded: false)).inserted else { return true }
            urls.append(url)
            return urls.count < limit
        }
        for root in roots {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: root.path(percentEncoded: false), isDirectory: &isDirectory) else { continue }
            guard isDirectory.boolValue else {
                if !add(root) { return (urls, true) }
                continue
            }
            guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey],
                                                                  options: [.skipsHiddenFiles, .skipsPackageDescendants],
                                                                  errorHandler: { _, _ in true }) else { continue }
            for case let url as URL in enumerator where (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
                if !add(url) { return (urls, true) }
            }
        }
        return (urls, false)
    }

    static func isImage(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else { return false }
        // 矢量图和图标不算照片
        return type.conforms(to: .image) && !type.conforms(to: .svg) && !type.conforms(to: .icns) && !type.conforms(to: .ico)
    }

    // MARK: - 读照片

    /// 读一张：摆正方向的缩略图算指纹和清晰程度；读不了时为 nil
    static func load(_ url: URL) -> Photo? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              var width = properties[kCGImagePropertyPixelWidth] as? Int,
              var height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        // 竖着拍的照片（方向 5～8）宽高对调
        if let orientation = properties[kCGImagePropertyOrientation] as? Int, (5...8).contains(orientation) {
            swap(&width, &height)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 256,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        return Photo(url: url, fingerprint: fingerprint(of: thumbnail), width: width, height: height,
                     bytes: Int64(values?.fileSize ?? 0), modified: values?.contentModificationDate, sharpness: sharpness(of: thumbnail))
    }

    /// 相邻两格差不到这么多级（一共 0～255 级）算一样亮。纯色和天空这种平的地方两格本来一样亮，
    /// 缩放时的舍入和边缘附近的振铃会让它们差一两级，直接比大小的话这些位会随着图片尺寸、压缩乱跳
    static let flatMargin = 3

    /// 缩成 9×9 的灰度图（先缩到 64 见方，一步缩太多会漏掉细节），比左右、上下相邻两格的明暗：后一格亮出 flatMargin 级以上的记 1
    static func fingerprint(of image: CGImage) -> Fingerprint {
        let small = gray(image, side: 64).flatMap { gray($0, side: 9) }
        guard let small, let data = small.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else {
            return Fingerprint(horizontal: 0, vertical: 0)
        }
        let stride = small.bytesPerRow
        var horizontal: UInt64 = 0
        var vertical: UInt64 = 0
        for y in 0..<8 {
            for x in 0..<8 {
                horizontal <<= 1
                vertical <<= 1
                let here = Int(bytes[y * stride + x])
                if Int(bytes[y * stride + x + 1]) - here > flatMargin { horizontal |= 1 }
                if Int(bytes[(y + 1) * stride + x]) - here > flatMargin { vertical |= 1 }
            }
        }
        return Fingerprint(horizontal: horizontal, vertical: vertical)
    }

    /// 灰度的正方形缩略图
    static func gray(_ image: CGImage, side: Int) -> CGImage? {
        guard let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        return context.makeImage()
    }

    /// 清晰程度：灰度图上拉普拉斯算子（上下左右四格之和减中间的四倍）的方差，糊的照片边缘少、方差小
    static func sharpness(of image: CGImage) -> Double {
        let width = image.width
        let height = image.height
        guard width > 2, height > 2,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue),
              let data = context.data else { return 0 }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height)
        var sum = 0.0
        var squares = 0.0
        var count = 0.0
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let center = Double(pixels[y * width + x])
                let value = Double(pixels[(y - 1) * width + x]) + Double(pixels[(y + 1) * width + x])
                    + Double(pixels[y * width + x - 1]) + Double(pixels[y * width + x + 1]) - 4 * center
                sum += value
                squares += value * value
                count += 1
            }
        }
        let mean = sum / count
        return squares / count - mean * mean
    }

    // MARK: - 分组

    /// 像的连在一起归成一组（A 像 B、B 像 C 时三张一组）；只有一张的不算。每组最好的在最前面，组按第一张的路径排
    static func groups(_ photos: [Photo], sensitivity: Sensitivity) -> [Group] {
        var parent = Array(photos.indices)
        func root(_ index: Int) -> Int {
            var index = index
            while parent[index] != index {
                parent[index] = parent[parent[index]]
                index = parent[index]
            }
            return index
        }
        for i in photos.indices {
            for j in photos.indices where j > i && photos[i].fingerprint.distance(to: photos[j].fingerprint) <= sensitivity.threshold {
                let a = root(i)
                let b = root(j)
                if a != b { parent[b] = a }
            }
        }
        var members: [Int: [Photo]] = [:]
        for index in photos.indices {
            members[root(index), default: []].append(photos[index])
        }
        return members.values.filter { $0.count > 1 }
            .map { Group(photos: $0.sorted(by: isBetter)) }
            // 不按语言排（中文环境里汉字会排到字母前面），结果每台机器都一样
            .sorted { $0.photos[0].url.path(percentEncoded: false).compare($1.photos[0].url.path(percentEncoded: false),
                                                                            options: [.numeric, .caseInsensitive]) == .orderedAscending }
    }

    /// 哪张更好：像素多的、清楚的、文件大的、新的
    static func isBetter(_ a: Photo, _ b: Photo) -> Bool {
        if a.pixels != b.pixels { return a.pixels > b.pixels }
        // 清晰程度差不到一成算一样
        if abs(a.sharpness - b.sharpness) > max(a.sharpness, b.sharpness) * 0.1 { return a.sharpness > b.sharpness }
        if a.bytes != b.bytes { return a.bytes > b.bytes }
        return (a.modified ?? .distantPast) > (b.modified ?? .distantPast)
    }

    /// 缩略图（卡片上显示）
    static func thumbnail(_ url: URL, side: Int = 160) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: side,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
