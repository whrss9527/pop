import AppKit
import AVFoundation
import Synchronization
@testable import Pop

/// 真正出声的部分，测试和演示时换成不出声的
@MainActor
protocol FocusSoundEngine: AnyObject {
    /// 放着放着出不了声了（比如换了输出设备以后起不来），参数是原因
    var onFailure: (@MainActor (String) -> Void)? { get set }
    /// 开始放，或者正在放时换声音、换音量
    func start(sound: FocusSound, volume: Float) throws
    func setVolume(_ volume: Float)
    func pause()
    func stop()
}

/// 主线程和实时线程之间传的参数：要放哪种声音、目标音量（Float 的位模式）
final class NoiseControls: Sendable {
    let sound = Atomic<Int>(0)
    let volumeBits = Atomic<UInt32>(0)

    var volume: Float {
        Float(bitPattern: volumeBits.load(ordering: .relaxed))
    }

    func set(volume: Float) {
        volumeBits.store(volume.bitPattern, ordering: .relaxed)
    }
}

/// 只在实时线程里用：左右两路生成器、现在的音量。音量变化都是渐变的；换声音时先淡出，换好再淡入
final class NoiseRenderer: @unchecked Sendable {
    private static let leftSeed: UInt64 = 0x1234_5678_9ABC_DEF1
    private static let rightSeed: UInt64 = 0x0FED_CBA9_8765_4323

    private let controls: NoiseControls
    private let sampleRate: Double
    private var current: FocusSound
    private var left: NoiseGenerator
    private var right: NoiseGenerator
    private var gain: Float = 0
    /// 每个样本往目标音量靠多少：大约 60 毫秒到位
    private let smoothing: Float

    init(controls: NoiseControls, sound: FocusSound, sampleRate: Double) {
        self.controls = controls
        self.sampleRate = sampleRate
        current = sound
        left = NoiseGenerator(sound: sound, sampleRate: sampleRate, seed: Self.leftSeed)
        right = NoiseGenerator(sound: sound, sampleRate: sampleRate, seed: Self.rightSeed)
        smoothing = Float(1 - exp(-1 / (0.06 * sampleRate)))
    }

    func render(frames: Int, into buffers: UnsafeMutableAudioBufferListPointer) {
        let requested = FocusSound(index: controls.sound.load(ordering: .relaxed))
        let target = controls.volume
        guard let first = buffers.first?.mData?.assumingMemoryBound(to: Float.self) else { return }
        let second = buffers.count > 1 ? buffers[1].mData?.assumingMemoryBound(to: Float.self) : nil
        for frame in 0..<frames {
            let wanted = requested == current ? target : 0
            gain += (wanted - gain) * smoothing
            if requested != current, gain < 0.0005 {
                current = requested
                left = NoiseGenerator(sound: requested, sampleRate: sampleRate, seed: Self.leftSeed)
                right = NoiseGenerator(sound: requested, sampleRate: sampleRate, seed: Self.rightSeed)
            }
            first[frame] = left.next() * gain
            second?[frame] = right.next() * gain
        }
    }
}

/// AVAudioEngine 加一个实时生成样本的 AVAudioSourceNode。第一次放的时候才建引擎；
/// 换了输出设备（插上耳机、连上 AirPods）时引擎会自己停下，这时接着放
@MainActor
final class NoiseEngine: FocusSoundEngine {
    var onFailure: (@MainActor (String) -> Void)?
    private var engine: AVAudioEngine?
    private let controls = NoiseControls()
    private var observer: NSObjectProtocol?
    private var wantsRunning = false
    /// 暂停、停止前先等声音淡下去；期间又放了就不停了
    private var generation = 0

    func start(sound: FocusSound, volume: Float) throws {
        controls.sound.store(sound.index, ordering: .relaxed)
        controls.set(volume: volume)
        generation += 1
        wantsRunning = true
        let engine = self.engine ?? makeEngine(sound: sound)
        if !engine.isRunning {
            engine.prepare()
            try engine.start()
        }
    }

    func setVolume(_ volume: Float) {
        controls.set(volume: volume)
    }

    func pause() {
        fadeOut { $0.pause() }
    }

    func stop() {
        fadeOut { $0.stop() }
    }

