import AVFoundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Pop

/// 测试用的临时文件夹和图片
private enum Samples {
    static func folder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "pop-media-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    static func image(width: Int, height: Int, red: CGFloat, green: CGFloat, blue: CGFloat) -> CGImage? {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        context?.setFillColor(CGColor(red: red, green: green, blue: blue, alpha: 1))
        context?.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context?.makeImage()
    }

    /// 一张杂色图：重新压缩过的话像素一定会变
    static func noise(width: Int, height: Int) -> CGImage? {
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
              let bytes = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        var seed: UInt32 = 2026
        for index in 0..<(width * height * 4) {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            bytes[index] = UInt8(truncatingIfNeeded: seed >> 24)
        }
        return context.makeImage()
    }

    /// 解码出来的原始像素（不按方向摆正，也不做颜色转换）
    static func pixels(of url: URL) -> [UInt8]? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let data = image.dataProvider?.data as Data? else { return nil }
        return [UInt8](data)
    }

    static func write(_ image: CGImage, to url: URL, type: UTType, properties: [CFString: Any] = [:]) -> Bool {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else { return false }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        return CGImageDestinationFinalize(destination)
    }

    /// 图片里某个像素的颜色（x、y 从左上角数）
    static func pixel(_ image: CGImage, x: Int, y: Int) -> (red: UInt8, green: UInt8, blue: UInt8)? {
        guard let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // 把要看的像素挪到 (0, 0)：CGContext 的原点在左下角
        context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
        guard let bytes = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        return (bytes[0], bytes[1], bytes[2])
    }

    /// 一张竖着拍的照片（方向 6）带着的拍摄信息和位置
    static let photoProperties: [CFString: Any] = [
        kCGImagePropertyOrientation: 6,
        kCGImagePropertyTIFFDictionary: [
            kCGImagePropertyTIFFMake: "Apple",
            kCGImagePropertyTIFFModel: "iPhone 15 Pro",
        ] as [CFString: Any],
        kCGImagePropertyExifDictionary: [
            kCGImagePropertyExifLensModel: "iPhone 15 Pro back triple camera 6.765mm f/1.78",
            kCGImagePropertyExifFocalLength: 6.765,
            kCGImagePropertyExifFocalLenIn35mmFilm: 24,
            kCGImagePropertyExifFNumber: 1.78,
            kCGImagePropertyExifExposureTime: 1.0 / 120,
            kCGImagePropertyExifISOSpeedRatings: [64],
            kCGImagePropertyExifDateTimeOriginal: "2026:09:29 12:30:05",
            kCGImagePropertyExifOffsetTimeOriginal: "+08:00",
        ] as [CFString: Any],
        kCGImagePropertyGPSDictionary: [
            kCGImagePropertyGPSLatitude: 31.2304,
            kCGImagePropertyGPSLatitudeRef: "N",
            kCGImagePropertyGPSLongitude: 121.4737,
            kCGImagePropertyGPSLongitudeRef: "E",
            kCGImagePropertyGPSAltitude: 12.4,
            kCGImagePropertyGPSAltitudeRef: 0,
        ] as [CFString: Any],
    ]
}

final class PhotoMetadataTests: XCTestCase {
    func testReadsCaptureDetails() {
        let metadata = PhotoMetadata(properties: Samples.photoProperties)
        XCTAssertEqual(metadata.camera, "Apple iPhone 15 Pro")
        XCTAssertEqual(metadata.exposure, "6.8 mm（等效 24 mm） · f/1.8 · 1/120 秒 · ISO 64")
        XCTAssertEqual(metadata.taken, "2026-09-29 12:30:05（UTC+08:00）")
        XCTAssertEqual(metadata.rows.map(\.label), ["相机", "镜头", "拍摄参数", "拍摄时间", "拍摄地点", "海拔"])
        XCTAssertEqual(metadata.rows.first { $0.label == "拍摄地点" }?.value, "北纬 31.23040°，东经 121.47370°")
        XCTAssertEqual(metadata.rows.last?.value, "12 米")
        XCTAssertTrue(metadata.mapURL?.absoluteString.hasPrefix("https://maps.apple.com/?ll=31.230400,121.473700&q=") == true,
                      metadata.mapURL?.absoluteString ?? "")
        XCTAssertTrue(PhotoMetadata(properties: [:]).isEmpty)
    }

