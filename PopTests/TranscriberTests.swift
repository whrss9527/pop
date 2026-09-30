import XCTest
@testable import Pop

final class TranscriberTests: XCTestCase {
    private func words(_ items: [(String, TimeInterval, TimeInterval)]) -> [Transcriber.Segment] {
        items.map { Transcriber.Segment(text: $0.0, start: $0.1, duration: $0.2) }
    }

    func testTimestamps() {
        XCTAssertEqual(Transcriber.timestamp(0), "00:00:00,000")
        XCTAssertEqual(Transcriber.timestamp(3725.5), "01:02:05,500")
        XCTAssertEqual(Transcriber.timestamp(59.9996), "00:01:00,000")
        XCTAssertEqual(Transcriber.timestamp(-3), "00:00:00,000")
    }

    func testChineseCuesBreakAtSentencesPausesAndLength() {
        let segments = words([("大家", 0.5, 0.4), ("好", 0.9, 0.3), ("。", 1.2, 0.1),
                              ("今天", 1.6, 0.4), ("开会", 2.0, 0.5),
                              // 停了两秒
                              ("先说", 4.5, 0.5), ("发布", 5.0, 0.5), ("时间", 5.5, 0.5), ("？", 6.0, 0.1)])
        let cues = Transcriber.cues(segments, language: "zh-CN")
        XCTAssertEqual(cues.map(\.text), ["大家好。", "今天开会", "先说发布时间？"])
        XCTAssertEqual(cues[0].start, 0.5)
        XCTAssertEqual(cues[0].end, 1.3, accuracy: 0.001)
        XCTAssertEqual(cues[1].end, 2.5, accuracy: 0.001)

        // 太长了换一条：每条最多 18 个字
        let long = words((0..<12).map { ("说话", TimeInterval($0) * 0.4, 0.4) })
        let split = Transcriber.cues(long, language: "zh-CN")
        XCTAssertEqual(split.map { $0.text.count }, [18, 6])
        // 超过 6 秒也换一条
        let slow = words((0..<8).map { ("字", TimeInterval($0) * 0.9, 0.9) })
        XCTAssertEqual(Transcriber.cues(slow, language: "zh-CN").map(\.text), ["字字字字字字", "字字"])
    }

    func testEnglishCuesKeepSpaces() {
        let segments = words([("Hello", 0, 0.4), ("everyone.", 0.4, 0.6), ("Let's", 1.2, 0.3), ("begin", 1.5, 0.4)])
        XCTAssertEqual(Transcriber.cues(segments, language: "en-US").map(\.text), ["Hello everyone.", "Let's begin"])
    }

    func testSRT() {
        let cues = [Transcriber.Cue(start: 0.5, end: 1.3, text: "大家好。"), Transcriber.Cue(start: 1.6, end: 1.7, text: "今天开会")]
        XCTAssertEqual(Transcriber.srt(cues), "1\n00:00:00,500 --> 00:00:01,300\n大家好。\n\n2\n00:00:01,600 --> 00:00:02,100\n今天开会\n")
        XCTAssertEqual(Transcriber.srt([]), "")
    }

    func testSavesTextAndSubtitlesBesideTheRecording() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "pop-transcriber-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        let recording = folder.appending(path: "周会.m4a")
        try Data().write(to: recording)
        let transcript = Transcriber.Transcript(text: "大家好。今天开会", segments: words([("大家", 0.5, 0.4), ("好。", 0.9, 0.3), ("今天开会", 1.6, 0.9)]),
                                                onDevice: true)
        let saved = try Transcriber.save(transcript, beside: recording, language: "zh-CN")
        XCTAssertEqual(saved.text.lastPathComponent, "周会.txt")
        XCTAssertEqual(saved.subtitles.lastPathComponent, "周会.srt")
        XCTAssertEqual(try String(contentsOf: saved.text, encoding: .utf8), "大家好。今天开会")
        XCTAssertTrue(try String(contentsOf: saved.subtitles, encoding: .utf8).hasPrefix("1\n00:00:00,500 --> 00:00:01,200\n大家好。\n"))
        // 再存一次不覆盖
        XCTAssertEqual(try Transcriber.save(transcript, beside: recording, language: "zh-CN").text.lastPathComponent, "周会 2.txt")

        let card = Transcriber.card(transcript, file: recording, language: "zh-CN")
        XCTAssertEqual(card.tabs.map(\.title), ["文字", "字幕 SRT"])
        XCTAssertFalse(card.detail?.contains("服务器") ?? true)
        var remote = transcript
        remote.onDevice = false
        XCTAssertTrue(Transcriber.card(remote, file: recording, language: "zh-CN").detail?.contains("苹果的服务器") ?? false)
    }

    func testDescribesCommonFailures() {
        XCTAssertEqual(Transcriber.describe(NSError(domain: "kAFAssistantErrorDomain", code: 1110)), "没有听到有人说话")
        XCTAssertTrue(Transcriber.describe(NSError(domain: "kLSRErrorDomain", code: 201)).contains("听写"))
        XCTAssertEqual(Transcriber.describe(Transcriber.Failure(message: "「a.mov」里没有声音")), "「a.mov」里没有声音")
    }

    @MainActor
    func testPluginOffersLanguagesForRecordings() async throws {
        let plugin = TranscribePlugin()
        let recording = URL(fileURLWithPath: "/tmp/周会.m4a")
        XCTAssertTrue(plugin.info.canHandle(ContentClassifier.classify(.files([recording]))))
        XCTAssertTrue(plugin.info.canHandle(ContentClassifier.classify(.files([URL(fileURLWithPath: "/tmp/采访.MOV")]))))
        XCTAssertFalse(plugin.info.canHandle(ContentClassifier.classify(.files([URL(fileURLWithPath: "/tmp/笔记.txt")]))))
        XCTAssertTrue(Transcriber.isMedia(URL(fileURLWithPath: "/tmp/a.MP3")))
        XCTAssertFalse(Transcriber.isMedia(URL(fileURLWithPath: "/tmp/a.pdf")))
        XCTAssertEqual(Transcriber.languages(preferred: "en-US").first?.identifier, "en-US")
        XCTAssertEqual(Transcriber.languages(preferred: "zh-Hans-CN").first?.identifier, "zh-CN")

        let outcome = await plugin.run(ContentClassifier.classify(.files([recording])), context: PluginContext(settings: AppSettings(), openSettings: {}))
        guard case .card(let card) = outcome else { return XCTFail("应该返回结果卡片") }
        XCTAssertEqual(card.rows.first?.value, "周会.m4a")
        // 按系统语言排：CI 上可能是英语在前
        XCTAssertEqual(card.buttons.map(\.action), Transcriber.languages().map { CardAction.transcribe(recording, language: $0.identifier) })
        XCTAssertFalse(card.buttons.isEmpty)
    }
}
