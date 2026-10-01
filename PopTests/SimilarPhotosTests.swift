import AppKit
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Pop

final class SimilarPhotosTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "pop-similar-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    /// 一张「照片」：渐变的天空、一个圆、一块地面；offset 把圆挪一点
    private func picture(width: Int = 320, height: Int = 240, offset: CGFloat = 0, flipped: Bool = false) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        let w = CGFloat(width)
        let h = CGFloat(height)
        let colors = flipped
            ? [CGColor(srgbRed: 0.1, green: 0.5, blue: 0.2, alpha: 1), CGColor(srgbRed: 0.9, green: 0.9, blue: 0.3, alpha: 1)]
            : [CGColor(srgbRed: 1, green: 0.7, blue: 0.4, alpha: 1), CGColor(srgbRed: 0.4, green: 0.5, blue: 1, alpha: 1)]
        let gradient = try XCTUnwrap(CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: [0, 1]))
        if flipped {
            context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: w, y: 0), options: [])
            context.setFillColor(CGColor(gray: 0.1, alpha: 1))
            context.fill(CGRect(x: w * 0.6, y: 0, width: w * 0.15, height: h))
        } else {
            context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: h), end: CGPoint(x: 0, y: h * 0.35), options: [.drawsAfterEndLocation])
            context.setFillColor(CGColor(srgbRed: 1, green: 0.95, blue: 0.8, alpha: 1))
            context.fillEllipse(in: CGRect(x: w * 0.45 + offset, y: h * 0.55, width: w * 0.18, height: w * 0.18))
            context.setFillColor(CGColor(srgbRed: 0.15, green: 0.25, blue: 0.6, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: w, height: h * 0.35))
        }
        return try XCTUnwrap(context.makeImage())
    }

    private func write(_ image: CGImage, _ name: String, type: UTType = .png, properties: [CFString: Any] = [:]) throws -> URL {
        let url = folder.appending(path: name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }

    private func photo(_ name: String, _ image: CGImage, width: Int, height: Int, bytes: Int64 = 1000, sharpness: Double = 100) -> PhotoSimilarity.Photo {
        PhotoSimilarity.Photo(url: URL(fileURLWithPath: "/tmp/\(name)"), fingerprint: PhotoSimilarity.fingerprint(of: image),
                              width: width, height: height, bytes: bytes, modified: nil, sharpness: sharpness)
    }

    func testFingerprintsOfSimilarAndDifferentPictures() throws {
        let original = try picture()
        let fingerprint = PhotoSimilarity.fingerprint(of: original)
        XCTAssertEqual(fingerprint.distance(to: fingerprint), 0)
        // 缩小一半、挪一点点：差得很少
        XCTAssertLessThanOrEqual(fingerprint.distance(to: PhotoSimilarity.fingerprint(of: try picture(width: 160, height: 120))), 6)
        XCTAssertLessThanOrEqual(fingerprint.distance(to: PhotoSimilarity.fingerprint(of: try picture(offset: 4))), 14)
        // 重新存成 JPEG（压缩得很厉害）
        let jpeg = try write(original, "a.jpg", type: .jpeg, properties: [kCGImageDestinationLossyCompressionQuality: 0.2])
        let reloaded = try XCTUnwrap(PhotoSimilarity.load(jpeg))
        XCTAssertLessThanOrEqual(fingerprint.distance(to: reloaded.fingerprint), 6)
        // 完全不一样的
        XCTAssertGreaterThan(fingerprint.distance(to: PhotoSimilarity.fingerprint(of: try picture(flipped: true))), 24)
    }

    func testGroupsKeepTheBestPhotoFirst() throws {
        let base = try picture()
        let photos = [
            photo("small.png", base, width: 800, height: 600),
            photo("big.png", base, width: 4000, height: 3000),
            photo("other.png", try picture(flipped: true), width: 4000, height: 3000),
            // 一样大，清楚的那张更好
            photo("blurry.png", try picture(offset: 2), width: 4000, height: 3000, sharpness: 20),
        ]
        let groups = PhotoSimilarity.groups(photos, sensitivity: .normal)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].photos.map(\.url.lastPathComponent), ["big.png", "blurry.png", "small.png"])
        // 最严的只要几乎一样的
        XCTAssertEqual(PhotoSimilarity.groups(photos, sensitivity: .strict).first?.photos.map(\.url.lastPathComponent).contains("big.png"), true)
        XCTAssertTrue(PhotoSimilarity.isBetter(photos[1], photos[0]))
        XCTAssertTrue(PhotoSimilarity.isBetter(photo("a", base, width: 10, height: 10, sharpness: 100), photo("b", base, width: 10, height: 10, sharpness: 50)))
        // 清晰程度差不到一成算一样，比文件大小
        XCTAssertTrue(PhotoSimilarity.isBetter(photo("a", base, width: 10, height: 10, bytes: 2000, sharpness: 95),
                                               photo("b", base, width: 10, height: 10, bytes: 1000, sharpness: 100)))
    }

    func testSharpnessPrefersCrispEdges() throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 128, height: 128, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 128, height: 128))
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        for x in stride(from: 0, to: 128, by: 8) {
            context.fill(CGRect(x: x, y: 0, width: 4, height: 128))
        }
        let sharp = try XCTUnwrap(context.makeImage())
        // 缩小再放大，边缘就糊了
        let small = try XCTUnwrap(PhotoSimilarity.gray(sharp, side: 16))
        let blurred = try XCTUnwrap(PhotoSimilarity.gray(small, side: 128))
        XCTAssertGreaterThan(PhotoSimilarity.sharpness(of: sharp), PhotoSimilarity.sharpness(of: blurred) * 2)
    }

    func testFindsImagesInFoldersAndReadsSizes() throws {
        let image = try picture()
        _ = try write(image, "a.png")
        _ = try write(image, "子文件夹/b.jpg", type: .jpeg)
        _ = try write(image, ".hidden.png")
        try Data("不是图片".utf8).write(to: folder.appending(path: "说明.txt"))
        // 竖着拍的：EXIF 方向 6，宽高对调
        let rotated = try write(image, "c.jpg", type: .jpeg, properties: [kCGImagePropertyOrientation: 6])

        let found = PhotoSimilarity.imageFiles(in: [folder])
        XCTAssertEqual(Set(found.urls.map(\.lastPathComponent)), ["a.png", "b.jpg", "c.jpg"])
        XCTAssertFalse(found.truncated)
        XCTAssertTrue(PhotoSimilarity.imageFiles(in: [folder], limit: 2).truncated)

        let loaded = try XCTUnwrap(PhotoSimilarity.load(rotated))
        XCTAssertEqual([loaded.width, loaded.height], [240, 320])
        XCTAssertGreaterThan(loaded.bytes, 0)
        XCTAssertNil(PhotoSimilarity.load(folder.appending(path: "说明.txt")))
        XCTAssertNotNil(PhotoSimilarity.thumbnail(rotated))
    }

    @MainActor
    func testCardMarksAllButTheBestAndMovesThemToTheTrash() async throws {
        let (photos, thumbnails) = SimilarPhotosPlugin.demo()
        var recycled: [URL] = []
        let model = SimilarPhotosModel(title: "照片", photos: photos, sensitivity: .normal, recycle: { urls in
            recycled = urls
            return urls
        })
        model.setThumbnails(thumbnails)
        XCTAssertEqual(model.phase, .results)
        XCTAssertEqual(model.groups.map { $0.photos.count }, [3, 2])
        XCTAssertEqual(model.groups[0].photos.first?.url.lastPathComponent, "IMG_2041.HEIC")
        XCTAssertEqual(model.groups[1].photos.first?.url.lastPathComponent, "猫.jpg")
        XCTAssertEqual(model.marked.count, 3)
        XCTAssertEqual(model.thumbnails.count, photos.count)
        let freed = ByteCountFormatter.string(fromByteCount: 2_300_000 + 2_350_000 + 240_000, countStyle: .file)
        XCTAssertEqual(model.summary, "找到 2 组相似的照片，一共 5 张；勾上的 3 张移到废纸篓能腾出 \(freed)")
        // 点一下留着
        let cat = try XCTUnwrap(model.groups[1].photos.last)
        model.toggle(cat)
        XCTAssertEqual(model.marked.count, 2)
        model.trash()
        for _ in 0..<200 where model.phase == .working {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(Set(recycled.map(\.lastPathComponent)), ["IMG_2042.HEIC", "IMG_2043.HEIC"])
        XCTAssertEqual(model.phase, .done(trashed: 2, freed: 2_300_000 + 2_350_000, failed: 0))

        let empty = SimilarPhotosModel(title: "照片", photos: [photos[5]], sensitivity: .normal, recycle: { $0 })
        XCTAssertEqual(empty.summary, "看了 1 张图片，没有找到相似的")
    }

    func testPluginTakesFoldersOrSeveralImages() {
        let plugin = SimilarPhotosPlugin().info
        XCTAssertTrue(plugin.canHandle(ContentClassifier.classify(.files([folder]))))
        XCTAssertTrue(plugin.canHandle(ContentClassifier.classify(.files([URL(fileURLWithPath: "/tmp/a.jpg"), URL(fileURLWithPath: "/tmp/b.heic")]))))
        XCTAssertFalse(plugin.canHandle(ContentClassifier.classify(.files([URL(fileURLWithPath: "/tmp/a.jpg")]))))
        XCTAssertFalse(plugin.canHandle(.empty))
    }
}
