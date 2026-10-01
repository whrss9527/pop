import AppKit
import ImageIO
import XCTest
@testable import Pop

final class AppIconTests: XCTestCase {
    /// 纯色的图，可以挖掉一块变透明（像素，左上角为原点）
    private func image(_ width: Int, _ height: Int, color: CGColor, clear: CGRect? = nil, alpha: Bool = true) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              bitmapInfo: alpha ? CGImageAlphaInfo.premultipliedLast.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(color)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        if let clear {
            context.clear(CGRect(x: clear.minX, y: CGFloat(height) - clear.maxY, width: clear.width, height: clear.height))
        }
        return try XCTUnwrap(context.makeImage())
    }

    /// 三条竖着的色带：左红、中绿、右蓝
    private func stripes(_ width: Int, _ height: Int) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let third = CGFloat(width) / 3
        for (index, color) in [CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1), CGColor(srgbRed: 0, green: 1, blue: 0, alpha: 1),
                               CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)].enumerated() {
            context.setFillColor(color)
            context.fill(CGRect(x: third * CGFloat(index), y: 0, width: third, height: CGFloat(height)))
        }
        return try XCTUnwrap(context.makeImage())
    }

    /// 读一个像素的 RGBA（0–255，左上角为原点）
    private func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> [Int] {
        var bytes = [UInt8](repeating: 0, count: 4)
        bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            context.draw(image, in: CGRect(x: -x, y: y - image.height + 1, width: image.width, height: image.height))
        }
        return bytes.map(Int.init)
    }

    /// 颜色差不多（缩放时每个通道可能差一点）
    private func assertColor(_ actual: [Int], _ expected: [Int], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.count, 4, file: file, line: line)
        for (a, e) in zip(actual, expected) where abs(a - e) > 3 {
            XCTFail("\(actual) 不是 \(expected)", file: file, line: line)
            return
        }
    }

    private func source(_ image: CGImage) -> IconMaker.Source {
        IconMaker.Source(image: image, focus: nil, hasTransparency: IconMaker.hasTransparency(image))
    }

    private func sizes(of data: Data) throws -> [Int] {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        return (0..<CGImageSourceGetCount(source)).compactMap { index in
            (CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any])?[kCGImagePropertyPixelWidth] as? Int
        }
    }

    func testSquircleHasRoundedCorners() {
        let rect = CGRect(x: 100, y: 100, width: 824, height: 824)
        let path = IconMaker.squircle(in: rect)
        XCTAssertEqual(path.boundingBox.minX, 100, accuracy: 0.5)
        XCTAssertEqual(path.boundingBox.maxY, 924, accuracy: 0.5)
        XCTAssertTrue(path.contains(CGPoint(x: 512, y: 512)))
        // 四条边的中间都到边上，拐角是圆的
        XCTAssertTrue(path.contains(CGPoint(x: 512, y: 102)))
        XCTAssertTrue(path.contains(CGPoint(x: 922, y: 512)))
        XCTAssertFalse(path.contains(CGPoint(x: 110, y: 110)))
        XCTAssertFalse(path.contains(CGPoint(x: 914, y: 914)))
        // 圆角和系统图标的差不多：对角线上离拐角 70～85 像素
        XCTAssertTrue(path.contains(CGPoint(x: 100 + 60, y: 100 + 60)))
        XCTAssertFalse(path.contains(CGPoint(x: 100 + 50, y: 100 + 50)))
    }

    func testRoundedMacOSIconLeavesAMarginAndRoundsTheCorners() throws {
        let red = source(try image(512, 512, color: CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)))
        let icon = try XCTUnwrap(IconMaker.macOS(red, side: 1024, options: IconMaker.Options()))
        XCTAssertEqual([icon.width, icon.height], [1024, 1024])
        assertColor(pixel(icon, 512, 512), [255, 0, 0, 255])
        assertColor(pixel(icon, 110, 512), [255, 0, 0, 255])
        // 四周留白（阴影在下面，上面一点都不透）
        XCTAssertEqual(pixel(icon, 512, 40)[3], 0)
        XCTAssertEqual(pixel(icon, 5, 5)[3], 0)
        // 拐角外面只有一点阴影
        XCTAssertLessThan(pixel(icon, 108, 108)[3], 100)
        // 底下有阴影
        XCTAssertGreaterThan(pixel(icon, 512, 935)[3], 0)
        // 「原样」铺满
        var plain = IconMaker.Options()
        plain.style = .plain
        let square = try XCTUnwrap(IconMaker.macOS(red, side: 64, options: plain))
        assertColor(pixel(square, 2, 2), [255, 0, 0, 255])
        assertColor(pixel(square, 61, 61), [255, 0, 0, 255])
        // 缩小后边上也不透
        XCTAssertGreaterThanOrEqual(pixel(square, 0, 0)[3], 250)
        XCTAssertGreaterThanOrEqual(pixel(square, 63, 63)[3], 250)
    }

    func testTransparencyMarginAndFill() throws {
        let opaque = try image(100, 100, color: CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1), alpha: false)
        XCTAssertFalse(IconMaker.hasTransparency(opaque))
        // 有透明通道但每个像素都不透明的，不算透明
        XCTAssertFalse(IconMaker.hasTransparency(try image(100, 100, color: CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))))
        let holed = try image(100, 100, color: CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1), clear: CGRect(x: 0, y: 0, width: 30, height: 30))
        XCTAssertTrue(IconMaker.hasTransparency(holed))

        var options = IconMaker.Options()
        options.margin = .narrow
        options.fill = .white
        let blue = source(opaque)
        // 留窄边：每边 10%，垫白色
        let framed = try XCTUnwrap(IconMaker.square(blue, side: 100, options: options))
        assertColor(pixel(framed, 4, 50), [255, 255, 255, 255])
        assertColor(pixel(framed, 50, 50), [0, 0, 255, 255])
        assertColor(pixel(framed, 15, 50), [0, 0, 255, 255])
        // 透明底留着透明，iOS 用的垫白色
        options.fill = .clear
        XCTAssertEqual(pixel(try XCTUnwrap(IconMaker.square(blue, side: 100, options: options)), 4, 50)[3], 0)
        assertColor(pixel(try XCTUnwrap(IconMaker.square(blue, side: 100, options: options, opaque: true)), 4, 50), [255, 255, 255, 255])
        options.fill = .black
        assertColor(pixel(try XCTUnwrap(IconMaker.square(blue, side: 100, options: options)), 4, 50), [0, 0, 0, 255])
    }

    func testNonSquareImagesAreCroppedOrFitted() throws {
        let wide = source(try stripes(300, 100))
        XCTAssertFalse(wide.isSquare)
        XCTAssertEqual(wide.region(.crop), CGRect(x: 100, y: 0, width: 100, height: 100))
        XCTAssertEqual(wide.region(.whole), CGRect(x: 0, y: 0, width: 300, height: 100))
        var options = IconMaker.Options()
        options.style = .plain
        // 裁成正方形：只留中间绿色那条
        let cropped = try XCTUnwrap(IconMaker.square(wide, side: 90, options: options))
        assertColor(pixel(cropped, 3, 45), [0, 255, 0, 255])
        assertColor(pixel(cropped, 86, 45), [0, 255, 0, 255])
        // 整张放进去：上下垫白色，左红右蓝
        options.fit = .whole
        let fitted = try XCTUnwrap(IconMaker.square(wide, side: 90, options: options))
        assertColor(pixel(fitted, 45, 5), [255, 255, 255, 255])
        assertColor(pixel(fitted, 5, 45), [255, 0, 0, 255])
        assertColor(pixel(fitted, 85, 45), [0, 0, 255, 255])
        // 宽高差不到 2% 的算正方形，不管怎么放都裁掉多出来的一点
        let almost = source(try image(1000, 990, color: CGColor(gray: 0.5, alpha: 1)))
        XCTAssertTrue(almost.isSquare)
        XCTAssertEqual(almost.region(.whole), CGRect(x: 5, y: 0, width: 990, height: 990))
    }

    func testIcnsHasEverySizeAndImageIOCanReadIt() throws {
        let red = source(try image(1024, 1024, color: CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)))
        let entries: [(type: String, png: Data)] = try IconMaker.icnsEntries.map { entry in
            (entry.type, try XCTUnwrap(IconMaker.png(try XCTUnwrap(IconMaker.macOS(red, side: entry.side, options: IconMaker.Options())))))
        }
        let data = IconMaker.icns(entries)
        XCTAssertEqual(String(decoding: data.prefix(4), as: UTF8.self), "icns")
        let length = data.subdata(in: 4..<8).reduce(0) { $0 << 8 | Int($1) }
        XCTAssertEqual(length, data.count)
        XCTAssertEqual(String(decoding: data.subdata(in: 8..<12), as: UTF8.self), "icp4")
        XCTAssertEqual(Set(try sizes(of: data)), [16, 32, 64, 128, 256, 512, 1024])
        XCTAssertTrue(try XCTUnwrap(NSImage(data: data)).isValid)
    }

    func testIcoHasThreeSizes() throws {
        let blue = source(try image(64, 64, color: CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)))
        let images: [(side: Int, png: Data)] = try IconMaker.faviconSides.map { side in
            (side, try XCTUnwrap(IconMaker.png(try XCTUnwrap(IconMaker.square(blue, side: side, options: IconMaker.Options())))))
        }
        let data = IconMaker.ico(images)
        XCTAssertEqual(Array(data.prefix(6)), [0, 0, 1, 0, 3, 0])
        XCTAssertEqual([data[6], data[22], data[38]], [16, 32, 48])
        // 第一张图紧跟在三条目录后面
        XCTAssertEqual(data.subdata(in: 18..<22).reversed().reduce(0) { $0 << 8 | Int($1) }, 6 + 16 * 3)
        XCTAssertEqual(Set(try sizes(of: data)), [16, 32, 48])
    }

    func testWriteMakesEveryFileInAFolderNextToTheImage() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "pop-icon-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let original = folder.appending(path: "Logo.png")
        let logo = source(try image(600, 600, color: CGColor(srgbRed: 0.2, green: 0.5, blue: 0.9, alpha: 1), clear: CGRect(x: 0, y: 0, width: 600, height: 100)))

        let output = try IconMaker.write(logo, options: IconMaker.Options(), beside: original)
        XCTAssertEqual(output.folder.lastPathComponent, "Logo 图标")
        XCTAssertEqual(output.files, 21)
        let files = try XCTUnwrap(FileManager.default.subpaths(atPath: output.folder.path(percentEncoded: false)))
            .filter { !$0.hasSuffix(".appiconset") && !["macOS", "iOS", "网站"].contains($0) }
        XCTAssertEqual(files.count, 21)

        let macOS = output.folder.appending(path: "macOS")
        XCTAssertEqual(Set(try sizes(of: Data(contentsOf: macOS.appending(path: "AppIcon.icns")))), [16, 32, 64, 128, 256, 512, 1024])
        let contents = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: macOS.appending(path: "AppIcon.appiconset/Contents.json"))) as? [String: Any])
        let images = try XCTUnwrap(contents["images"] as? [[String: String]])
        XCTAssertEqual(images.count, 10)
        XCTAssertEqual(images[1], ["filename": "icon_16x16@2x.png", "idiom": "mac", "scale": "2x", "size": "16x16"])
        let retina = try XCTUnwrap(TextRecognizer.cgImage(contentsOf: macOS.appending(path: "AppIcon.appiconset/icon_16x16@2x.png")))
        XCTAssertEqual([retina.width, retina.height], [32, 32])

        // iOS 的图标不透明：透明的地方垫白色
        let iOS = try XCTUnwrap(TextRecognizer.cgImage(contentsOf: output.folder.appending(path: "iOS/AppIcon.appiconset/AppIcon-1024.png")))
        XCTAssertEqual([iOS.width, iOS.height], [1024, 1024])
        assertColor(pixel(iOS, 512, 5), [255, 255, 255, 255])

        let web = output.folder.appending(path: "网站")
        XCTAssertEqual(Set(try sizes(of: Data(contentsOf: web.appending(path: "favicon.ico")))), [16, 32, 48])
        let touch = try XCTUnwrap(TextRecognizer.cgImage(contentsOf: web.appending(path: "apple-touch-icon.png")))
        XCTAssertEqual([touch.width, touch.height], [180, 180])
        let manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: web.appending(path: "site.webmanifest"))) as? [String: Any])
        XCTAssertEqual(manifest["name"] as? String, "Logo")
        XCTAssertEqual((manifest["icons"] as? [[String: String]])?.map { $0["sizes"] }, ["192x192", "512x512"])

        // 只要网站的；再生成一次换个文件夹
        var options = IconMaker.Options()
        options.macOS = false
        options.iOS = false
        let second = try IconMaker.write(logo, options: options, beside: original)
        XCTAssertEqual(second.folder.lastPathComponent, "Logo 图标 2")
        XCTAssertEqual(second.files, 7)
        XCTAssertFalse(FileManager.default.fileExists(atPath: second.folder.appending(path: "macOS").path(percentEncoded: false)))
        options.web = false
        XCTAssertThrowsError(try IconMaker.write(logo, options: options, beside: original))
    }

    @MainActor
    func testCardOptionsAndSummary() throws {
        let keys = [AppIconModel.styleKey, AppIconModel.fillKey, AppIconModel.outputsKey]
        let saved = keys.map { UserDefaults.standard.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, saved) {
                UserDefaults.standard.set(value, forKey: key)
            }
        }
        keys.forEach(UserDefaults.standard.removeObject(forKey:))

        let opaque = source(try image(200, 200, color: CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1), alpha: false))
        let model = AppIconModel(source: opaque, name: "Logo.png")
        XCTAssertEqual(model.options, IconMaker.Options())
        XCTAssertFalse(model.needsFill)
        XCTAssertNotNil(model.macOSPreview)
        XCTAssertEqual(model.faviconPreview?.width, 32)
        XCTAssertEqual(model.folderName, "Logo 图标")
        XCTAssertEqual(model.summary, "生成 macOS 的 .icns 和图标集、iOS 的 1024 图标、网站的 favicon，存在原图旁边的「Logo 图标」文件夹")
        // 留了边就要选底色
        model.options.margin = .wide
        XCTAssertTrue(model.needsFill)
        model.options.style = .plain
        model.options.iOS = false
        model.remember()
        let next = AppIconModel.savedOptions(for: opaque)
        XCTAssertEqual(next.style, .plain)
        XCTAssertEqual([next.macOS, next.iOS, next.web], [true, false, true])
        // 边距不记，有透明的地方时默认留窄边
        XCTAssertEqual(next.margin, .off)
        XCTAssertEqual(AppIconModel.savedOptions(for: source(try image(100, 100, color: CGColor(gray: 0, alpha: 1), clear: CGRect(x: 0, y: 0, width: 10, height: 10)))).margin, .narrow)

        model.options.macOS = false
        model.options.web = false
        XCTAssertEqual(model.summary, "至少选一种要生成的图标")
    }

    func testPluginTakesImageFiles() throws {
        let plugin = AppIconPlugin().info
        XCTAssertTrue(plugin.canHandle(ContentClassifier.classify(.files([URL(fileURLWithPath: "/tmp/Logo.png")]))))
        XCTAssertFalse(plugin.canHandle(ContentClassifier.classify(.files([URL(fileURLWithPath: "/tmp/说明.txt")]))))
        XCTAssertFalse(plugin.canHandle(.empty))
        let logo = try XCTUnwrap(AppIconPlugin.demoLogo())
        XCTAssertEqual([logo.width, logo.height], [1024, 1024])
        XCTAssertTrue(IconMaker.hasTransparency(logo))
    }
}
