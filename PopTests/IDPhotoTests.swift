import ImageIO
import XCTest
@testable import Pop

final class IDPhotoTests: XCTestCase {
    /// 400×500 的透明图，中间一个深色的「人」（左上角为原点：x 150–250，y 100–400）；脸在上面那一截
    private func sampleCutout() throws -> IDPhoto.Cutout {
        let context = try XCTUnwrap(CGContext(data: nil, width: 400, height: 500, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.clear(CGRect(x: 0, y: 0, width: 400, height: 500))
        context.setFillColor(CGColor(srgbRed: 0.2, green: 0.2, blue: 0.2, alpha: 1))
        context.fill(CGRect(x: 150, y: 100, width: 100, height: 300))
        let image = try XCTUnwrap(context.makeImage())
        return IDPhoto.Cutout(image: image, face: CGRect(x: 160, y: 100, width: 80, height: 90))
    }

    /// 读一个像素（左上角为原点）
    private func pixel(_ image: CGImage, x: Int, y: Int) throws -> (red: Int, green: Int, blue: Int) {
        let width = image.width
        let height = image.height
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                              space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let bytes = try XCTUnwrap(context.data?.assumingMemoryBound(to: UInt8.self))
        let offset = (y * width + x) * 4
        return (Int(bytes[offset]), Int(bytes[offset + 1]), Int(bytes[offset + 2]))
    }

    private func assertColor(_ color: (red: Int, green: Int, blue: Int), _ expected: IDPhoto.Background,
                             file: StaticString = #filePath, line: UInt = #line) {
        let rgb = expected.rgb
        XCTAssertEqual(Double(color.red), Double(rgb.red), accuracy: 2, file: file, line: line)
        XCTAssertEqual(Double(color.green), Double(rgb.green), accuracy: 2, file: file, line: line)
        XCTAssertEqual(Double(color.blue), Double(rgb.blue), accuracy: 2, file: file, line: line)
    }

    func testCropFollowsTheFace() {
        let aspect: CGFloat = 295.0 / 413.0
        let crop = IDPhoto.cropRect(imageSize: CGSize(width: 3000, height: 4000), face: CGRect(x: 1300, y: 1200, width: 400, height: 460),
                                    aspect: aspect)
        XCTAssertEqual(crop.height, 1000, accuracy: 0.5)
        XCTAssertEqual(crop.width, 1000 * aspect, accuracy: 0.5)
        XCTAssertEqual(crop.midX, 1500, accuracy: 0.5)
        // 脸的中心在从上往下 47% 的地方
        XCTAssertEqual((1430 - crop.minY) / crop.height, 0.47, accuracy: 0.001)

        // 脸贴着照片上边：框不出界
        let high = IDPhoto.cropRect(imageSize: CGSize(width: 3000, height: 4000), face: CGRect(x: 1300, y: 20, width: 400, height: 460),
                                    aspect: aspect)
        XCTAssertEqual(high.minY, 0)
        // 脸很大、照片很小：按比例缩小，还在照片里面
        let tight = IDPhoto.cropRect(imageSize: CGSize(width: 500, height: 600), face: CGRect(x: 100, y: 100, width: 300, height: 400),
                                     aspect: aspect)
        XCTAssertEqual(tight.width / tight.height, aspect, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(tight.minX, 0)
        XCTAssertGreaterThanOrEqual(tight.minY, 0)
        XCTAssertLessThanOrEqual(tight.maxX, 500.001)
        XCTAssertLessThanOrEqual(tight.maxY, 600.001)
        // 没有人脸：中间最大的一块
        let middle = IDPhoto.cropRect(imageSize: CGSize(width: 1000, height: 1000), face: nil, aspect: aspect)
        XCTAssertEqual(middle.height, 1000, accuracy: 0.001)
        XCTAssertEqual(middle.midX, 500, accuracy: 0.001)
        XCTAssertEqual(middle.minY, 0, accuracy: 0.001)
    }

    func testVisionBoxesBecomePixelRects() {
        let rect = IDPhoto.pixelRect(CGRect(x: 0.25, y: 0.5, width: 0.5, height: 0.25), width: 400, height: 800)
        XCTAssertEqual(rect, CGRect(x: 100, y: 200, width: 200, height: 200))
    }

    func testComposesBackgroundAndSize() throws {
        let cutout = try sampleCutout()
        let blue = try XCTUnwrap(IDPhoto.compose(cutout, background: .blue, size: .oneInch))
        XCTAssertEqual(blue.width, 295)
        XCTAssertEqual(blue.height, 413)
        for (x, y) in [(0, 0), (294, 0), (0, 412), (294, 412)] {
            assertColor(try pixel(blue, x: x, y: y), .blue)
        }
        // 人还在中间
        let center = try pixel(blue, x: 147, y: 206)
        XCTAssertLessThan(center.red, 80)
        XCTAssertLessThan(center.blue, 80)

        let white = try XCTUnwrap(IDPhoto.compose(cutout, background: .white, size: .original))
        XCTAssertEqual(white.width, 400)
        XCTAssertEqual(white.height, 500)
        assertColor(try pixel(white, x: 5, y: 5), .white)
        let red = try XCTUnwrap(IDPhoto.compose(cutout, background: .red, size: .twoInch, maxSide: 100))
        XCTAssertEqual(max(red.width, red.height), 100)
        assertColor(try pixel(red, x: 0, y: 0), .red)
    }

    func testSavesJPEGBesideTheOriginal() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "pop-id-photo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        let original = folder.appending(path: "照片.png")
        let cutout = try sampleCutout()
        let image = try XCTUnwrap(IDPhoto.compose(cutout, background: .blue, size: .oneInch))

        let saved = try IDPhoto.save(image, beside: original, background: .blue, size: .oneInch)
        XCTAssertEqual(saved.lastPathComponent, "照片 蓝底 一寸.jpg")
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(saved as CFURL, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        XCTAssertEqual((properties[kCGImagePropertyDPIWidth] as? NSNumber)?.intValue, 300)
        XCTAssertEqual((properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue, 295)
        XCTAssertEqual(try IDPhoto.save(image, beside: original, background: .blue, size: .oneInch).lastPathComponent, "照片 蓝底 一寸 2.jpg")
        XCTAssertEqual(try IDPhoto.save(image, beside: original, background: .white, size: .original).lastPathComponent, "照片 白底.jpg")
    }

    @MainActor
    func testCardPreviewsAndRemembersTheBackground() async throws {
        let key = IDPhotoModel.backgroundKey
        let saved = UserDefaults.standard.string(forKey: key)
        addTeardownBlock {
            if let saved {
                UserDefaults.standard.set(saved, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        UserDefaults.standard.removeObject(forKey: key)
        let model = IDPhotoModel(file: URL(fileURLWithPath: "/tmp/pop-id-photo.png"), cutout: try sampleCutout())
        XCTAssertEqual(model.background, .blue)
        XCTAssertTrue(model.canSave)
        XCTAssertNil(model.message)
        for _ in 0..<100 where model.preview?.width != 295 {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(model.preview?.height, 413)
        model.size = .original
        for _ in 0..<100 where model.preview?.width != 400 {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(model.preview?.height, 500)

        model.background = .red
        XCTAssertEqual(IDPhotoModel(file: URL(fileURLWithPath: "/tmp/a.png"), cutout: try sampleCutout()).background, .red)
        // 没找到人脸时说明按中间裁剪
        var faceless = try sampleCutout()
        faceless.face = nil
        XCTAssertNotNil(IDPhotoModel(file: URL(fileURLWithPath: "/tmp/b.png"), cutout: faceless).message)
    }

    @MainActor
    func testPluginOpensTheCardForPhotos() async {
        let plugin = IDPhotoPlugin()
        let photo = URL(fileURLWithPath: "/tmp/证件照.jpg")
        XCTAssertTrue(plugin.info.canHandle(ContentClassifier.classify(.files([photo]))))
        XCTAssertFalse(plugin.info.canHandle(ContentClassifier.classify(.files([URL(fileURLWithPath: "/tmp/合同.pdf")]))))
        let outcome = await plugin.run(ContentClassifier.classify(.files([photo])), context: PluginContext(settings: AppSettings(), openSettings: {}))
        XCTAssertEqual(outcome, .idPhoto(photo))
    }
}
