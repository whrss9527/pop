import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
@testable import Pop

/// 把一张图切成几张：九宫格、四宫格（先裁成正方形，对准画面里的主体）、横着三张（先裁成 3:1），或者把长图切成几页。
/// 切好的按发出去的顺序（从左到右、从上到下）编号，存在原图旁边的一个文件夹里，原图不动。
enum ImageSplitter {
    enum Layout: String, CaseIterable, Identifiable {
        case nine
        case four
        case triptych
        case pages

        var id: String { rawValue }

        var title: String {
            switch self {
            case .nine: return String(localized: "九宫格")
            case .four: return String(localized: "四宫格")
            case .triptych: return String(localized: "横切三张")
            case .pages: return String(localized: "长图分页")
            }
        }

        /// 网格的列数、行数（长图分页按图的长短算，不在这里）
        var grid: (columns: Int, rows: Int)? {
            switch self {
            case .nine: return (3, 3)
            case .four: return (2, 2)
            case .triptych: return (3, 1)
            case .pages: return nil
            }
        }
    }

    /// 长图分页时每页最多这么长（短边的 4/3 倍，竖着就是 3:4）
    static let pageRatio: CGFloat = 4.0 / 3.0
    /// 长图最多切这么多页（朋友圈一次最多发 9 张）
    static let maxPages = 9
    /// 长边是短边的这么多倍以上才算长图
    static let longRatio: CGFloat = 1.6

    struct Failure: Error, Equatable {
        let message: String
    }

    struct Plan: Equatable {
        /// 用到的那一块（像素，左上角为原点）；网格先裁成正方形或 3:1
        var region: CGRect
        /// 每一张的位置，按顺序排好
        var tiles: [CGRect]
    }

    /// 这张图能不能按长图分页
    static func isLong(_ size: CGSize) -> Bool {
        let short = min(size.width, size.height)
        return short > 0 && max(size.width, size.height) / short >= longRatio
    }

    /// 怎么切：网格按比例取最大的一块（中心尽量对准 focus），再均分成一样大的格子；长图按长边均分成几页
    static func plan(_ size: CGSize, layout: Layout, focus: CGRect? = nil) -> Plan {
        let width = size.width.rounded(.down)
        let height = size.height.rounded(.down)
        guard width >= 1, height >= 1 else { return Plan(region: .zero, tiles: []) }
        if let grid = layout.grid {
            let columns = grid.columns
            let rows = grid.rows
            let ratio = CGFloat(columns) / CGFloat(rows)
            let crop = SmartCrop.cropRect(imageSize: CGSize(width: width, height: height), ratio: ratio, focus: focus)
            // 每格一样大：切不尽的几个像素从四周平均去掉
            let side = min((crop.width / CGFloat(columns)).rounded(.down), (crop.height / CGFloat(rows)).rounded(.down))
            guard side >= 1 else { return Plan(region: .zero, tiles: []) }
            let region = CGRect(x: crop.minX + ((crop.width - side * CGFloat(columns)) / 2).rounded(.down),
                                y: crop.minY + ((crop.height - side * CGFloat(rows)) / 2).rounded(.down),
                                width: side * CGFloat(columns), height: side * CGFloat(rows))
            var tiles: [CGRect] = []
            for row in 0..<rows {
                for column in 0..<columns {
                    tiles.append(CGRect(x: region.minX + side * CGFloat(column), y: region.minY + side * CGFloat(row), width: side, height: side))
                }
            }
            return Plan(region: region, tiles: tiles)
        }
        // 长图：竖着的按高度分，横着的按宽度分；每页一样长，最多 9 页
        let vertical = height >= width
        let long = vertical ? height : width
        let short = vertical ? width : height
        let count = min(max(Int((long / (short * pageRatio)).rounded(.up)), 2), maxPages)
        var tiles: [CGRect] = []
        for index in 0..<count {
            let start = (long * CGFloat(index) / CGFloat(count)).rounded()
            let end = (long * CGFloat(index + 1) / CGFloat(count)).rounded()
            tiles.append(vertical ? CGRect(x: 0, y: start, width: width, height: end - start)
                                  : CGRect(x: start, y: 0, width: end - start, height: height))
        }
        return Plan(region: CGRect(x: 0, y: 0, width: width, height: height), tiles: tiles)
    }

    /// 读图（照片按方向摆正）
    static func load(_ url: URL) throws -> (image: CGImage, photo: Bool) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0,
              let image = ImageConverter.uprightImage(source) else {
            throw Failure(message: String(localized: "读不了「\(url.lastPathComponent)」"))
        }
        let type = (CGImageSourceGetType(source) as String?).flatMap { UTType($0) } ?? .png
        return (image, type.conforms(to: .jpeg) || type.conforms(to: .heic) || type.conforms(to: .heif))
    }

    /// 切好存进原图旁边的新文件夹「原名 九宫格」，一张一个文件：1.jpg、2.jpg……；照片存成 JPEG，其余存成 PNG。返回文件夹
    static func split(_ image: CGImage, plan: Plan, photo: Bool, beside original: URL, layout: Layout) throws -> URL {
        guard !plan.tiles.isEmpty else { throw Failure(message: String(localized: "图片太小，切不开")) }
        let folder = FileNames.available(in: original.deletingLastPathComponent(),
                                         base: original.deletingPathExtension().lastPathComponent + " " + layout.title)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        } catch {
            throw Failure(message: String(localized: "没能新建文件夹「\(folder.lastPathComponent)」：\(error.localizedDescription)"))
        }
        let type: UTType = photo ? .jpeg : .png
        for (index, tile) in plan.tiles.enumerated() {
            let output = folder.appending(path: "\(index + 1).\(photo ? "jpg" : "png")")
            guard let piece = image.cropping(to: tile),
                  let destination = CGImageDestinationCreateWithURL(output as CFURL, type.identifier as CFString, 1, nil) else {
                try? FileManager.default.removeItem(at: folder)
                throw Failure(message: String(localized: "切第 \(index + 1) 张时出错了"))
            }
            CGImageDestinationAddImage(destination, piece, [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
            guard CGImageDestinationFinalize(destination) else {
                try? FileManager.default.removeItem(at: folder)
                throw Failure(message: String(localized: "存储「\(output.lastPathComponent)」失败"))
            }
        }
        return folder
    }

    /// 「切成 9 张 1080 × 1080」
    static func describe(_ plan: Plan) -> String {
        guard let first = plan.tiles.first else { return String(localized: "图片太小，切不开") }
        let sameSize = plan.tiles.allSatisfy { abs($0.width - first.width) <= 1 && abs($0.height - first.height) <= 1 }
        let count = plan.tiles.count
        if sameSize {
            return String(localized: "切成 \(count) 张 \(Int(first.width)) × \(Int(first.height))")
        }
        return String(localized: "切成 \(count) 张")
    }
}
