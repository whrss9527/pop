import CoreText
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Pop

final class RedactionTests: XCTestCase {
    func testFindsPersonalInfoInText() {
        let text = "电话 138 1234 5678，邮箱 pop@example.com，身份证 11010519491231002X，卡号 6217 0000 1234 5670，车牌 京A12345"
        let found = Redaction.sensitiveRanges(in: text)
        XCTAssertEqual(found.map { $0.kind }, [.phone, .email, .idNumber, .idNumber, .plate])
        XCTAssertEqual(found.map { String(text[$0.range]) },
                       ["138 1234 5678", "pop@example.com", "11010519491231002X", "6217 0000 1234 5670", "京A12345"])
        // 校验不通过的长数字（订单号）不算
        XCTAssertTrue(Redaction.sensitiveRanges(in: "订单号 202609301234567，金额 128 元").isEmpty)
    }

    func testConvertsVisionCoordinates() {
        XCTAssertEqual(Redaction.pixelRect(CGRect(x: 0.25, y: 0.5, width: 0.5, height: 0.25), in: CGSize(width: 400, height: 200)),
                       CGRect(x: 100, y: 50, width: 200, height: 50))
    }

    func testPixelatesOnlyTheRegions() throws {
        let image = try XCTUnwrap(Self.checkerboard(size: 60))
        let region = Redaction.Region(rect: CGRect(x: 0, y: 0, width: 30, height: 30), kind: .text)
        let result = try XCTUnwrap(Redaction.pixelate(image, regions: [region]))
        let pixels = try XCTUnwrap(Self.rgba(result))
        // 打码的地方：一格里的颜色都一样，是黑白两色的平均（灰色）
        XCTAssertEqual(Self.pixel(pixels, 5, 5, width: 60), Self.pixel(pixels, 6, 5, width: 60))
        XCTAssertEqual(Self.pixel(pixels, 5, 5, width: 60), Self.pixel(pixels, 5, 6, width: 60))
        let gray = Int(Self.pixel(pixels, 5, 5, width: 60)[0])
        XCTAssertTrue((70...190).contains(gray), "\(gray)")
        // 别的地方不动：还是黑白相间
        XCTAssertNotEqual(Self.pixel(pixels, 45, 45, width: 60), Self.pixel(pixels, 46, 45, width: 60))
    }

    func testRecognizesAndHidesAPhoneNumber() throws {
        let image = try XCTUnwrap(Self.textImage("手机 13812345678"))
        let regions = try Redaction.find(in: image, targets: [.personalInfo])
        XCTAssertEqual(regions.map(\.kind), [.phone])
        // 只盖住号码，「手机」两个字不在里面
        let rect = try XCTUnwrap(regions.first?.rect)
        XCTAssertGreaterThan(rect.minX, 100)
        let redacted = try XCTUnwrap(Redaction.pixelate(image, regions: regions))
        let text = try TextRecognizer.recognizeLines(in: redacted)
        XCTAssertFalse(text.filter(\.isNumber).contains("13812345678"), text)
    }

    func testSavesARedactedCopyNextToTheOriginal() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "RedactionTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "截图.png")
        try Self.writePNG(XCTUnwrap(Self.textImage("邮箱 pop@example.com")), to: url)
        let original = try Data(contentsOf: url)
        let (output, regions) = try Redaction.redact(url, targets: Redaction.defaultTargets)
        XCTAssertEqual(output.lastPathComponent, "截图 打码.png")
        XCTAssertEqual(regions.map(\.kind), [.email])
        XCTAssertEqual(try Data(contentsOf: url), original)
        XCTAssertNotNil(CGImageSourceCreateWithURL(output as CFURL, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) })

        let blank = folder.appending(path: "空白.png")
        try Self.writePNG(XCTUnwrap(Self.textImage("")), to: blank)
        XCTAssertThrowsError(try Redaction.redact(blank, targets: Redaction.defaultTargets)) { error in
            XCTAssertEqual((error as? Redaction.Failure)?.message, "「空白.png」里没找到要打码的地方")
        }
    }

    func testCardOffersSavingOnlyWhenSomethingWasFound() {
        let url = URL(fileURLWithPath: "/tmp/截图.png")
        let empty = RedactPlugin.card([url], preview: Redaction.Preview(png: Data(), regions: []))
        XCTAssertEqual(empty.buttons.map(\.action), [.redactImages([url], [.faces, .allText])])
        let regions = [Redaction.Region(rect: .zero, kind: .phone), Redaction.Region(rect: .zero, kind: .face)]
        let found = RedactPlugin.card([url], preview: Redaction.Preview(png: Data(), regions: regions))
        XCTAssertEqual(found.buttons.map(\.action), [.redactImages([url], Redaction.defaultTargets), .redactImages([url], [.faces, .allText])])
        XCTAssertEqual(found.detail, "找到人脸 1 处、电话号码 1 处，预览里已经打上马赛克；存的时候另存一份，原图不动")
        XCTAssertEqual(Redaction.summary([]), "")
    }

    // MARK: - 测试用的图片

    /// 1 像素一格的黑白棋盘
    private static func checkerboard(size: Int) -> CGImage? {
        guard let context = makeContext(width: size, height: size) else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        for y in 0..<size {
            for x in 0..<size where (x + y) % 2 == 0 {
                context.fill(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }
        return context.makeImage()
    }

    /// 白底黑字的一行字，字号 56
    private static func textImage(_ text: String) -> CGImage? {
        guard let context = makeContext(width: 900, height: 160) else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 900, height: 160))
        let font = CTFontCreateUIFontForLanguage(.system, 56, nil) ?? CTFontCreateWithName("Helvetica" as CFString, 56, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1),
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        context.textPosition = CGPoint(x: 40, y: 56)
        CTLineDraw(line, context)
        return context.makeImage()
    }

    private static func makeContext(width: Int, height: Int) -> CGContext? {
        CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    /// 按行排的 RGBA 像素，第一行是图片最上面一行
    private static func rgba(_ image: CGImage) -> [UInt8]? {
        guard let context = makeContext(width: image.width, height: image.height) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let data = context.data else { return nil }
        let count = image.width * image.height * 4
        return Array(UnsafeBufferPointer(start: data.bindMemory(to: UInt8.self, capacity: count), count: count))
    }

    private static func pixel(_ pixels: [UInt8], _ x: Int, _ y: Int, width: Int) -> [UInt8] {
        let offset = (y * width + x) * 4
        return Array(pixels[offset..<offset + 4])
    }

    private static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }
}
