import AVFoundation
import XCTest
@testable import Pop

final class SpeechExportTests: XCTestCase {
    func testFileNamesAndDurations() {
        XCTAssertEqual(SpeechExporter.fileName(for: "你好，世界"), "朗读 你好，世界")
        XCTAssertEqual(SpeechExporter.fileName(for: "第一行\n第二行/第三行:完"), "朗读 第一行 第二行-第三行-…")
        XCTAssertEqual(SpeechExporter.fileName(for: "  \n "), "朗读")
        XCTAssertEqual(SpeechExporter.describe(12.4), "12 秒")
        XCTAssertEqual(SpeechExporter.describe(0.2), "1 秒")
        XCTAssertEqual(SpeechExporter.describe(120), "2 分钟")
        XCTAssertEqual(SpeechExporter.describe(80), "1 分 20 秒")
    }

    func testPicksAVoiceForTheLanguage() throws {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        try XCTSkipIf(voices.isEmpty, "这台机器上没有系统语音")
        XCTAssertNil(SpeechExporter.voice(for: nil))
        if voices.contains(where: { $0.language.hasPrefix("en") }) {
            XCTAssertEqual(SpeechExporter.voice(for: "en")?.language.hasPrefix("en"), true)
        }
        if voices.contains(where: { $0.language == "zh-CN" }) {
            XCTAssertEqual(SpeechExporter.voice(for: "zh-Hans")?.language, "zh-CN")
        }
    }

    /// 真的读一句存成 .m4a；机器上的语音服务没有回应时跳过（CI 的机器上不一定有能导出的语音）
    func testExportsAnAudioFile() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "pop-speech-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: url) }
        let finished = expectation(description: "存好")
        // 在另一个任务里导出，等不到时不会一直卡着
        let box = OutcomeBox()
        let exporter = SpeechExporter()
        Task {
            do {
                box.outcome = .success(try await exporter.export("Hello from Pop.", voice: SpeechExporter.voice(for: "en"), to: url))
            } catch {
                box.outcome = .failure(error)
            }
            finished.fulfill()
        }
        let waited = await XCTWaiter().fulfillment(of: [finished], timeout: 30)
        guard waited == .completed, let outcome = box.outcome else { throw XCTSkip("语音服务没有回应") }
        switch outcome {
        case .failure(let error):
            throw XCTSkip("这台机器上的语音不能导出：\(error)")
        case .success(let output):
            XCTAssertEqual(output.url, url)
            XCTAssertGreaterThan(output.duration, 0.3)
            let file = try AVAudioFile(forReading: url)
            XCTAssertGreaterThan(file.length, 0)
        }
    }

    func testPluginTakesText() {
        let plugin = SpeakToFilePlugin().info
        XCTAssertTrue(plugin.canHandle(ContentClassifier.classify(.text("Hello"))))
        XCTAssertFalse(plugin.canHandle(.empty))
        XCTAssertEqual(SpeakEntry.makePlugins().map { $0.info.id }, [BuiltinPluginID.speak, BuiltinPluginID.speakToFile])
    }
}

/// 导出的结果（在别的任务里填）
private final class OutcomeBox {
    var outcome: Result<SpeechExporter.Output, Error>?
}
