import AVFoundation
import XCTest
@testable import Pop

final class VoiceRecorderTests: XCTestCase {
    func testFileNamesLevelsAndFormat() throws {
        let date = try XCTUnwrap(DateComponents(calendar: Calendar(identifier: .gregorian), timeZone: .current,
                                                year: 2026, month: 10, day: 1, hour: 9, minute: 5).date)
        XCTAssertEqual(VoiceRecorder.fileName(at: date), "录音 2026-10-01 09.05")
        // -50 dB 以下算没声音，0 dB 最响
        XCTAssertEqual(VoiceRecorder.level(decibels: -160), 0)
        XCTAssertEqual(VoiceRecorder.level(decibels: -50), 0)
        XCTAssertEqual(VoiceRecorder.level(decibels: -25), 0.5, accuracy: 0.0001)
        XCTAssertEqual(VoiceRecorder.level(decibels: 0), 1)
        XCTAssertEqual(VoiceRecorder.level(decibels: 3), 1)
        XCTAssertEqual(VoiceRecorder.level(decibels: .nan), 0)
        // AAC、单声道
        let settings = VoiceRecorder.settings
        XCTAssertEqual((settings[AVFormatIDKey] as? NSNumber)?.uint32Value, kAudioFormatMPEG4AAC)
        XCTAssertEqual((settings[AVNumberOfChannelsKey] as? NSNumber)?.intValue, 1)
        XCTAssertTrue(VoiceRecorder.permissionHint.contains("麦克风"))
    }

    @MainActor
    func testCapsuleModel() throws {
        let model = VoiceRecorderModel()
        model.reset(canTranscribe: true)
        XCTAssertTrue(model.isRecording)
        XCTAssertEqual(model.levels.count, VoiceRecorderModel.barCount)
        // 新的音量从右边进来，超出范围的截到 0～1
        model.push(0.5)
        model.push(2)
        XCTAssertEqual(model.levels.suffix(2), [0.5, 1])
        XCTAssertEqual(model.levels.count, VoiceRecorderModel.barCount)
        model.elapsed = 42
        XCTAssertEqual(model.elapsedText, "00:42")
        XCTAssertNil(model.savedDetail)
        model.phase = .paused
        XCTAssertFalse(model.isRecording)
        model.phase = .saved(URL(fileURLWithPath: "/tmp/录音 2026-10-01 09.05.m4a"), duration: 80)
        XCTAssertEqual(model.savedDetail, "存进了「下载」，长 1 分 20 秒")
        // 不到一秒也写 1 秒
        model.phase = .saved(URL(fileURLWithPath: "/tmp/a.m4a"), duration: 0.3)
        XCTAssertEqual(model.savedDetail, "存进了「下载」，长 1 秒")
        // 重新开始录：清空
        model.reset(canTranscribe: false)
        XCTAssertEqual(model.phase, .recording)
        XCTAssertEqual(model.elapsed, 0)
        XCTAssertFalse(model.canTranscribe)
        XCTAssertEqual(Set(model.levels), [0])
    }

    @MainActor
    func testDemoCapsuleShowsAndCloses() throws {
        let screen = try XCTUnwrap(NSScreen.main ?? NSScreen.screens.first)
        let recorder = VoiceRecorder.shared
        let frame = recorder.showForDemo(on: screen)
        XCTAssertGreaterThan(frame.width, 100)
        XCTAssertTrue(screen.frame.intersects(frame))
        XCTAssertNotNil(recorder.windowNumber)
        XCTAssertFalse(recorder.isRecording)
        recorder.close()
        XCTAssertNil(recorder.windowNumber)
        // 没在录时停止什么都不做
        XCTAssertNil(recorder.stop())
    }

    func testPluginNeedsNoSelection() {
        let info = VoiceRecorderPlugin().info
        XCTAssertTrue(info.canHandle(.empty))
        XCTAssertTrue(info.hidesOverlay)
    }
}