    func testFormatting() {
        XCTAssertEqual(PhotoMetadata.cameraName(make: "Canon", model: "Canon EOS R5"), "Canon EOS R5")
        XCTAssertEqual(PhotoMetadata.cameraName(make: "NIKON CORPORATION", model: "NIKON Z 6"), "NIKON Z 6")
        XCTAssertEqual(PhotoMetadata.cameraName(make: "SONY", model: nil), "SONY")
        XCTAssertNil(PhotoMetadata.cameraName(make: " ", model: ""))
        XCTAssertEqual(PhotoMetadata.shutter(0.5), "1/2 秒")
        XCTAssertEqual(PhotoMetadata.shutter(2.5), "2.5 秒")
        XCTAssertEqual(PhotoMetadata.focalLength(50, equivalent: 50), "50 mm")
        XCTAssertEqual(PhotoMetadata.focalLength(nil, equivalent: 26), "等效 26 mm")
        XCTAssertNil(PhotoMetadata.focalLength(0, equivalent: nil))
        XCTAssertEqual(PhotoMetadata.coordinates(latitude: -33.4489, longitude: -70.6693), "南纬 33.44890°，西经 70.66930°")
        XCTAssertEqual(PhotoMetadata.captureDate("2026:09:29 08:05:00", offset: nil), "2026-09-29 08:05:00")
        XCTAssertNil(PhotoMetadata.captureDate("  ", offset: nil))
    }

    func testRemovesLocationOrAllCaptureDetails() throws {
        let folder = try Samples.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let photo = folder.appending(path: "照片.jpg")
        let image = try XCTUnwrap(Samples.noise(width: 40, height: 30))
        XCTAssertTrue(Samples.write(image, to: photo, type: .jpeg, properties: Samples.photoProperties))
        let original = try XCTUnwrap(PhotoMetadata.read(photo))
        XCTAssertEqual(original.camera, "Apple iPhone 15 Pro")
        XCTAssertTrue(original.hasLocation)
        let pixels = try XCTUnwrap(Samples.pixels(of: photo))

        let withoutLocation = try ImageConverter.convert(photo, .removeLocation)
        XCTAssertEqual(withoutLocation.lastPathComponent, "照片 无位置.jpg")
        let kept = try XCTUnwrap(PhotoMetadata.read(withoutLocation))
        XCTAssertFalse(kept.hasLocation)
        XCTAssertEqual(kept.camera, original.camera)
        XCTAssertEqual(kept.exposure, original.exposure)
        XCTAssertEqual(kept.taken, original.taken)
        // 画面原样拷贝，没有重新压缩
        XCTAssertTrue(Samples.pixels(of: withoutLocation) == pixels, "去掉位置时重新压缩了画面")

        let bare = try ImageConverter.convert(photo, .removeMetadata)
        XCTAssertEqual(bare.lastPathComponent, "照片 无拍摄信息.jpg")
        XCTAssertEqual(PhotoMetadata.read(bare)?.isEmpty, true)
        // 照片的方向还在：摆正后是竖着的 30 × 40，画面数据原样
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(bare as CFURL, nil))
        XCTAssertEqual(ImageStitcher.uprightSize(source), CGSize(width: 30, height: 40))
        XCTAssertTrue(Samples.pixels(of: bare) == pixels, "去掉拍摄信息时重新压缩了画面")
        // 原图不动
        XCTAssertTrue(try XCTUnwrap(PhotoMetadata.read(photo)).hasLocation)
    }

    func testFileInfoOffersToRemoveTheLocation() throws {
        let folder = try Samples.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let photo = folder.appending(path: "照片.jpg")
        let image = try XCTUnwrap(Samples.image(width: 40, height: 30, red: 0.2, green: 0.5, blue: 0.8))
        XCTAssertTrue(Samples.write(image, to: photo, type: .jpeg, properties: Samples.photoProperties))
        XCTAssertEqual(FileInfoPlugin.photoButtons(for: photo).map(\.title), ["在地图中打开", "去掉位置信息", "去掉拍摄信息"])
        XCTAssertEqual(FileInfoPlugin.photoButtons(for: photo).last?.action, .convertImages([photo], .removeMetadata))

        let plain = folder.appending(path: "截图.png")
        XCTAssertTrue(Samples.write(image, to: plain, type: .png))
        XCTAssertEqual(FileInfoPlugin.photoButtons(for: plain), [])
    }
}

