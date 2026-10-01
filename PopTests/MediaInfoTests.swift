import AVFoundation
import XCTest
@testable import Pop

final class MediaInfoTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "pop-media-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    func testNamesAndNumbers() {
        XCTAssertEqual(MediaInspector.videoCodec("hvc1"), "HEVC（H.265）")
        XCTAssertEqual(MediaInspector.videoCodec("avc1"), "H.264")
        XCTAssertEqual(MediaInspector.videoCodec("apch"), "ProRes 422 HQ")
        XCTAssertEqual(MediaInspector.videoCodec("xyz1"), "XYZ1")
        XCTAssertEqual(MediaInspector.audioCodec("aac "), "AAC")
        XCTAssertEqual(MediaInspector.audioCodec(".mp3"), "MP3")
        XCTAssertEqual(MediaInspector.audioCodec("ec-3"), "Dolby Digital Plus（E-AC-3）")
        XCTAssertEqual(MediaInspector.fourCC(kCMVideoCodecType_H264), "avc1")
        XCTAssertEqual(MediaInspector.channels(1), "单声道")
        XCTAssertEqual(MediaInspector.channels(2), "立体声")
        XCTAssertEqual(MediaInspector.channels(6), "5.1 声道")
        XCTAssertEqual(MediaInspector.channels(3), "3 声道")
        XCTAssertEqual(MediaInspector.bitRate(38_200_000), "38.2 Mbps")
        XCTAssertEqual(MediaInspector.bitRate(40_000_000), "40 Mbps")
        XCTAssertEqual(MediaInspector.bitRate(128_000), "128 kbps")
        XCTAssertEqual(MediaInspector.frameRate(29.97), "29.97")
        XCTAssertEqual(MediaInspector.frameRate(30), "30")
        XCTAssertEqual(MediaInspector.frameRate(23.976), "23.976")
        XCTAssertEqual(MediaInspector.sampleRate(48_000), "48 kHz")
        XCTAssertEqual(MediaInspector.sampleRate(44_100), "44.1 kHz")
        XCTAssertEqual(MediaInspector.resolutionName(width: 3840, height: 2160), "4K")
        XCTAssertEqual(MediaInspector.resolutionName(width: 1080, height: 1920), "1080p 竖屏")
        XCTAssertEqual(MediaInspector.resolutionName(width: 1920, height: 800), "1080p")
        XCTAssertNil(MediaInspector.resolutionName(width: 2704, height: 1520))
        XCTAssertEqual(MediaInspector.container(of: URL(fileURLWithPath: "/tmp/a.MOV")), "QuickTime")
        XCTAssertEqual(MediaInspector.container(of: URL(fileURLWithPath: "/tmp/a.flac")), "FLAC")
        XCTAssertEqual(MediaInspector.device(make: "Apple", model: "iPhone 15 Pro"), "Apple iPhone 15 Pro")
        XCTAssertEqual(MediaInspector.device(make: "DJI", model: "DJI Osmo Pocket 3"), "DJI Osmo Pocket 3")
        XCTAssertEqual(MediaInspector.device(make: nil, model: "Pixel 9"), "Pixel 9")
        XCTAssertNil(MediaInspector.device(make: nil, model: nil))
        XCTAssertEqual(MediaInspector.languageName("eng"), Localization.locale.localizedString(forIdentifier: "en"))
        XCTAssertEqual(MediaInspector.languageName("zh-Hans"), Localization.locale.localizedString(forIdentifier: "zh-Hans"))
    }

    func testReadsISO6709Locations() {
        XCTAssertEqual(MediaInspector.location(iso6709: "+31.2304+121.4737+012.345/"), MediaInspector.Location(latitude: 31.2304, longitude: 121.4737))
        XCTAssertEqual(MediaInspector.location(iso6709: "-33.8688+151.2093/"), MediaInspector.Location(latitude: -33.8688, longitude: 151.2093))
        XCTAssertNil(MediaInspector.location(iso6709: "不是位置"))
        XCTAssertNil(MediaInspector.location(iso6709: "+3112.30+12128.42/"))
    }

    func testReadsAVideoAndSavesACopyWithoutTheLocation() async throws {
        let url = folder.appending(path: "片段.mov")
        try await writeVideo(to: url)
        let report = try await MediaInspector.inspect(url)
        XCTAssertEqual(report.container, "QuickTime")
        XCTAssertEqual(report.duration, 1, accuracy: 0.05)
        XCTAssertGreaterThan(report.bytes, 0)
        let track = try XCTUnwrap(report.video.first)
        XCTAssertEqual(track.codec, "Motion JPEG")
        // 竖着拍的：画面按 preferredTransform 转过来
        XCTAssertEqual([track.width, track.height], [48, 64])
        XCTAssertEqual(track.frameRate, 10, accuracy: 0.5)
        XCTAssertNil(track.hdr)
        XCTAssertTrue(report.audio.isEmpty)
        XCTAssertEqual(report.device, "Apple iPhone 15 Pro")
        XCTAssertEqual(report.location, MediaInspector.Location(latitude: 31.2304, longitude: 121.4737))
        XCTAssertNotNil(report.created)

        let model = await MediaInfoModel(report: report)
        let titles = await model.sections.map(\.title)
        XCTAssertEqual(titles, ["视频", "信息"])

        let copy = try await MediaInspector.exportWithoutLocation(url)
        XCTAssertEqual(copy.lastPathComponent, "片段 无位置.mov")
        let stripped = try await MediaInspector.inspect(copy)
        XCTAssertNil(stripped.location)
        XCTAssertEqual(stripped.video.first?.codec, "Motion JPEG")
        // 再存一次不覆盖
        let again = try await MediaInspector.exportWithoutLocation(url)
        XCTAssertEqual(again.lastPathComponent, "片段 无位置 2.mov")
    }

    func testReadsAnAudioFile() async throws {
        let url = folder.appending(path: "铃声.m4a")
        try writeTone(to: url)
        let report = try await MediaInspector.inspect(url)
        XCTAssertEqual(report.container, "M4A")
        XCTAssertTrue(report.video.isEmpty)
        let track = try XCTUnwrap(report.audio.first)
        XCTAssertEqual(track.codec, "AAC")
        XCTAssertEqual(track.channels, 1)
        XCTAssertEqual(track.sampleRate, 44_100)
        XCTAssertEqual(report.duration, 0.5, accuracy: 0.1)
        let model = await MediaInfoModel(report: report)
        let audioOnly = await model.isAudioOnly
        XCTAssertTrue(audioOnly)
        let rows = await model.sections.first?.rows.map(\.value)
        XCTAssertEqual(Array((rows ?? []).prefix(2)), ["AAC", "单声道 · 44.1 kHz"])

        do {
            _ = try await MediaInspector.inspect(folder.appending(path: "没有这个.mp4"))
            XCTFail("读不了的文件应该报错")
        } catch let failure as MediaInspector.Failure {
            XCTAssertTrue(failure.message.contains("没有这个.mp4"))
        }
    }

    @MainActor
    func testCardRowsCopyTextAndRemovingTheLocation() async throws {
        let report = MediaInfoPlugin.demoReport()
        var stripped: [URL] = []
        let model = MediaInfoModel(report: report, strip: { url in
            stripped.append(url)
            return url.deletingLastPathComponent().appending(path: "旅行 无位置.mov")
        })
        XCTAssertEqual(model.headline, "QuickTime · 1:23 · \(ByteCountFormatter.string(fromByteCount: 412_000_000, countStyle: .file)) · 39.5 Mbps")
        XCTAssertEqual(model.sections.map(\.title), ["视频", "音频", "信息"])
        XCTAssertEqual(model.sections[0].rows.map(\.value),
                       ["HEVC（H.265）", "3840 × 2160 · 4K", "29.97 帧/秒", "38.2 Mbps", "Dolby Vision（HLG）", "BT.2020 · 10 位"])
        XCTAssertEqual(model.sections[1].rows.map(\.value), ["AAC", "立体声 · 48 kHz", "128 kbps"])
        let place = try XCTUnwrap(model.sections[2].rows.last)
        XCTAssertEqual(place.label, "拍摄地点")
        XCTAssertEqual(place.value, "31.2304, 121.4737")
        XCTAssertTrue(place.warning)
        XCTAssertEqual(model.mapURL?.host(), "maps.apple.com")
        XCTAssertTrue(model.text.hasPrefix("旅行.mov\nQuickTime · 1:23"))
        XCTAssertTrue(model.text.contains("视频：编码格式 HEVC（H.265） · 画面 3840 × 2160 · 4K"))

        model.removeLocation()
        for _ in 0..<100 where model.phase == .saving {
            try await Task.sleep(for: .milliseconds(10))
        }
        guard case .saved(let copy) = model.phase else { return XCTFail("应该存好了：\(model.phase)") }
        XCTAssertEqual(copy.lastPathComponent, "旅行 无位置.mov")
        XCTAssertEqual(stripped, [report.url])
    }

    func testPluginTakesVideoAndAudioFiles() {
        let plugin = MediaInfoPlugin().info
        XCTAssertTrue(plugin.canHandle(ContentClassifier.classify(.files([URL(fileURLWithPath: "/tmp/旅行.MOV")]))))
        XCTAssertTrue(plugin.canHandle(ContentClassifier.classify(.files([URL(fileURLWithPath: "/tmp/歌.mp3")]))))
        XCTAssertFalse(plugin.canHandle(ContentClassifier.classify(.files([URL(fileURLWithPath: "/tmp/笔记.txt")]))))
        XCTAssertFalse(plugin.canHandle(.empty))
    }

    // MARK: - 做测试用的文件

    /// 一段 1 秒、每秒 10 帧、64 × 48 的竖拍视频（Motion JPEG，不依赖硬件编码），带着拍摄设备、时间和地点
    private func writeVideo(to url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.jpeg, AVVideoWidthKey: 64, AVVideoHeightKey: 48,
        ])
        input.expectsMediaDataInRealTime = false
        input.transform = CGAffineTransform(rotationAngle: .pi / 2)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 64,
            kCVPixelBufferHeightKey as String: 48,
        ])
        func item(_ identifier: AVMetadataIdentifier, _ value: String, type: CFString = kCMMetadataBaseDataType_UTF8) -> AVMetadataItem {
            let item = AVMutableMetadataItem()
            item.identifier = identifier
            item.value = value as NSString
            item.dataType = type as String
            return item
        }
        writer.metadata = [
            item(.quickTimeMetadataLocationISO6709, "+31.2304+121.4737+012.345/", type: kCMMetadataDataType_QuickTimeMetadataLocation_ISO6709),
            item(.quickTimeMetadataMake, "Apple"),
            item(.quickTimeMetadataModel, "iPhone 15 Pro"),
            item(.quickTimeMetadataCreationDate, "2026-09-21T17:42:05+0800"),
        ]
        XCTAssertTrue(writer.canAdd(input))
        writer.add(input)
        XCTAssertTrue(writer.startWriting(), writer.error?.localizedDescription ?? "")
        writer.startSession(atSourceTime: .zero)
        for index in 0..<10 {
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
            XCTAssertTrue(adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(index), timescale: 10)))
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(value: 10, timescale: 10))
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed, writer.error?.localizedDescription ?? "")
    }

    /// 半秒 440 赫兹的单声道 AAC
    private func writeTone(to url: URL) throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 22_050))
        buffer.frameLength = 22_050
        let samples = try XCTUnwrap(buffer.floatChannelData?[0])
        for index in 0..<22_050 {
            samples[index] = sin(Float(index) * 2 * .pi * 440 / 44_100) * 0.3
        }
        // 文件在这个作用域结束时关上
        do {
            let file = try AVAudioFile(forWriting: url, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44_100,
                                                                    AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 64_000],
                                       commonFormat: .pcmFormatFloat32, interleaved: false)
            try file.write(from: buffer)
        }
    }
}