    private func makeEngine(sound: FocusSound) -> AVAudioEngine {
        let engine = AVAudioEngine()
        let sampleRate = 44_100.0
        if let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) {
            let node = Self.sourceNode(format: format, renderer: NoiseRenderer(controls: controls, sound: sound, sampleRate: sampleRate))
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
        }
        observer = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.restartAfterDeviceChange()
            }
        }
        self.engine = engine
        return engine
    }

    /// 渲染的闭包在音频的实时线程里调用，不能算在主线程上
    private nonisolated static func sourceNode(format: AVAudioFormat, renderer: NoiseRenderer) -> AVAudioSourceNode {
        AVAudioSourceNode(format: format) { _, _, frameCount, bufferList in
            renderer.render(frames: Int(frameCount), into: UnsafeMutableAudioBufferListPointer(bufferList))
            return noErr
        }
    }

    /// 只放声音的话输出那头会自己转换采样率，重新开起来就行。刚连上 AirPods 时设备可能还没准备好，起不来就过一秒再试一次
    private func restartAfterDeviceChange(retrying: Bool = true) {
        guard wantsRunning, let engine, !engine.isRunning else { return }
        do {
            engine.prepare()
            try engine.start()
        } catch {
            if retrying {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                    MainActor.assumeIsolated {
                        self?.restartAfterDeviceChange(retrying: false)
                    }
                }
                return
            }
            wantsRunning = false
            onFailure?(error.localizedDescription)
        }
    }

    /// 音量先降到 0（渲染那边大约 60 毫秒降完），过一会儿再真的暂停或停止，免得「啪」的一声
    private func fadeOut(then action: @escaping (AVAudioEngine) -> Void) {
        wantsRunning = false
        controls.set(volume: 0)
        generation += 1
        let expected = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == expected, !self.wantsRunning, let engine = self.engine else { return }
                action(engine)
            }
        }
    }
}

/// 白噪音放着的时候：放什么、多大声、什么时候停。卡片和菜单栏的小图标都看它
@MainActor
final class FocusSoundPlayer: ObservableObject {
    static let shared = FocusSoundPlayer(engine: NoiseEngine())
    static let soundKey = "pop.focusSounds.sound"
    static let volumeKey = "pop.focusSounds.volume"
    static let timerKey = "pop.focusSounds.timer"
    /// 定时停止的几档（分钟），0 是不限时
    static let timerChoices = [0, 15, 30, 60, 120]
    /// 到点前多少秒开始慢慢变小声
    static let fadeSeconds = 5.0

    enum State: Equatable {
        case stopped, playing, paused
    }

    @Published private(set) var state = State.stopped
    @Published private(set) var sound: FocusSound
    /// 音量条的位置，0…1
    @Published var volume: Double {
        didSet {
            defaults.set(volume, forKey: Self.volumeKey)
            applyVolume()
        }
    }
    /// 定时停止：0 是不限时
    @Published private(set) var timerMinutes: Int
    /// 在放的时候：几点停
    @Published private(set) var endsAt: Date?
    /// 暂停的时候：还剩多少秒（暂停时不算时间）
    @Published private(set) var pausedRemaining: TimeInterval?
    /// 放不出声音时的说明
    @Published private(set) var message: String?
    /// 每秒更新一次，剩余时间跟着变
    @Published private(set) var clock: Date

    private let engine: FocusSoundEngine
    private let defaults: UserDefaults
    private let now: () -> Date
    private let usesTimers: Bool
    private let showsStatusItem: Bool
    private var ticker: Timer?
    /// 快到点时从 1 慢慢降到 0
    private var fade: Double = 1
    private var statusItem: FocusSoundStatusItem?

    init(engine: FocusSoundEngine, defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init,
         usesTimers: Bool = true, showsStatusItem: Bool = true) {
        self.engine = engine
        self.defaults = defaults
        self.now = now
        self.usesTimers = usesTimers
        self.showsStatusItem = showsStatusItem
        sound = FocusSound(rawValue: defaults.string(forKey: Self.soundKey) ?? "") ?? .rain
        let savedVolume = defaults.object(forKey: Self.volumeKey) as? Double ?? 0.5
        volume = min(max(savedVolume, 0), 1)
        let savedTimer = defaults.integer(forKey: Self.timerKey)
        timerMinutes = Self.timerChoices.contains(savedTimer) ? savedTimer : 0
        clock = now()
        engine.onFailure = { [weak self] reason in
            self?.fail(reason)
        }
    }

    /// 放这种声音（正在放别的就换过去）；不给的话放上次的
    func play(_ next: FocusSound? = nil) {
        if let next, next != sound {
            sound = next
            defaults.set(next.rawValue, forKey: Self.soundKey)
        }
        do {
            try engine.start(sound: sound, volume: engineVolume)
        } catch {
            fail(error.localizedDescription)
            return
        }
        message = nil
        switch state {
        case .stopped:
            restartTimer()
        case .paused:
            resumeTimer()
        case .playing:
            break
        }
        state = .playing
        updateTicker()
        updateStatusItem()
    }

    /// 点了卡片上的一种声音：正在放的就是它就暂停，不然换过去放
    func select(_ next: FocusSound) {
        if next == sound, state == .playing {
            pause()
        } else {
            play(next)
        }
    }

    /// 卡片上的大按钮、菜单栏菜单：在放就暂停，没在放就放
    func togglePlay() {
        if state == .playing {
            pause()
        } else {
            play()
        }
    }

    /// 暂停：定时停止也停在这里，接着放时再接着算
    func pause() {
        guard state == .playing else { return }
        engine.pause()
        pausedRemaining = endsAt.map { max(0, $0.timeIntervalSince(now())) }
        endsAt = nil
        state = .paused
        updateTicker()
        updateStatusItem()
    }

