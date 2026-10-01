import AVFoundation
import Synchronization
import XCTest
@testable import Pop

/// 测试里的「现在」：北京时间 2026 年 10 月 2 日上午 10:30
private let testStart = Date(timeIntervalSince1970: 1_790_908_200)

/// 测试用的引擎：不出声，记下调用了什么
@MainActor
private final class FakeSoundEngine: FocusSoundEngine {
    var onFailure: (@MainActor (String) -> Void)?
    var calls: [String] = []
    var sound: FocusSound?
    var volume: Float = 0
    var failure: Error?

    func start(sound: FocusSound, volume: Float) throws {
        if let failure {
            throw failure
        }
        calls.append("start \(sound.rawValue)")
        self.sound = sound
        self.volume = volume
    }

    func setVolume(_ volume: Float) {
        calls.append("volume")
        self.volume = volume
    }

    func pause() {
        calls.append("pause")
    }

    func stop() {
        calls.append("stop")
    }
}

@MainActor
final class FocusSoundsTests: XCTestCase {
    private func freshDefaults() -> UserDefaults {
        let suite = "PopFocusSoundsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        addTeardownBlock {
            UserDefaults.standard.removePersistentDomain(forName: suite)
        }
        return defaults
    }

    private func samples(_ sound: FocusSound, seconds: Double, seed: UInt64 = 0x1234_5678_9ABC_DEF1) -> [Float] {
        var generator = NoiseGenerator(sound: sound, seed: seed)
        return (0..<Int(44_100 * seconds)).map { _ in generator.next() }
    }

    private func rms<C: Collection>(_ values: C) -> Double where C.Element == Float {
        (values.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(values.count)).squareRoot()
    }

    /// 相邻两个样本有多像：白噪音接近 0，声音越低沉越接近 1
    private func lagOneCorrelation(_ values: [Float]) -> Double {
        var product = 0.0
        var energy = 0.0
        for index in 0..<(values.count - 1) {
            product += Double(values[index]) * Double(values[index + 1])
            energy += Double(values[index]) * Double(values[index])
        }
        return product / energy
    }

    // MARK: 生成声音

    func testEverySoundStaysInRangeAndIsAboutAsLoud() {
        for sound in FocusSound.allCases {
            let values = samples(sound, seconds: 4)
            XCTAssertTrue(values.allSatisfy { $0 >= -1 && $0 <= 1 }, sound.rawValue)
            let level = rms(values)
            XCTAssertGreaterThan(level, 0.1, sound.rawValue)
            XCTAssertLessThan(level, 0.35, sound.rawValue)
            let mean = values.reduce(0.0) { $0 + Double($1) } / Double(values.count)
            XCTAssertLessThan(abs(mean), 0.05, sound.rawValue)
        }
    }

    func testNoiseColorsGetDeeper() {
        XCTAssertLessThan(abs(lagOneCorrelation(samples(.white, seconds: 2))), 0.05)
        let pink = lagOneCorrelation(samples(.pink, seconds: 2))
        XCTAssertGreaterThan(pink, 0.7)
        XCTAssertLessThan(pink, 0.92)
        XCTAssertGreaterThan(lagOneCorrelation(samples(.brown, seconds: 2)), 0.95)
        // 雨声去掉了低音，比粉红噪音「亮」
        let rain = lagOneCorrelation(samples(.rain, seconds: 2))
        XCTAssertGreaterThan(rain, 0.4)
        XCTAssertLessThan(rain, 0.7)
    }

    func testWavesRiseAndFall() {
        let values = samples(.waves, seconds: 24)
        let window = 22_050
        let levels = stride(from: 0, through: values.count - window, by: window).map { rms(values[$0..<($0 + window)]) }
        let loudest = levels.max() ?? 0
        let quietest = levels.min() ?? 1
        XCTAssertGreaterThan(loudest / quietest, 2.5)
    }

    func testSameSeedGivesTheSameSound() {
        XCTAssertEqual(samples(.rain, seconds: 0.1), samples(.rain, seconds: 0.1))
        XCTAssertNotEqual(samples(.rain, seconds: 0.1), samples(.rain, seconds: 0.1, seed: 7))
    }

    func testSoundIndexRoundTrips() {
        for sound in FocusSound.allCases {
            XCTAssertEqual(FocusSound(index: sound.index), sound)
        }
        XCTAssertEqual(FocusSound(index: 99), .white)
    }

    func testRendererFadesInOutAndSwitchesSounds() {
        let controls = NoiseControls()
        controls.sound.store(FocusSound.white.index, ordering: .relaxed)
        controls.set(volume: 0.5)
        let renderer = NoiseRenderer(controls: controls, sound: .white, sampleRate: 44_100)
        let frames = 4_410
        let left = UnsafeMutablePointer<Float>.allocate(capacity: frames)
        let right = UnsafeMutablePointer<Float>.allocate(capacity: frames)
        let buffers = AudioBufferList.allocate(maximumBuffers: 2)
        defer {
            left.deallocate()
            right.deallocate()
            free(buffers.unsafeMutablePointer)
        }
        buffers[0] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(frames * MemoryLayout<Float>.size), mData: left)
        buffers[1] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(frames * MemoryLayout<Float>.size), mData: right)
        func tail() -> [Float] {
            Array(UnsafeBufferPointer(start: left + frames - 1_000, count: 1_000))
        }

        // 从没声慢慢变大
        renderer.render(frames: frames, into: buffers)
        XCTAssertLessThan(abs(left[0]), 0.01)
        XCTAssertGreaterThan(rms(tail()), 0.06)
        XCTAssertNotEqual(left[200], right[200])
        // 音量调到 0：慢慢没声
        controls.set(volume: 0)
        for _ in 0..<5 {
            renderer.render(frames: frames, into: buffers)
        }
        XCTAssertLessThan(rms(tail()), 0.002)
        // 换成棕色噪音再放
        controls.sound.store(FocusSound.brown.index, ordering: .relaxed)
        controls.set(volume: 0.5)
        for _ in 0..<5 {
            renderer.render(frames: frames, into: buffers)
        }
        XCTAssertGreaterThan(lagOneCorrelation(tail()), 0.9)
        XCTAssertGreaterThan(rms(tail()), 0.03)
    }

    // MARK: 播放

    func testPlayPauseAndSwitch() {
        let engine = FakeSoundEngine()
        let player = FocusSoundPlayer(engine: engine, defaults: freshDefaults(), now: { testStart }, usesTimers: false, showsStatusItem: false)
        XCTAssertEqual(player.state, .stopped)
        XCTAssertEqual(player.sound, .rain)
        XCTAssertEqual(player.volume, 0.5)
        XCTAssertNil(player.statusText)

        player.togglePlay()
        XCTAssertEqual(player.state, .playing)
        XCTAssertEqual(engine.sound, .rain)
        // 音量条在中间，听起来的大小按平方
        XCTAssertEqual(engine.volume, 0.25, accuracy: 0.0001)
        XCTAssertEqual(player.statusText, "正在放雨声")

        // 点正在放的那种：暂停
        player.select(.rain)
        XCTAssertEqual(player.state, .paused)
        XCTAssertEqual(player.statusText, "雨声 · 已暂停")
        // 点别的：换过去接着放
        player.select(.waves)
        XCTAssertEqual(player.state, .playing)
        XCTAssertEqual(engine.sound, .waves)
        player.volume = 1
        XCTAssertEqual(engine.volume, 1)
        XCTAssertEqual(engine.calls, ["start rain", "pause", "start waves", "volume"])

        player.stop()
        XCTAssertEqual(player.state, .stopped)
        XCTAssertNil(player.statusText)
        // 停着的时候调音量不碰引擎
        player.volume = 0.2
        XCTAssertEqual(engine.calls.last, "stop")
    }

    func testSleepTimerCountsDownPausesAndFadesOut() {
        var current = testStart
        let engine = FakeSoundEngine()
        let player = FocusSoundPlayer(engine: engine, defaults: freshDefaults(), now: { current }, usesTimers: false, showsStatusItem: false)
        player.setTimer(15)
        XCTAssertNil(player.remainingText)
        player.play(.brown)
        XCTAssertEqual(player.remainingText, "还剩 15:00")
        XCTAssertEqual(player.statusText, "正在放棕色噪音 · 还剩 15:00")

        current = testStart.addingTimeInterval(60)
        player.tick()
        XCTAssertEqual(player.remainingText, "还剩 14:00")
        // 暂停的时候不算时间
        player.pause()
        current = testStart.addingTimeInterval(600)
        player.tick()
        XCTAssertEqual(player.remainingText, "还剩 14:00")
        player.play()
        XCTAssertEqual(player.remainingText, "还剩 14:00")

        // 最后 5 秒慢慢变小声，到点停下
        current = testStart.addingTimeInterval(600 + 840 - 2.5)
        player.tick()
        XCTAssertEqual(player.state, .playing)
        XCTAssertEqual(engine.volume, 0.125, accuracy: 0.0001)
        current = testStart.addingTimeInterval(600 + 840)
        player.tick()
        XCTAssertEqual(player.state, .stopped)
        XCTAssertNil(player.remainingText)
        XCTAssertEqual(engine.calls.last, "stop")
    }

    func testChangingTheTimerStartsOver() {
        var current = testStart
        let player = FocusSoundPlayer(engine: FakeSoundEngine(), defaults: freshDefaults(), now: { current }, usesTimers: false, showsStatusItem: false)
        player.play()
        XCTAssertNil(player.remainingText)
        current = testStart.addingTimeInterval(100)
        player.setTimer(30)
        XCTAssertEqual(player.remainingText, "还剩 30:00")
        player.pause()
        player.setTimer(120)
        XCTAssertEqual(player.remainingText, "还剩 2:00:00")
        player.setTimer(0)
        XCTAssertNil(player.remainingText)
        // 不在几档里的当成不限时
        player.setTimer(7)
        XCTAssertEqual(player.timerMinutes, 0)
    }

    func testRemembersSoundVolumeAndTimer() {
        let defaults = freshDefaults()
        let first = FocusSoundPlayer(engine: FakeSoundEngine(), defaults: defaults, usesTimers: false, showsStatusItem: false)
        first.play(.pink)
        first.volume = 0.8
        first.setTimer(60)
        first.stop()
        let second = FocusSoundPlayer(engine: FakeSoundEngine(), defaults: defaults, usesTimers: false, showsStatusItem: false)
        XCTAssertEqual(second.sound, .pink)
        XCTAssertEqual(second.volume, 0.8)
        XCTAssertEqual(second.timerMinutes, 60)
        XCTAssertEqual(second.state, .stopped)
    }

    func testShowsWhyItCannotPlay() {
        let engine = FakeSoundEngine()
        let player = FocusSoundPlayer(engine: engine, defaults: freshDefaults(), now: { testStart }, usesTimers: false, showsStatusItem: false)
        engine.failure = NSError(domain: "PopTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "没有能用的输出设备"])
        player.play()
        XCTAssertEqual(player.state, .stopped)
        XCTAssertEqual(player.message, "放不出声音：没有能用的输出设备")

        engine.failure = nil
        player.play()
        XCTAssertEqual(player.state, .playing)
        XCTAssertNil(player.message)
        // 放着放着出不了声了
        engine.onFailure?("设备断开了")
        XCTAssertEqual(player.state, .stopped)
        XCTAssertEqual(player.message, "放不出声音：设备断开了")
    }

    func testTimerTitles() {
        XCTAssertEqual(FocusSoundPlayer.timerChoices.map { FocusSoundPlayer.timerTitle($0) }, ["不限时", "15 分钟", "30 分钟", "1 小时", "2 小时"])
    }

    func testDemoIsPlayingRainWithTimeLeft() {
        let player = FocusSoundsPlugin.demoPlayer()
        XCTAssertEqual(player.state, .playing)
        XCTAssertEqual(player.sound, .rain)
        XCTAssertEqual(player.volume, 0.6)
        XCTAssertEqual(player.remainingText, "还剩 24:12")
    }
}
