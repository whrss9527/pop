import AppKit
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import XCTest
@testable import Pop

/// 测试用的临时文件夹和图片
private enum Canvas {
    static func folder(_ test: XCTestCase) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "pop-image-tools-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        test.addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return folder
    }

    static func solid(width: Int, height: Int, gray: CGFloat) -> CGImage? {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        context?.setFillColor(CGColor(gray: gray, alpha: 1))
        context?.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context?.makeImage()
    }

    /// 杂色图：JPEG 很难压小
    static func noise(width: Int, height: Int) -> CGImage? {
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
              let bytes = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        var seed: UInt32 = 930
        for index in 0..<(width * height * 4) {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            bytes[index] = UInt8(truncatingIfNeeded: seed >> 24)
        }
        return context.makeImage()
    }

    static func write(_ image: CGImage, to url: URL, type: UTType) -> Bool {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else { return false }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination)
    }

    /// 有多少像素的红色通道比 threshold 暗
    static func darkPixels(_ image: CGImage, below threshold: UInt8) -> Int {
        let width = image.width
        let height = image.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 0 }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let bytes = context.data?.assumingMemoryBound(to: UInt8.self) else { return 0 }
        var count = 0
        for pixel in 0..<(width * height) where bytes[pixel * 4] < threshold {
            count += 1
        }
        return count
    }
}

final class WatermarkTests: XCTestCase {
    func testWatermarkCoversTheWholeImage() throws {
        let white = try XCTUnwrap(Canvas.solid(width: 600, height: 400, gray: 1))
        let marked = try XCTUnwrap(ImageWatermark.apply(white, text: "仅供测试使用", opacity: 0.5))
        XCTAssertEqual(marked.width, 600)
        XCTAssertEqual(marked.height, 400)
        XCTAssertGreaterThan(Canvas.darkPixels(marked, below: 235), 600 * 400 / 50)
        // 斜着铺满：四个角上都有字
        for corner in [CGRect(x: 0, y: 0, width: 300, height: 200), CGRect(x: 300, y: 0, width: 300, height: 200),
                       CGRect(x: 0, y: 200, width: 300, height: 200), CGRect(x: 300, y: 200, width: 300, height: 200)] {
            let part = try XCTUnwrap(marked.cropping(to: corner))
            XCTAssertGreaterThan(Canvas.darkPixels(part, below: 235), 100, "\(corner)")
        }
        // 越浓越深
        let light = try XCTUnwrap(ImageWatermark.apply(white, text: "仅供测试使用", opacity: 0.1))
        XCTAssertLessThan(Canvas.darkPixels(light, below: 200), Canvas.darkPixels(marked, below: 200))
        // 没有文字就不加
        let plain = try XCTUnwrap(ImageWatermark.apply(white, text: "  ", opacity: 0.5))
        XCTAssertEqual(Canvas.darkPixels(plain, below: 235), 0)
    }