final class ImageStitcherTests: XCTestCase {
    func testLayoutAlignsToTheSmallest() {
        let sizes = [CGSize(width: 100, height: 50), CGSize(width: 200, height: 100), CGSize(width: 50, height: 50)]
        let vertical = ImageStitcher.layout(sizes, direction: .vertical)
        XCTAssertEqual(vertical.size, CGSize(width: 50, height: 100))
        XCTAssertEqual(vertical.frames, [CGRect(x: 0, y: 0, width: 50, height: 25), CGRect(x: 0, y: 25, width: 50, height: 25),
                                         CGRect(x: 0, y: 50, width: 50, height: 50)])
        let horizontal = ImageStitcher.layout(sizes, direction: .horizontal)
        XCTAssertEqual(horizontal.size, CGSize(width: 250, height: 50))
        XCTAssertEqual(horizontal.frames.map(\.minX), [0, 100, 200])
        XCTAssertEqual(horizontal.frames.map(\.width), [100, 100, 50])
    }

    func testLayoutShrinksVeryLongResults() {
        let sizes = Array(repeating: CGSize(width: 100, height: 100), count: 3)
        let plan = ImageStitcher.layout(sizes, direction: .vertical, maxLength: 150)
        XCTAssertEqual(plan.size, CGSize(width: 50, height: 150))
        XCTAssertEqual(plan.frames.map(\.height), [50, 50, 50])
        XCTAssertEqual(plan.frames.last?.maxY, 150)
    }

    func testStitchesFilesInNameOrder() throws {
        let folder = try Samples.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let second = folder.appending(path: "截图 10.png")
        let first = folder.appending(path: "截图 9.png")
        XCTAssertTrue(Samples.write(try XCTUnwrap(Samples.image(width: 40, height: 30, red: 0, green: 0, blue: 1)), to: second, type: .png))
        XCTAssertTrue(Samples.write(try XCTUnwrap(Samples.image(width: 80, height: 20, red: 1, green: 0, blue: 0)), to: first, type: .png))
        // 按文件名里的数字排：9 在 10 前面
        let ordered = ImageStitcher.ordered([second, first])
        XCTAssertEqual(ordered, [first, second])

        let output = try ImageStitcher.stitch(ordered, direction: .vertical)
        XCTAssertEqual(output.lastPathComponent, "截图 9 拼接.png")
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(output as CFURL, nil))
        // 第一张 80 × 20 缩到 40 × 10，第二张 40 × 30 原样
        XCTAssertEqual(ImageStitcher.uprightSize(source), CGSize(width: 40, height: 40))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let top = try XCTUnwrap(Samples.pixel(image, x: 20, y: 3))
        let bottom = try XCTUnwrap(Samples.pixel(image, x: 20, y: 30))
        XCTAssertTrue(top.red > 200 && top.blue < 60, "\(top)")
        XCTAssertTrue(bottom.blue > 200 && bottom.red < 60, "\(bottom)")

        XCTAssertThrowsError(try ImageStitcher.stitch([first], direction: .horizontal))
    }

    @MainActor
    func testPluginNeedsTwoImages() async throws {
        let context = PluginContext(settings: AppSettings(), openSettings: {})
        let one = await StitchImagesPlugin().run(ContentClassifier.classify(.files([URL(fileURLWithPath: "/tmp/a.png")])), context: context)
        guard case .failure = one else { return XCTFail("一张图不能拼") }
        let files = [URL(fileURLWithPath: "/tmp/b.png"), URL(fileURLWithPath: "/tmp/a.png")]
        let outcome = await StitchImagesPlugin().run(ContentClassifier.classify(.files(files)), context: context)
        guard case .card(let card) = outcome else { return XCTFail("应该返回结果卡片") }
        XCTAssertEqual(card.body, "a.png\nb.png")
        XCTAssertEqual(card.buttons.map(\.title), ["竖着拼接", "横着拼接"])
        XCTAssertEqual(card.buttons.first?.action, .stitchImages(Array(files.reversed()), .vertical))
    }
}

