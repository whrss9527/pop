import XCTest
@testable import Pop

final class ScreenRecordingTests: XCTestCase {
    private func size(_ points: CGSize, scale: CGFloat) -> [Int] {
        let size = ScreenRecording.outputSize(points: points, scale: scale)
        return [size.width, size.height]
    }

    func testOutputSizeInPixels() {
        // 视网膜屏上每点 2 个像素
        XCTAssertEqual(size(CGSize(width: 641, height: 361), scale: 2), [1282, 722])
        // 宽高取偶数
        XCTAssertEqual(size(CGSize(width: 301, height: 201), scale: 1), [300, 200])
        // 5K 屏整个录：等比缩到 3840×2160
        XCTAssertEqual(size(CGSize(width: 2560, height: 1440), scale: 2), [3840, 2160])
        // 竖着的一大块：短边不超过 2160
        XCTAssertEqual(size(CGSize(width: 1600, height: 2400), scale: 2), [2160, 3240])
        // 带鱼屏不用缩
        XCTAssertEqual(size(CGSize(width: 3440, height: 1440), scale: 1), [3440, 1440])
        XCTAssertEqual(size(CGSize(width: 1, height: 1), scale: 2), [2, 2])
    }

    func testSourceRectIsTopLeftInTheScreen() {
        let primary = CGRect(x: 0, y: 0, width: 1440, height: 900)
        XCTAssertEqual(ScreenRecording.sourceRect(CGRect(x: 100, y: 200, width: 300, height: 150), in: primary),
                       CGRect(x: 100, y: 550, width: 300, height: 150))
        // 右边那块屏幕，比主屏低一些
        let secondary = CGRect(x: 1440, y: -200, width: 1920, height: 1080)
        XCTAssertEqual(ScreenRecording.sourceRect(CGRect(x: 1540, y: 0, width: 400, height: 300), in: secondary),
                       CGRect(x: 100, y: 580, width: 400, height: 300))
        // 超出屏幕的部分切掉
        XCTAssertEqual(ScreenRecording.sourceRect(CGRect(x: 1400, y: 800, width: 200, height: 200), in: primary),
                       CGRect(x: 1400, y: 0, width: 40, height: 100))
        XCTAssertEqual(ScreenRecording.sourceRect(CGRect(x: 5000, y: 0, width: 10, height: 10), in: primary), .zero)
    }

