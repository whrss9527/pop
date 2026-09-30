import XCTest
@testable import Pop

final class TextImageTests: XCTestCase {
    func testTidiesTheText() {
        XCTAssertEqual(TextImage.normalized("\n\n  第一段  \r\n\r\n\r\n第二段\t尾巴 \n\t缩进\n\n\n"), "  第一段\n\n第二段    尾巴\n    缩进")
        XCTAssertEqual(TextImage.normalized(" \n \n"), "")
        // 太长的截掉，末尾说还剩多少字
        let long = String(repeating: "字", count: TextImage.maxCharacters + 5)
        XCTAssertEqual(TextImage.limited(long), String(repeating: "字", count: TextImage.maxCharacters) + "\n\n……（后面还有 5 字没画）")
        XCTAssertEqual(TextImage.limited("短"), "短")
    }

    /// 读一个像素（左上角为原点）
    private func pixel(_ png: Data, x: Int, y: Int) throws -> (red: Int, green: Int, blue: Int) {
        let image = try XCTUnwrap(TextRecognizer.cgImage(from: png))
        let context = try XCTUnwrap(CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                              bytesPerRow: image.width * 4,
                                              space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let bytes = try XCTUnwrap(context.data?.assumingMemoryBound(to: UInt8.self))
        let offset = (y * image.width + x) * 4
        return (Int(bytes[offset]), Int(bytes[offset + 1]), Int(bytes[offset + 2]))
    }

    func testRendersAPhoneWidthImage() throws {
        let text = "今天把 Pop 更新到了新版本。\n\n文字转图片会把一段话排成一张宽 1080 像素的长图，发到不方便贴长文字的地方。"
        let short = try XCTUnwrap(TextImage.render("一行", style: .paper))
        let png = try XCTUnwrap(TextImage.render(text, style: .paper))
        let image = try XCTUnwrap(NSBitmapImageRep(data: png))
        XCTAssertEqual(image.pixelsWide, 1080)
        // 字多的图更高
        XCTAssertGreaterThan(image.pixelsHigh, try XCTUnwrap(NSBitmapImageRep(data: short)).pixelsHigh)
        // 左上角是底色：白底、深色
        let paper = try pixel(png, x: 4, y: 4)
        XCTAssertGreaterThan(paper.red + paper.green + paper.blue, 740)
        let night = try pixel(try XCTUnwrap(TextImage.render(text, style: .night)), x: 4, y: 4)
        XCTAssertLessThan(night.red + night.green + night.blue, 120)
        XCTAssertNil(TextImage.render("  \n\n "))
    }

    @MainActor
    func testCardOffersTheOtherStyles() async throws {
        let text = "一段要发出去的话"
        let outcome = await TextImagePlugin().run(ContentClassifier.classify(.text(text)),
                                                  context: PluginContext(settings: AppSettings(), openSettings: {}))
        guard case .card(let card) = outcome else { return XCTFail("应该返回结果卡片") }
        XCTAssertEqual(card.title, "文字转图片")
        XCTAssertNotNil(card.image)
        XCTAssertEqual(card.buttons.map(\.title), ["复制图片", "存储", "贴到屏幕", "米黄", "深色"])
        XCTAssertEqual(card.buttons.suffix(2).map(\.action), [.textImage(text, .warm), .textImage(text, .night)])
        guard case .card(let night) = TextImagePlugin.outcome(text, style: .night) else { return XCTFail("应该返回结果卡片") }
        XCTAssertEqual(night.buttons.suffix(2).map(\.title), ["白底", "米黄"])
    }

    func testBarcodeRoundTrip() throws {
        XCTAssertTrue(QRCode.canMakeBarcode("SKU-2026-0930"))
        XCTAssertFalse(QRCode.canMakeBarcode("条形码"))
        XCTAssertFalse(QRCode.canMakeBarcode(""))
        XCTAssertFalse(QRCode.canMakeBarcode(String(repeating: "A", count: 81)))
        XCTAssertNil(QRCode.barcode("条形码"))
        let png = try XCTUnwrap(QRCode.barcode("SKU-2026-0930"))
        let image = try XCTUnwrap(TextRecognizer.cgImage(from: png))
        XCTAssertGreaterThan(image.width, image.height)
        XCTAssertEqual(QRCode.decode(image), ["SKU-2026-0930"])
    }

    @MainActor
    func testQRCardOffersABarcodeForPlainText() async throws {
        let context = PluginContext(settings: AppSettings(), openSettings: {})
        guard case .card(let latin) = await QRCodePlugin().run(ContentClassifier.classify(.text("ABC-123")), context: context) else {
            return XCTFail("应该返回结果卡片")
        }
        XCTAssertEqual(latin.buttons.map(\.action).last, .barcode("ABC-123"))
        guard case .card(let chinese) = await QRCodePlugin().run(ContentClassifier.classify(.text("你好")), context: context) else {
            return XCTFail("应该返回结果卡片")
        }
        XCTAssertFalse(chinese.buttons.contains { $0.title == "条形码" })
    }
}
