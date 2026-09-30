import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Pop

final class SmartCropTests: XCTestCase {
    func testCropRectKeepsTheSubjectInside() {
        let landscape = CGSize(width: 4000, height: 3000)
        // 主体在最右边：方形框靠右，但不出界
        XCTAssertEqual(SmartCrop.cropRect(imageSize: landscape, ratio: 1, focus: CGRect(x: 3300, y: 1300, width: 400, height: 400)),
                       CGRect(x: 1000, y: 0, width: 3000, height: 3000))
        // 主体偏左一点：框的中心对准主体
        XCTAssertEqual(SmartCrop.cropRect(imageSize: landscape, ratio: 1, focus: CGRect(x: 1600, y: 1000, width: 400, height: 400)),
                       CGRect(x: 300, y: 0, width: 3000, height: 3000))
        // 找不到主体：取中间
        XCTAssertEqual(SmartCrop.cropRect(imageSize: landscape, ratio: 1, focus: nil), CGRect(x: 500, y: 0, width: 3000, height: 3000))
        // 16:9：宽度用满，高度取整
        XCTAssertEqual(SmartCrop.cropRect(imageSize: CGSize(width: 1000, height: 1000), ratio: SmartCrop.Ratio.sixteenNine.value, focus: nil),
                       CGRect(x: 0, y: 219, width: 1000, height: 562))
        // 横图裁 9:16：高度用满
        XCTAssertEqual(SmartCrop.cropRect(imageSize: CGSize(width: 1920, height: 1080), ratio: SmartCrop.Ratio.nineSixteen.value, focus: nil),
                       CGRect(x: 656, y: 0, width: 607, height: 1080))
        // 本来就是这个比例：整张
        XCTAssertEqual(SmartCrop.cropRect(imageSize: landscape, ratio: SmartCrop.Ratio.fourThree.value, focus: nil),
                       CGRect(x: 0, y: 0, width: 4000, height: 3000))
        XCTAssertEqual(SmartCrop.cropRect(imageSize: CGSize(width: 1920, height: 1080), ratio: SmartCrop.Ratio.sixteenNine.value, focus: nil),
                       CGRect(x: 0, y: 0, width: 1920, height: 1080))
    }

    func testRatioNames() {
        XCTAssertEqual(SmartCrop.Ratio.allCases.map(\.title), ["1:1 方形", "4:3", "3:4", "16:9", "9:16"])
        // 文件名里不能有冒号
        XCTAssertFalse(SmartCrop.Ratio.allCases.contains { $0.fileSuffix.contains(":") })
    }

    /// 浅灰底，右边一块红色
    private func sampleImage(width: Int, height: Int) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(srgbRed: 0.9, green: 0.1, blue: 0.1, alpha: 1))
        context.fill(CGRect(x: width * 3 / 4, y: height / 3, width: width / 8, height: height / 3))
        return try XCTUnwrap(context.makeImage())
    }

    private func writeImage(_ image: CGImage, to url: URL, type: UTType) throws {
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }

    private func pixelSize(_ url: URL) throws -> [Int] {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        return [(properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0,
                (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0]
    }

    func testFocusStaysInsideTheImage() throws {
        let image = try sampleImage(width: 1200, height: 600)
        // 找不找得到主体看 Vision；找到的话一定在图片范围里
        if let focus = SmartCrop.focus(of: image) {
            XCTAssertTrue(CGRect(x: 0, y: 0, width: 1200, height: 600).insetBy(dx: -1, dy: -1).contains(focus), "\(focus)")
        }
    }

    func testCropsACopyBesideTheOriginal() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "pop-crop-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        let image = try sampleImage(width: 400, height: 300)

        let png = folder.appending(path: "截图.png")
        try writeImage(image, to: png, type: .png)
        let square = try SmartCrop.crop(png, ratio: .square)
        XCTAssertEqual(square.lastPathComponent, "截图 1比1.png")
        XCTAssertEqual(try pixelSize(square), [300, 300])
        // 原图不动；再裁一次不覆盖
        XCTAssertEqual(try pixelSize(png), [400, 300])
        XCTAssertEqual(try SmartCrop.crop(png, ratio: .square).lastPathComponent, "截图 1比1 2.png")
        let wide = try SmartCrop.crop(png, ratio: .sixteenNine)
        XCTAssertEqual(wide.lastPathComponent, "截图 16比9.png")
        XCTAssertEqual(try pixelSize(wide), [400, 225])
        XCTAssertEqual(try pixelSize(try SmartCrop.crop(png, ratio: .nineSixteen)), [168, 300])

        // 照片存成 JPEG
        let photo = folder.appending(path: "照片.jpeg")
        try writeImage(image, to: photo, type: .jpeg)
        let portrait = try SmartCrop.crop(photo, ratio: .threeFour)
        XCTAssertEqual(portrait.lastPathComponent, "照片 3比4.jpg")
        XCTAssertEqual(try pixelSize(portrait), [225, 300])

        // 本来就是 4:3：不另存
        XCTAssertThrowsError(try SmartCrop.crop(photo, ratio: .fourThree)) { error in
            XCTAssertEqual((error as? SmartCrop.Failure)?.message, "「照片.jpeg」本来就是 4:3")
        }
        XCTAssertThrowsError(try SmartCrop.crop(folder.appending(path: "没有这张.png"), ratio: .square))
    }

    @MainActor
    func testPluginOffersEveryRatio() async throws {
        let plugin = CropImagePlugin()
        let photos = [URL(fileURLWithPath: "/tmp/a.jpg"), URL(fileURLWithPath: "/tmp/b.png")]
        XCTAssertTrue(plugin.info.canHandle(ContentClassifier.classify(.files(photos))))
        XCTAssertFalse(plugin.info.canHandle(ContentClassifier.classify(.files([URL(fileURLWithPath: "/tmp/合同.pdf")]))))
        let context = PluginContext(settings: AppSettings(), openSettings: {})
        let outcome = await plugin.run(ContentClassifier.classify(.files(photos)), context: context)
        guard case .card(let card) = outcome else { return XCTFail("应该返回结果卡片") }
        XCTAssertEqual(card.body, "把 2 张图片裁成哪种比例？")
        XCTAssertEqual(card.buttons.map(\.action), SmartCrop.Ratio.allCases.map { CardAction.cropImages(photos, $0) })
        let single = await plugin.run(ContentClassifier.classify(.files([photos[0]])), context: context)
        guard case .card(let one) = single else { return XCTFail("应该返回结果卡片") }
        XCTAssertEqual(one.body, "把「a.jpg」裁成哪种比例？")
    }
}