    func testDraggedRegion() {
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 1000)
        XCTAssertEqual(ScreenRecording.region(from: CGPoint(x: 10.4, y: 20.6), to: CGPoint(x: 110.5, y: 5.2), in: bounds),
                       CGRect(x: 10, y: 5, width: 101, height: 16))
        // 拖出了屏幕：只留屏幕里的
        XCTAssertEqual(ScreenRecording.region(from: CGPoint(x: -50, y: 900), to: CGPoint(x: 100, y: 1200), in: bounds),
                       CGRect(x: 0, y: 900, width: 100, height: 100))
    }

    func testWindowUnderThePointer() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let windows = [
            // Pop 自己的窗口、菜单栏这类不是普通层级的、透明的都不算
            ScreenRecording.WindowInfo(frame: screen, layer: 0, ownerPID: 42, alpha: 1),
            ScreenRecording.WindowInfo(frame: CGRect(x: 0, y: 0, width: 1440, height: 24), layer: 25, ownerPID: 7, alpha: 1),
            ScreenRecording.WindowInfo(frame: screen, layer: 0, ownerPID: 8, alpha: 0),
            // 太小的
            ScreenRecording.WindowInfo(frame: CGRect(x: 290, y: 290, width: 30, height: 30), layer: 0, ownerPID: 9, alpha: 1),
            ScreenRecording.WindowInfo(frame: CGRect(x: 100, y: 100, width: 600, height: 400), layer: 0, ownerPID: 10, alpha: 1),
            ScreenRecording.WindowInfo(frame: CGRect(x: 1300, y: 100, width: 400, height: 300), layer: 0, ownerPID: 11, alpha: 1),
            ScreenRecording.WindowInfo(frame: screen, layer: 0, ownerPID: 12, alpha: 1),
        ]
        func window(at point: CGPoint) -> CGRect? {
            ScreenRecording.window(at: point, in: windows, ownPID: 42, primaryHeight: 900, screenFrame: screen)
        }
        // 左上角为原点的 (100, 100, 600, 400) 换成左下角为原点是 (100, 400, 600, 400)
        XCTAssertEqual(window(at: CGPoint(x: 300, y: 600)), CGRect(x: 100, y: 400, width: 600, height: 400))
        // 伸出屏幕的窗口只算屏幕里的部分
        XCTAssertEqual(window(at: CGPoint(x: 1400, y: 600)), CGRect(x: 1300, y: 500, width: 140, height: 300))
        // 后面铺满屏幕的窗口
        XCTAssertEqual(window(at: CGPoint(x: 1000, y: 100)), screen)
        XCTAssertNil(ScreenRecording.window(at: CGPoint(x: 1000, y: 100), in: Array(windows.prefix(6)), ownPID: 42,
                                            primaryHeight: 900, screenFrame: screen))
    }

    func testFileNameAndDuration() throws {
        let date = try XCTUnwrap(Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: 15, minute: 30, second: 12)))
        XCTAssertEqual(ScreenRecording.fileName(at: date), "录屏 2026-09-30 15.30.12")
        XCTAssertEqual(ScreenRecording.durationText(0), "00:00")
        XCTAssertEqual(ScreenRecording.durationText(12.9), "00:12")
        XCTAssertEqual(ScreenRecording.durationText(65), "01:05")
        XCTAssertEqual(ScreenRecording.durationText(3723), "1:02:03")
        XCTAssertEqual(ScreenRecording.durationText(-5), "00:00")
        XCTAssertEqual(ScreenRecording.durationText(.nan), "00:00")
    }

    func testSavesWhereScreenshotsGo() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "pop-record-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        XCTAssertEqual(ScreenRecording.folder(screenshotLocation: folder.path(percentEncoded: false)).standardizedFileURL.path,
                       folder.standardizedFileURL.path)
        XCTAssertEqual(ScreenRecording.folder(screenshotLocation: "~").standardizedFileURL.path,
                       FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path)
        // 没设置过、文件夹不在了、是个文件：存到桌面
        let file = folder.appending(path: "a.txt")
        try Data("x".utf8).write(to: file)
        for location in [nil, "", folder.appending(path: "没有这个").path(percentEncoded: false), file.path(percentEncoded: false)] {
            XCTAssertEqual(ScreenRecording.folder(screenshotLocation: location).lastPathComponent, "Desktop", location ?? "nil")
        }
    }

    func testRemembersOptions() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "pop-record-tests-\(UUID().uuidString)"))
        XCTAssertEqual(ScreenRecording.Options.saved(in: defaults), ScreenRecording.Options())
        ScreenRecording.Options(audio: .microphone, showClicks: true).save(in: defaults)
        XCTAssertEqual(ScreenRecording.Options.saved(in: defaults), ScreenRecording.Options(audio: .microphone, showClicks: true))
        ScreenRecording.Options(audio: .off, showKeys: true).save(in: defaults)
        XCTAssertEqual(ScreenRecording.Options.saved(in: defaults), ScreenRecording.Options(audio: .off, showKeys: true))
        XCTAssertEqual(ScreenRecording.Audio.allCases.map(\.title), ["不录声音", "电脑里的声音", "麦克风"])
    }

    /// 0.30.0 存的是「录上电脑里的声音」的勾选
    func testReadsTheOldSoundCheckbox() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "pop-record-old-\(UUID().uuidString)"))
        defaults.set(true, forKey: ScreenRecording.Options.systemAudioKey)
        XCTAssertEqual(ScreenRecording.Options.saved(in: defaults).audio, .system)
        defaults.set(ScreenRecording.Audio.off.rawValue, forKey: ScreenRecording.Options.audioKey)
        XCTAssertEqual(ScreenRecording.Options.saved(in: defaults).audio, .off)
    }

    func testFinishedCard() {
        let url = URL(fileURLWithPath: "/tmp/录屏 2026-09-30 15.30.12.mp4")
        let card = ScreenRecording.card(ScreenRecording.Clip(url: url, duration: 12.4, width: 1280, height: 720))
        XCTAssertEqual(card.title, "录好了")
        XCTAssertEqual(card.body, "录屏 2026-09-30 15.30.12.mp4")
        XCTAssertTrue(card.detail?.hasPrefix("00:12 · 1280 × 720 · 存在「") == true, card.detail ?? "")
        XCTAssertEqual(card.buttons.map(\.action), [.convertVideos([url], .gif), .trimMedia(url), .open(url), .reveal(url)])
    }
}
