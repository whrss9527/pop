import XCTest
@testable import Pop

final class CompareImagesTests: XCTestCase {
    /// 白底的图，再按顺序涂几块颜色（像素，左上角为原点）
    private func image(_ width: Int, _ height: Int, background: CGColor = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1),
                       fills: [(CGRect, CGColor)] = []) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(background)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        for (rect, color) in fills {
            context.setFillColor(color)
            context.fill(CGRect(x: rect.minX, y: CGFloat(height) - rect.maxY, width: rect.width, height: rect.height))
        }
        return try XCTUnwrap(context.makeImage())
    }

    private let red = CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
    private let blue = CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)

    private func compare(_ first: CGImage, _ second: CGImage, ignoringSubtle: Bool = false) throws -> ImageDiff.Result {
        let prepared = try ImageDiff.prepare(first, second)
        let a = try XCTUnwrap(ImageDiff.pixels(of: prepared.first))
        let b = try XCTUnwrap(ImageDiff.pixels(of: prepared.second))
        return ImageDiff.compare(a, b, width: prepared.canvas.width, height: prepared.canvas.height, ignoringSubtle: ignoringSubtle)
    }

    func testCanvasAlignment() {
        let same = ImageDiff.canvas(CGSize(width: 1280, height: 800), CGSize(width: 1280, height: 800))
        XCTAssertEqual(same.alignment, .same)
        XCTAssertEqual([same.width, same.height], [1280, 800])
        // 1 倍和 2 倍的截图：缩到小的那张的大小
        let scaled = ImageDiff.canvas(CGSize(width: 2560, height: 1600), CGSize(width: 1280, height: 800))
        XCTAssertEqual(scaled.alignment, .scaled)
        XCTAssertEqual([scaled.width, scaled.height], [1280, 800])
        XCTAssertEqual(scaled.first, scaled.bounds)
        XCTAssertEqual(scaled.second, scaled.bounds)
        // 只差几个像素的不缩放，左上角对齐
        let nearly = ImageDiff.canvas(CGSize(width: 1280, height: 800), CGSize(width: 1282, height: 801))
        XCTAssertEqual(nearly.alignment, .topLeft)
        XCTAssertEqual([nearly.width, nearly.height], [1282, 801])
        XCTAssertEqual(nearly.first, CGRect(x: 0, y: 0, width: 1280, height: 800))
        // 横的和竖的
        let rotated = ImageDiff.canvas(CGSize(width: 400, height: 300), CGSize(width: 300, height: 400))
        XCTAssertEqual(rotated.alignment, .topLeft)
        XCTAssertEqual([rotated.width, rotated.height], [400, 400])
        XCTAssertNil(ImageDiff.note(same))
        XCTAssertEqual(ImageDiff.note(rotated), "两张图大小不同：按左上角对齐")
        // 太大了两张一起缩小，比例不变
        let huge = ImageDiff.canvas(CGSize(width: 5000, height: 4000), CGSize(width: 5000, height: 4000), maxPixels: 1_000_000)
        XCTAssertTrue(huge.reduced)
        XCTAssertLessThanOrEqual(huge.width * huge.height, 1_000_000)
        XCTAssertEqual(Double(huge.width) / Double(huge.height), 1.25, accuracy: 0.01)
        XCTAssertEqual(huge.first, huge.bounds)
        XCTAssertEqual(ImageDiff.note(huge), "图片太大，缩小到 \(huge.width) × \(huge.height) 对比")
    }

    func testFindsEachChangedArea() throws {
        let first = try image(100, 80)
        let second = try image(100, 80, fills: [(CGRect(x: 5, y: 5, width: 10, height: 10), red),
                                                 (CGRect(x: 70, y: 60, width: 4, height: 3), blue)])
        let result = try compare(first, second)
        XCTAssertEqual(result.changed, 100 + 12)
        XCTAssertEqual(result.regions, [CGRect(x: 5, y: 5, width: 10, height: 10), CGRect(x: 70, y: 60, width: 4, height: 3)])
        XCTAssertEqual(result.fraction, 112.0 / 8000, accuracy: 0.000001)
        XCTAssertEqual(ImageDiff.summary(result), "2 处不一样，占 1.4% 的像素")
        // 一样的图
        let identical = try compare(first, try image(100, 80))
        XCTAssertTrue(identical.isIdentical)
        XCTAssertTrue(identical.regions.isEmpty)
        XCTAssertEqual(ImageDiff.summary(identical), "没有找到不一样的地方")
    }

    func testNearbyChangesAreOneArea() throws {
        // 相隔几个像素、落在相邻格子里的两块算同一处；框在别的框里面的合成一个
        let first = try image(64, 64)
        let second = try image(64, 64, fills: [(CGRect(x: 10, y: 10, width: 4, height: 4), red),
                                               (CGRect(x: 18, y: 12, width: 4, height: 4), red)])
        XCTAssertEqual(try compare(first, second).regions, [CGRect(x: 10, y: 10, width: 12, height: 6)])
        XCTAssertEqual(ImageDiff.merged([CGRect(x: 0, y: 0, width: 50, height: 50), CGRect(x: 10, y: 10, width: 5, height: 5),
                                         CGRect(x: 60, y: 60, width: 5, height: 5)]),
                       [CGRect(x: 0, y: 0, width: 50, height: 50), CGRect(x: 60, y: 60, width: 5, height: 5)])
    }

    func testIgnoringSubtleDifferences() throws {
        let first = try image(64, 64)
        let faint = CGColor(srgbRed: 245.0 / 255, green: 1, blue: 1, alpha: 1)
        let second = try image(64, 64, fills: [(CGRect(x: 0, y: 0, width: 8, height: 8), faint),
                                               // 零星两个像素的杂点
                                               (CGRect(x: 40, y: 2, width: 2, height: 1), red),
                                               (CGRect(x: 30, y: 40, width: 5, height: 5), blue)])
        let exact = try compare(first, second)
        XCTAssertEqual(exact.changed, 64 + 2 + 25)
        XCTAssertEqual(exact.regions.count, 3)
        // 放宽以后颜色差一点的和零星的杂点不算，明显的那块还在
        let relaxed = try compare(first, second, ignoringSubtle: true)
        XCTAssertEqual(relaxed.changed, 25)
        XCTAssertEqual(relaxed.regions, [CGRect(x: 30, y: 40, width: 5, height: 5)])
        XCTAssertEqual(relaxed.mask.filter { $0 }.count, 25)
    }

    func testUncoveredAreaCountsAsChanged() throws {
        // 第二张高出两行：只有它盖到的地方算不一样
        let result = try compare(try image(10, 10), try image(10, 12))
        XCTAssertEqual(result.width, 10)
        XCTAssertEqual(result.height, 12)
        XCTAssertEqual(result.changed, 20)
        XCTAssertEqual(result.regions, [CGRect(x: 0, y: 10, width: 10, height: 2)])
    }

    func testDifferenceImageMarksChangedPixels() throws {
        let first = try image(40, 30, fills: [(CGRect(x: 0, y: 0, width: 40, height: 15), blue)])
        let second = try image(40, 30, fills: [(CGRect(x: 0, y: 0, width: 40, height: 15), blue),
                                               (CGRect(x: 20, y: 20, width: 3, height: 3), red)])
        let prepared = try ImageDiff.prepare(first, second)
        let outcome = ImageDiff.outcome(prepared, ignoringSubtle: false)
        XCTAssertEqual(outcome.regions, 1)
        XCTAssertFalse(outcome.isIdentical)
        let difference = try XCTUnwrap(outcome.difference)
        let pixels = try XCTUnwrap(ImageDiff.pixels(of: difference))
        func pixel(_ x: Int, _ y: Int) -> [UInt8] {
            let i = (y * 40 + x) * 4
            return Array(pixels[i..<i + 4])
        }
        let highlight = ImageDiff.highlight
        XCTAssertEqual(pixel(21, 21), [highlight.red, highlight.green, highlight.blue, 255])
        // 没变的地方褪成浅灰：蓝色变成偏浅的灰，白色还是白色
        let faded = pixel(5, 5)
        XCTAssertEqual(faded[0], faded[1])
        XCTAssertEqual(faded[1], faded[2])
        XCTAssertGreaterThan(faded[0], 150)
        XCTAssertLessThan(faded[0], 255)
        XCTAssertEqual(pixel(5, 26), [255, 255, 255, 255])
    }

    func testComposeFollowsTheView() throws {
        let first = try image(100, 50, background: red)
        let second = try image(100, 50, background: blue)
        let side = try XCTUnwrap(ImageDiff.compose(.sideBySide, first: first, second: second, difference: nil, split: 0.5, opacity: 0.5))
        XCTAssertEqual(side.width, 100 * 2 + 8)
        XCTAssertEqual(side.height, 50)
        // 滑动：分界线左边是旧的，右边是新的
        let swipe = try XCTUnwrap(ImageDiff.compose(.swipe, first: first, second: second, difference: nil, split: 0.3, opacity: 0.5))
        let swiped = try XCTUnwrap(ImageDiff.pixels(of: swipe))
        XCTAssertEqual(Array(swiped[(25 * 100 + 10) * 4..<(25 * 100 + 10) * 4 + 3]), [255, 0, 0])
        XCTAssertEqual(Array(swiped[(25 * 100 + 80) * 4..<(25 * 100 + 80) * 4 + 3]), [0, 0, 255])
        // 叠加：完全不透明时只看得到新的
        let overlay = try XCTUnwrap(ImageDiff.compose(.overlay, first: first, second: second, difference: nil, split: 0.5, opacity: 1))
        XCTAssertEqual(Array(try XCTUnwrap(ImageDiff.pixels(of: overlay))[0..<3]), [0, 0, 255])
        XCTAssertNil(ImageDiff.compose(.difference, first: first, second: second, difference: nil, split: 0.5, opacity: 0.5))
        XCTAssertNotNil(ImageDiff.png(side))
    }

    func testPercentages() {
        XCTAssertEqual(ImageDiff.percent(0.00005), "<0.01%")
        XCTAssertEqual(ImageDiff.percent(0.0123), "1.2%")
        XCTAssertEqual(ImageDiff.percent(0.004), "0.40%")
        XCTAssertEqual(ImageDiff.percent(0.5), "50%")
        XCTAssertEqual(ImageDiff.percent(0), "0.00%")
    }

    func testPluginNeedsTwoImages() {
        let plugin = CompareImagesPlugin().info
        func content(_ names: [String]) -> ClassifiedContent {
            ContentClassifier.classify(.files(names.map { URL(fileURLWithPath: "/tmp/\($0)") }))
        }
        XCTAssertTrue(plugin.canHandle(content(["旧.png", "新.jpg"])))
        XCTAssertFalse(plugin.canHandle(content(["旧.png"])))
        XCTAssertFalse(plugin.canHandle(content(["a.png", "b.png", "c.png"])))
        XCTAssertFalse(plugin.canHandle(content(["a.png", "说明.txt"])))
        XCTAssertFalse(plugin.canHandle(.empty))
    }

    @MainActor
    func testDemoScreenshotHasThreeChanges() throws {
        let sample = try XCTUnwrap(OverlayDemo.sampleScreenshot())
        let changed = try XCTUnwrap(CompareImagesPlugin.demoChanged(sample.image))
        let outcome = ImageDiff.outcome(try ImageDiff.prepare(sample.image, changed), ignoringSubtle: false)
        XCTAssertEqual(outcome.regions, 3)
    }
}