    func stop() {
        engine.stop()
        state = .stopped
        endsAt = nil
        pausedRemaining = nil
        fade = 1
        updateTicker()
        statusItem?.remove()
        statusItem = nil
    }

    /// 改定时：在放或者暂停着的话从现在开始重新算
    func setTimer(_ minutes: Int) {
        timerMinutes = Self.timerChoices.contains(minutes) ? minutes : 0
        defaults.set(timerMinutes, forKey: Self.timerKey)
        guard state != .stopped else { return }
        restartTimer()
        fade = 1
        applyVolume()
        updateTicker()
        updateStatusItem()
    }

    /// 每秒一次：最后几秒慢慢变小声，到点就停
    func tick() {
        clock = now()
        statusItem?.update()
        guard state == .playing, let endsAt else { return }
        let left = endsAt.timeIntervalSince(clock)
        if left <= 0 {
            stop()
        } else if left < Self.fadeSeconds {
            fade = left / Self.fadeSeconds
            applyVolume()
        }
    }

    /// 还剩多少秒；不限时、没在放时为 nil
    var remaining: TimeInterval? {
        switch state {
        case .stopped:
            return nil
        case .paused:
            return pausedRemaining
        case .playing:
            return endsAt.map { max(0, $0.timeIntervalSince(clock)) }
        }
    }

    /// 「还剩 24:12」
    var remainingText: String? {
        guard let remaining else { return nil }
        return String(localized: "还剩 \(CountdownTimer.clock(Int(remaining.rounded(.up))))")
    }

    /// 菜单栏菜单里的一句：「正在放雨声 · 还剩 24:12」「雨声 · 已暂停」
    var statusText: String? {
        switch state {
        case .stopped:
            return nil
        case .playing:
            let playing = String(localized: "正在放\(sound.title)")
            return remainingText.map { playing + " · " + $0 } ?? playing
        case .paused:
            return String(localized: "\(sound.title) · 已暂停")
        }
    }

    /// 定时停止那几档的名字：「不限时」「15 分钟」「1 小时」
    nonisolated static func timerTitle(_ minutes: Int) -> String {
        if minutes <= 0 {
            return String(localized: "不限时")
        }
        if minutes % 60 == 0 {
            return String(localized: "\(minutes / 60) 小时")
        }
        return String(localized: "\(minutes) 分钟")
    }

    /// 音量条是线性的，听起来的大小按平方算
    private var engineVolume: Float {
        Float(volume * volume * fade)
    }

    private func applyVolume() {
        guard state == .playing else { return }
        engine.setVolume(engineVolume)
    }

    private func fail(_ reason: String) {
        stop()
        message = String(localized: "放不出声音：\(reason)")
    }

    /// 从现在开始重新算定时
    private func restartTimer() {
        let start = now()
        clock = start
        let length = timerMinutes > 0 ? TimeInterval(timerMinutes * 60) : nil
        if state == .paused {
            pausedRemaining = length
        } else {
            endsAt = length.map { start.addingTimeInterval($0) }
        }
    }

    private func resumeTimer() {
        let start = now()
        clock = start
        endsAt = pausedRemaining.map { start.addingTimeInterval($0) }
        pausedRemaining = nil
    }

    /// 有定时、正在放的时候每秒走一次（菜单、弹出菜单开着时也走），别的时候不用
    private func updateTicker() {
        let needed = usesTimers && state == .playing && endsAt != nil
        if needed, ticker == nil {
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.tick()
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            ticker = timer
        } else if !needed {
            ticker?.invalidate()
            ticker = nil
        }
    }

    private func updateStatusItem() {
        guard showsStatusItem, state != .stopped else { return }
        if statusItem == nil {
            statusItem = FocusSoundStatusItem(player: self)
        }
        statusItem?.update()
    }
}

/// 放着白噪音时菜单栏里的耳机图标：点开能暂停、接着放、停止
@MainActor
final class FocusSoundStatusItem: NSObject, NSMenuDelegate {
    private let item: NSStatusItem
    private weak var player: FocusSoundPlayer?

    init(player: FocusSoundPlayer) {
        self.player = player
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        let image = NSImage(systemSymbolName: "headphones", accessibilityDescription: String(localized: "白噪音"))
        image?.isTemplate = true
        item.button?.image = image
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        update()
    }

    func update() {
        item.button?.toolTip = player?.statusText
        item.button?.appearsDisabled = player?.state == .paused
    }

    func remove() {
        NSStatusBar.system.removeStatusItem(item)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let player else { return }
        let title = NSMenuItem(title: player.statusText ?? String(localized: "白噪音"), action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())
        let toggle = NSMenuItem(title: player.state == .playing ? String(localized: "暂停") : String(localized: "接着放"),
                                action: #selector(togglePlay), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)
        let stop = NSMenuItem(title: String(localized: "停止"), action: #selector(stopPlaying), keyEquivalent: "")
        stop.target = self
        menu.addItem(stop)
    }

    @objc private func togglePlay() {
        player?.togglePlay()
    }

    @objc private func stopPlaying() {
        player?.stop()
    }
}