    func testSavesBesideTheOriginal() throws {
        let folder = try Canvas.folder(self)
        let png = folder.appending(path: "身份证.png")
        XCTAssertTrue(Canvas.write(try XCTUnwrap(Canvas.solid(width: 320, height: 200, gray: 0.9)), to: png, type: .png))
        let before = try Data(contentsOf: png)
        let output = try ImageWatermark.watermark(png, text: "仅供办理业务使用", opacity: 0.4)
        XCTAssertEqual(output.lastPathComponent, "身份证 水印.png")
        XCTAssertEqual(try Data(contentsOf: png), before, "原图不动")
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(output as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(image.width, 320)
        XCTAssertGreaterThan(Canvas.darkPixels(image, below: 215), 0)

        let jpeg = folder.appending(path: "照片.jpg")
        XCTAssertTrue(Canvas.write(try XCTUnwrap(Canvas.solid(width: 320, height: 200, gray: 0.9)), to: jpeg, type: .jpeg))
        XCTAssertEqual(try ImageWatermark.watermark(jpeg, text: "样张", opacity: 0.4).lastPathComponent, "照片 水印.jpg")
        XCTAssertThrowsError(try ImageWatermark.watermark(folder.appending(path: "没有这张.png"), text: "样张", opacity: 0.4))
    }

    func testWatermarksEveryPDFPage() throws {
        let folder = try Canvas.folder(self)
        let pdf = folder.appending(path: "合同.pdf")
        let document = PDFDocument()
        for index in 0..<2 {
            let image = try XCTUnwrap(Canvas.solid(width: 600, height: 800, gray: 0.95))
            let page = try XCTUnwrap(PDFPage(image: NSImage(cgImage: image, size: NSSize(width: 600, height: 800))))
            document.insert(page, at: index)
        }
        // 第二页是横着放的扫描件
        document.page(at: 1)?.rotation = 90
        XCTAssertTrue(document.write(to: pdf))

        let output = try ImageWatermark.watermark(pdf, text: "仅供入职使用", opacity: 0.4)
        XCTAssertEqual(output.lastPathComponent, "合同 水印.pdf")
        let marked = try XCTUnwrap(PDFDocument(url: output))
        XCTAssertEqual(marked.pageCount, 2)
        // 原来的页面只有图片，读得出的字都是水印
        for index in 0..<2 {
            let text = marked.page(at: index)?.string ?? ""
            XCTAssertTrue(text.contains("仅"), "第 \(index + 1) 页：\(text.prefix(40))")
        }
        let upright = try XCTUnwrap(marked.page(at: 0)?.bounds(for: .cropBox))
        XCTAssertEqual(upright.width, 600, accuracy: 1)
        XCTAssertEqual(upright.height, 800, accuracy: 1)
        let turned = try XCTUnwrap(marked.page(at: 1)?.bounds(for: .cropBox))
        XCTAssertEqual(turned.width, 800, accuracy: 1)
        XCTAssertEqual(turned.height, 600, accuracy: 1)
        XCTAssertEqual(try ImageWatermark.watermark(pdf, text: "仅供入职使用", opacity: 0.4).lastPathComponent, "合同 水印 2.pdf")

        let preview = try XCTUnwrap(ImageWatermark.preview(pdf, text: "样张", opacity: 0.4, maxSide: 200))
        XCTAssertEqual(preview.height, 200)
        XCTAssertEqual(preview.width, 150)
        // 预览很小，字的笔画被抗锯齿冲淡：和没有水印的第一页（灰度 242）比，有变暗的像素就行
        let plain = try XCTUnwrap(ImageWatermark.preview(pdf, text: "", opacity: 0.4, maxSide: 200))
        XCTAssertEqual(Canvas.darkPixels(plain, below: 236), 0)
        XCTAssertGreaterThan(Canvas.darkPixels(preview, below: 236), 0)
    }

    @MainActor
    func testPluginTakesImagesAndPDFs() async {
        let plugin = WatermarkPlugin()
        let pdf = URL(fileURLWithPath: "/tmp/合同.pdf")
        let photo = URL(fileURLWithPath: "/tmp/身份证.jpg")
        XCTAssertTrue(plugin.info.canHandle(ContentClassifier.classify(.files([pdf]))))
        XCTAssertTrue(plugin.info.canHandle(ContentClassifier.classify(.files([photo]))))
        XCTAssertFalse(plugin.info.canHandle(ContentClassifier.classify(.files([URL(fileURLWithPath: "/tmp/说明.txt")]))))
        let content = ContentClassifier.classify(.files([pdf, URL(fileURLWithPath: "/tmp/说明.txt"), photo]))
        XCTAssertEqual(WatermarkPlugin.files(in: content), [pdf, photo])
        // 插件包自己弹出加水印的卡片
        let outcome = await plugin.run(content, context: PluginContext(settings: AppSettings(), openSettings: {}))
        guard case .present = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(WatermarkModel(files: [pdf, photo]).countLabel(2), "2 个文件")
        XCTAssertEqual(WatermarkModel(files: [photo]).countLabel(1), "1 张图片")
    }

    @MainActor
    func testCardRemembersTheText() throws {
        let key = ImageWatermark.textKey
        let saved = UserDefaults.standard.string(forKey: key)
        addTeardownBlock {
            if let saved {
                UserDefaults.standard.set(saved, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        UserDefaults.standard.removeObject(forKey: key)
        let model = WatermarkModel(files: [URL(fileURLWithPath: "/tmp/pop-missing.png")])
        XCTAssertEqual(model.text, ImageWatermark.defaultText)
        model.text = "仅供入职使用"
        model.remember()
        XCTAssertEqual(WatermarkModel(files: []).text, "仅供入职使用")
        model.text = "   "
        XCTAssertFalse(model.canApply)
    }
}

final class ImageSizeLimitTests: XCTestCase {
    func testCompressesUnderTheLimit() throws {
        let folder = try Canvas.folder(self)
        let png = folder.appending(path: "报名照片.png")
        XCTAssertTrue(Canvas.write(try XCTUnwrap(Canvas.noise(width: 1200, height: 900)), to: png, type: .png))

        let result = try ImageConverter.compress(png, toBytes: 200_000)
        XCTAssertEqual(result.url.lastPathComponent, "报名照片 200KB.jpg")
        XCTAssertLessThanOrEqual(result.bytes, 200_000)
        XCTAssertEqual(try result.url.resourceValues(forKeys: [.fileSizeKey]).fileSize, result.bytes)

        // 上限很小：画质降到底还不够，就缩小尺寸
        let tiny = try ImageConverter.compress(png, toBytes: 20_000)
        XCTAssertLessThanOrEqual(tiny.bytes, 20_000)
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(tiny.url as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertLessThan(image.width, 1200)

        XCTAssertThrowsError(try ImageConverter.compress(png, toBytes: 100)) { error in
            XCTAssertEqual(error as? ImageConverter.Failure, ImageConverter.Failure(message: "「报名照片.png」压不到 100 B 以内"))
        }
        XCTAssertEqual(ImageConverter.sizeLabel(200_000), "200 KB")
        XCTAssertEqual(ImageConverter.sizeLabel(1_000_000), "1 MB")
        XCTAssertEqual(ImageConverter.sizeLabel(1_500_000), "1.5 MB")
    }
}

final class ImageSaveFailureTests: XCTestCase {
    /// 存不进去的文件夹：说没有权限，不要说成这台 Mac 不支持这种格式
    func testReadOnlyFolderSaysNoPermission() throws {
        let folder = try Canvas.folder(self)
        let locked = folder.appending(path: "只读")
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        let png = locked.appending(path: "截图.png")
        XCTAssertTrue(Canvas.write(try XCTUnwrap(Canvas.solid(width: 40, height: 30, gray: 0.5)), to: png, type: .png))
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
        // 后加的先执行：先恢复权限，删临时文件夹时才删得掉
        addTeardownBlock { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }

        XCTAssertThrowsError(try ImageConverter.convert(png, .jpeg)) { error in
            XCTAssertEqual(error as? ImageConverter.Failure, ImageConverter.Failure(message: "没有权限在「只读」里存文件"))
        }
    }

    func testUnsupportedFormatStillSaysSo() {
        XCTAssertEqual(ImageConverter.cannotCreateMessage(URL(fileURLWithPath: "/tmp/说明.txt"), type: .plainText),
                       "这台 Mac 不支持存成 TXT")
    }
}

final class FolderCompareTests: XCTestCase {
    private func makeFolder(_ root: URL, _ files: [String: String]) throws {
        for (path, text) in files {
            let url = root.appending(path: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }
    }

    func testFindsMissingAndChangedFiles() throws {
        let base = try Canvas.folder(self)
        let left = base.appending(path: "旧/照片")
        let right = base.appending(path: "新/照片")
        try makeFolder(left, ["a.txt": "same", "b.txt": "abcd", "d.txt": "short", "sub/c.txt": "nested", "只在旧的.txt": "x",
                              ".hidden": "h"])
        try makeFolder(right, ["a.txt": "same", "b.txt": "abce", "d.txt": "much longer", "sub/c.txt": "nested", "只在新的.txt": "y"])

        let result = FolderCompare.compare(left, right)
        XCTAssertEqual(result.same, 2)
        XCTAssertEqual(result.different, ["b.txt", "d.txt"])
        XCTAssertEqual(result.onlyLeft, ["只在旧的.txt"])
        XCTAssertEqual(result.onlyRight, ["只在新的.txt"])
        XCTAssertFalse(result.isIdentical)
        XCTAssertFalse(result.truncated)

        let card = FolderCompare.card(result)
        XCTAssertEqual(card.tabs.map(\.title), ["内容不同 2", "只在「旧/照片」里 1", "只在「新/照片」里 1"])
        XCTAssertEqual(card.tabs.first?.text, "b.txt\nd.txt")

        let same = FolderCompare.compare(left.appending(path: "sub"), right.appending(path: "sub"))
        XCTAssertTrue(same.isIdentical)
        XCTAssertEqual(FolderCompare.card(same).body, "两个文件夹里的 1 个文件完全一样")
        XCTAssertTrue(FolderCompare.card(same).tabs.isEmpty)
        XCTAssertEqual(FolderCompare.names(left.appending(path: "sub"), right.appending(path: "sub")).left, "旧/…/sub")
        XCTAssertEqual(FolderCompare.names(left, base.appending(path: "新/图片")).right, "图片")
        XCTAssertEqual(FolderCompare.names(left, left).right, "第二个 照片")
    }

    @MainActor
    func testPluginNeedsExactlyTwoFolders() async throws {
        let base = try Canvas.folder(self)
        let left = base.appending(path: "甲")
        let right = base.appending(path: "乙")
        try makeFolder(left, ["a.txt": "1"])
        try makeFolder(right, ["a.txt": "2"])
        let plugin = FolderComparePlugin()
        XCTAssertTrue(plugin.info.canHandle(ContentClassifier.classify(.files([left, right]))))
        XCTAssertFalse(plugin.info.canHandle(ContentClassifier.classify(.files([left]))))
        XCTAssertFalse(plugin.info.canHandle(ContentClassifier.classify(.files([left, left.appending(path: "a.txt")]))))
        let outcome = await plugin.run(ContentClassifier.classify(.files([left, right])), context: PluginContext(settings: AppSettings(),
                                                                                                                  openSettings: {}))
        guard case .card(let card) = outcome else { return XCTFail("应该返回结果卡片") }
        XCTAssertEqual(card.tabs.map(\.title), ["内容不同 1"])
    }
}
