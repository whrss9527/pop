import AppKit
import XCTest
@testable import Pop

final class SplitImageTests: XCTestCase {
    func testNineGridIsSquaresAroundTheSubject() {
        let plan = ImageSplitter.plan(CGSize(width: 1000, height: 800), layout: .nine)
        // 800 × 800 的正方形放在中间，切不尽的 2 个像素从两边各去掉 1 个
        XCTAssertEqual(plan.region, CGRect(x: 101, y: 1, width: 798, height: 798))
        XCTAssertEqual(plan.tiles.count, 9)
        XCTAssertEqual(plan.tiles.first, CGRect(x: 101, y: 1, width: 266, height: 266))
        XCTAssertEqual(plan.tiles[1], CGRect(x: 367, y: 1, width: 266, height: 266))
        XCTAssertEqual(plan.tiles.last, CGRect(x: 633, y: 533, width: 266, height: 266))
        XCTAssertEqual(ImageSplitter.describe(plan), "切成 9 张 266 × 266")
        // 主体在右边时正方形往右挪，不超出图片
        let right = ImageSplitter.plan(CGSize(width: 1000, height: 800), layout: .nine, focus: CGRect(x: 900, y: 300, width: 100, height: 100))
        XCTAssertEqual(right.region.minX, 201)
        XCTAssertLessThanOrEqual(right.region.maxX, 1000)
    }

    func testFourGridAndThreeAcross() {
        let four = ImageSplitter.plan(CGSize(width: 600, height: 600), layout: .four)
        XCTAssertEqual(four.region, CGRect(x: 0, y: 0, width: 600, height: 600))
        XCTAssertEqual(four.tiles, [CGRect(x: 0, y: 0, width: 300, height: 300), CGRect(x: 300, y: 0, width: 300, height: 300),
                                    CGRect(x: 0, y: 300, width: 300, height: 300), CGRect(x: 300, y: 300, width: 300, height: 300)])
        let panorama = ImageSplitter.plan(CGSize(width: 3000, height: 1000), layout: .triptych)
        XCTAssertEqual(panorama.tiles.map(\.minX), [0, 1000, 2000])
        XCTAssertTrue(panorama.tiles.allSatisfy { $0.size == CGSize(width: 1000, height: 1000) })
        // 不够宽的图裁出中间一条 3:1
        let photo = ImageSplitter.plan(CGSize(width: 1200, height: 900), layout: .triptych)
        XCTAssertEqual(photo.region, CGRect(x: 0, y: 250, width: 1200, height: 400))
        XCTAssertEqual(photo.tiles.map(\.minX), [0, 400, 800])
    }

    func testLongImagesSplitIntoEqualPages() {
        let pages = ImageSplitter.plan(CGSize(width: 1000, height: 5000), layout: .pages)
        XCTAssertEqual(pages.tiles, [CGRect(x: 0, y: 0, width: 1000, height: 1250), CGRect(x: 0, y: 1250, width: 1000, height: 1250),
                                     CGRect(x: 0, y: 2500, width: 1000, height: 1250), CGRect(x: 0, y: 3750, width: 1000, height: 1250)])
        // 再长也最多 9 页，首尾相接
        let long = ImageSplitter.plan(CGSize(width: 1000, height: 30000), layout: .pages)
        XCTAssertEqual(long.tiles.count, 9)
        XCTAssertEqual(long.tiles.first?.minY, 0)
        XCTAssertEqual(long.tiles.last?.maxY, 30000)
        for (a, b) in zip(long.tiles, long.tiles.dropFirst()) {
            XCTAssertEqual(a.maxY, b.minY)
        }
        XCTAssertEqual(ImageSplitter.describe(long), "切成 9 张 1000 × 3333")
        // 横着的长图按宽度分
        let wide = ImageSplitter.plan(CGSize(width: 5000, height: 1000), layout: .pages)
        XCTAssertEqual(wide.tiles.map(\.minX), [0, 1250, 2500, 3750])
        XCTAssertTrue(ImageSplitter.isLong(CGSize(width: 1000, height: 1600)))
        XCTAssertTrue(ImageSplitter.isLong(CGSize(width: 2000, height: 1000)))
        XCTAssertFalse(ImageSplitter.isLong(CGSize(width: 1000, height: 1500)))
    }

    func testTooSmallImages() {
        XCTAssertTrue(ImageSplitter.plan(CGSize(width: 2, height: 2), layout: .nine).tiles.isEmpty)
        XCTAssertTrue(ImageSplitter.plan(.zero, layout: .pages).tiles.isEmpty)
        XCTAssertEqual(ImageSplitter.describe(ImageSplitter.Plan(region: .zero, tiles: [])), "图片太小，切不开")
    }

    func testSplitSavesNumberedPiecesInAFolder() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "pop-split-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let context = try XCTUnwrap(CGContext(data: nil, width: 300, height: 300, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(srgbRed: 0.2, green: 0.5, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 300, height: 300))
        let original = folder.appending(path: "图.png")
        try XCTUnwrap(NSBitmapImageRep(cgImage: try XCTUnwrap(context.makeImage())).representation(using: .png, properties: [:])).write(to: original)

        let (image, photo) = try ImageSplitter.load(original)
        XCTAssertFalse(photo)
        let plan = ImageSplitter.plan(CGSize(width: image.width, height: image.height), layout: .nine)
        let output = try ImageSplitter.split(image, plan: plan, photo: photo, beside: original, layout: .nine)
        XCTAssertEqual(output.lastPathComponent, "图 九宫格")
        let names = try FileManager.default.contentsOfDirectory(atPath: output.path(percentEncoded: false)).sorted()
        XCTAssertEqual(names, (1...9).map { "\($0).png" })
        let piece = try XCTUnwrap(TextRecognizer.cgImage(contentsOf: output.appending(path: "5.png")))
        XCTAssertEqual([piece.width, piece.height], [100, 100])
        // 再切一次不覆盖，换个文件夹
        XCTAssertEqual(try ImageSplitter.split(image, plan: plan, photo: photo, beside: original, layout: .nine).lastPathComponent, "图 九宫格 2")
    }

    @MainActor
    func testCardOffersPagesOnlyForLongImages() throws {
        func image(_ width: Int, _ height: Int) throws -> CGImage {
            try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage())
        }
        let long = SplitImageModel(image: try image(100, 400), name: "长图.png", focus: nil)
        XCTAssertEqual(long.layout, .pages)
        XCTAssertEqual(long.layouts, [.nine, .four, .triptych, .pages])
        let square = SplitImageModel(image: try image(300, 300), name: "方图.png", focus: nil, layout: .pages)
        XCTAssertEqual(square.layout, .nine)
        XCTAssertEqual(square.layouts, [.nine, .four, .triptych])
        XCTAssertEqual(square.folderName, "方图 九宫格")
        XCTAssertLessThanOrEqual(max(square.preview.width, square.preview.height), 900)
    }

    func testPluginTakesImageFiles() throws {
        let plugin = SplitImagePlugin().info
        XCTAssertTrue(plugin.canHandle(ContentClassifier.classify(.files([URL(fileURLWithPath: "/tmp/海边.jpg")]))))
        XCTAssertFalse(plugin.canHandle(ContentClassifier.classify(.files([URL(fileURLWithPath: "/tmp/说明.txt")]))))
        XCTAssertFalse(plugin.canHandle(.empty))
        let photo = try XCTUnwrap(SplitImagePlugin.demoPhoto())
        XCTAssertEqual([photo.width, photo.height], [1200, 900])
    }
}
