import XCTest
@testable import Pop

final class BeautifyTests: XCTestCase {
    func testCanvasAddsPaddingAndFillsOutTheRatio() {
        let image = CGSize(width: 1000, height: 500)
        var options = ScreenshotBeautifier.Options()
        // 中等留白是长边的 9%
        XCTAssertEqual(ScreenshotBeautifier.canvasSize(for: image, options: options), CGSize(width: 1180, height: 680))
        options.ratio = .square
        XCTAssertEqual(ScreenshotBeautifier.canvasSize(for: image, options: options), CGSize(width: 1180, height: 1180))
        // 比 16:9 窄：补宽度
        options.ratio = .sixteenNine
        XCTAssertEqual(ScreenshotBeautifier.canvasSize(for: image, options: options), CGSize(width: 1209, height: 680))
        // 比 4:3 宽：补高度
        options.ratio = .fourThree
        XCTAssertEqual(ScreenshotBeautifier.canvasSize(for: image, options: options), CGSize(width: 1180, height: 885))
        options.ratio = .auto
        options.padding = .small
        XCTAssertEqual(ScreenshotBeautifier.canvasSize(for: image, options: options), CGSize(width: 1100, height: 600))
    }

    func testImageSitsInTheMiddleWithRoundedCorners() {
        let rect = ScreenshotBeautifier.imageRect(for: CGSize(width: 1000, height: 500), in: CGSize(width: 1209, height: 680))
        XCTAssertEqual(rect, CGRect(x: 105, y: 90, width: 1000, height: 500))
        XCTAssertEqual(ScreenshotBeautifier.cornerRadius(for: CGSize(width: 1600, height: 1000)), 25)
        // 小图至少 8 像素
        XCTAssertEqual(ScreenshotBeautifier.cornerRadius(for: CGSize(width: 200, height: 100)), 8)
    }

    func testRendersOnAGradientOrTransparent() throws {
        let red = try XCTUnwrap(Self.solidImage(width: 100, height: 50, red: 255))
        var options = ScreenshotBeautifier.Options(background: .sky, padding: .small, ratio: .auto, corners: false, shadow: false)
        let onSky = try XCTUnwrap(ScreenshotBeautifier.render(red, options: options))
        XCTAssertEqual(onSky.width, 110)
        XCTAssertEqual(onSky.height, 60)
        // 四周是渐变，不透明；中间是截图
        XCTAssertEqual(Self.pixel(onSky, x: 1, y: 1)?.alpha, 255)
        XCTAssertEqual(Self.pixel(onSky, x: 55, y: 30)?.red, 255)
        options.background = nil
        let clear = try XCTUnwrap(ScreenshotBeautifier.render(red, options: options))
        XCTAssertEqual(Self.pixel(clear, x: 1, y: 1)?.alpha, 0)
        XCTAssertEqual(Self.pixel(clear, x: 55, y: 30)?.alpha, 255)
    }

    func testDownscalesLongSideForThePreview() throws {
        let image = try XCTUnwrap(Self.solidImage(width: 1800, height: 600, red: 0))
        let small = ScreenshotBeautifier.downscaled(image, maxSide: 900)
        XCTAssertEqual(small.width, 900)
        XCTAssertEqual(small.height, 300)
        // 本来就小的不动
        XCTAssertEqual(ScreenshotBeautifier.downscaled(small, maxSide: 900).width, 900)
    }

    func testRemembersTheLastLook() {
        let defaults = UserDefaults.standard
        let keys = ScreenshotBeautifier.Options.keys
        let previous = keys.map { defaults.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, previous) {
                defaults.set(value, forKey: key)
            }
        }
        ScreenshotBeautifier.Options(background: .mint, padding: .large, ratio: .square, corners: false, shadow: true).save()
        XCTAssertEqual(ScreenshotBeautifier.Options.saved,
                       ScreenshotBeautifier.Options(background: .mint, padding: .large, ratio: .square, corners: false, shadow: true))
        // 透明的存成 clear，读回来还是没有背景
        ScreenshotBeautifier.Options(background: nil).save()
        XCTAssertNil(ScreenshotBeautifier.Options.saved.background)
        // 没存过的用默认的样子
        keys.forEach(defaults.removeObject(forKey:))
        XCTAssertEqual(ScreenshotBeautifier.Options.saved, ScreenshotBeautifier.Options())
    }

    private static func solidImage(width: Int, height: Int, red: CGFloat) -> CGImage? {
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(CGColor(srgbRed: red / 255, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    /// 取一个像素（左下角为原点），RGBA 各 0～255
    private static func pixel(_ image: CGImage, x: Int, y: Int) -> (red: UInt8, alpha: UInt8)? {
        var data = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(data: &data, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: -x, y: -y, width: image.width, height: image.height))
        return (data[0], data[3])
    }
}