final class VideoConverterTests: XCTestCase {
    func testFrameTimes() {
        let times = VideoConverter.frameTimes(duration: 1, frameRate: 10)
        XCTAssertEqual(times.count, 10)
        XCTAssertEqual(times.last ?? 0, 0.9, accuracy: 1e-9)
        XCTAssertEqual(VideoConverter.frameTimes(duration: 0.05, frameRate: 10), [0])
        XCTAssertEqual(VideoConverter.frameTimes(duration: 0, frameRate: 10), [])
    }

    func testOutputNames() {
        let folder = FileManager.default.temporaryDirectory.appending(path: "pop-video-names-\(UUID().uuidString)")
        let mov = folder.appending(path: "录屏.mov")
        XCTAssertEqual(VideoConverter.outputURL(for: mov, operation: .gif).lastPathComponent, "录屏.gif")
        XCTAssertEqual(VideoConverter.outputURL(for: mov, operation: .mp4).lastPathComponent, "录屏.mp4")
        XCTAssertEqual(VideoConverter.outputURL(for: mov, operation: .compress).lastPathComponent, "录屏 720p.mp4")
        XCTAssertEqual(VideoConverter.outputURL(for: mov, operation: .audio).lastPathComponent, "录屏.m4a")
        XCTAssertEqual(VideoConverter.outputURL(for: folder.appending(path: "录屏.mp4"), operation: .mp4).lastPathComponent, "录屏 转换.mp4")
    }

    @MainActor
    func testPluginSkipsMP4ForMP4Files() async throws {
        let context = PluginContext(settings: AppSettings(), openSettings: {})
        let mp4 = URL(fileURLWithPath: "/tmp/pop-missing-\(UUID().uuidString).mp4")
        let outcome = await VideoConvertPlugin().run(ContentClassifier.classify(.files([mp4])), context: context)
        guard case .card(let card) = outcome else { return XCTFail("应该返回结果卡片") }
        XCTAssertEqual(card.buttons.map(\.title), ["转成 GIF", "压缩到 720p", "提取音频"])
        XCTAssertEqual(card.buttons.first?.action, .convertVideos([mp4], .gif))
    }

    func testMakesALoopingGIF() async throws {
        let folder = try Samples.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let video = folder.appending(path: "录屏.mov")
        try await writeVideo(to: video)

        let result = try await VideoConverter.convert(video, .gif)
        XCTAssertEqual(result.url.lastPathComponent, "录屏.gif")
        XCTAssertNil(result.note)
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(result.url as CFURL, nil))
        XCTAssertTrue((9...10).contains(CGImageSourceGetCount(source)), "\(CGImageSourceGetCount(source)) 帧")
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        XCTAssertEqual(properties?[kCGImagePropertyPixelWidth] as? Int, 64)

        // 没有声音的视频提取不了音频，也不会留下空文件
        do {
            _ = try await VideoConverter.convert(video, .audio)
            XCTFail("没有声音也提取了音频")
        } catch let failure as VideoConverter.Failure {
            XCTAssertEqual(failure.message, "「录屏.mov」没有声音")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appending(path: "录屏.m4a").path(percentEncoded: false)))
    }

    /// 写一段 1 秒、每秒 10 帧、64 × 48 的视频（Motion JPEG，不依赖硬件编码），每一帧换一个灰度
    private func writeVideo(to url: URL, frames: Int = 10, frameRate: Int32 = 10) async throws {
        let width = 64
        let height = 48
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.jpeg, AVVideoWidthKey: width, AVVideoHeightKey: height,
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ])
        XCTAssertTrue(writer.canAdd(input))
        writer.add(input)
        XCTAssertTrue(writer.startWriting(), writer.error?.localizedDescription ?? "")
        writer.startSession(atSourceTime: .zero)
        for index in 0..<frames {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 5_000_000)
            }
            let pool = try XCTUnwrap(adaptor.pixelBufferPool)
            var created: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &created)
            let buffer = try XCTUnwrap(created)
            CVPixelBufferLockBaseAddress(buffer, [])
            memset(CVPixelBufferGetBaseAddress(buffer), Int32(index * 25), CVPixelBufferGetDataSize(buffer))
            CVPixelBufferUnlockBaseAddress(buffer, [])
            XCTAssertTrue(adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(index), timescale: frameRate)))
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(value: CMTimeValue(frames), timescale: frameRate))
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed, writer.error?.localizedDescription ?? "")
    }
}
