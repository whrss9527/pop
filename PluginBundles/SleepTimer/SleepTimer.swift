import AppKit
import AudioToolbox
import CoreAudio
import SwiftUI
@testable import Pop

/// 到点以后做什么
enum SleepTimerAction: String, CaseIterable, Identifiable {
    case sleep
    case displaySleep
    case lock
    case shutDown

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sleep: return String(localized: "睡眠", bundle: .sleepTimer)
        case .displaySleep: return String(localized: "熄屏", bundle: .sleepTimer)
        case .lock: return String(localized: "锁屏", bundle: .sleepTimer)
        case .shutDown: return String(localized: "关机", bundle: .sleepTimer)
        }
    }

    var symbol: String {
        switch self {
        case .sleep: return "moon.zzz.fill"
        case .displaySleep: return "display"
        case .lock: return "lock.fill"
        case .shutDown: return "power"
        }
    }

    /// 最后一分钟慢慢调小音量：睡眠、关机时才调（熄屏、锁屏以后声音照常放）
    var fadesVolume: Bool {
        self == .sleep || self == .shutDown
    }

    /// 「23:30 睡眠」
    func at(_ time: String) -> String {
        switch self {
        case .sleep: return String(localized: "\(time) 睡眠", bundle: .sleepTimer)
        case .displaySleep: return String(localized: "\(time) 熄屏", bundle: .sleepTimer)
        case .lock: return String(localized: "\(time) 锁屏", bundle: .sleepTimer)
        case .shutDown: return String(localized: "\(time) 关机", bundle: .sleepTimer)
        }
    }

    /// 「0:42 后睡眠」
    func after(_ clock: String) -> String {
        switch self {
        case .sleep: return String(localized: "\(clock) 后睡眠", bundle: .sleepTimer)
        case .displaySleep: return String(localized: "\(clock) 后熄屏", bundle: .sleepTimer)
        case .lock: return String(localized: "\(clock) 后锁屏", bundle: .sleepTimer)
        case .shutDown: return String(localized: "\(clock) 后关机", bundle: .sleepTimer)
        }
    }
}

/// 定时睡眠：过一会儿（或者到几点）让 Mac 睡眠、熄屏、锁屏或者关机。最后一分钟在屏幕上方提示，可以推迟、取消；
/// 睡眠、关机前慢慢把音量调小，醒来（下次开机）以后调回去
@MainActor
final class SleepTimer: ObservableObject {
    static let shared = SleepTimer()

    static let actionKey = "pop.sleepTimer.action"
    static let minutesKey = "pop.sleepTimer.minutes"
    static let fadeKey = "pop.sleepTimer.fade"
    static let pendingKey = "pop.sleepTimer.pending"
    static let volumeKey = "pop.sleepTimer.volume"
    static let defaultsKeys = [actionKey, minutesKey, fadeKey, pendingKey, volumeKey]

    /// 多久以后（分钟）
    static let durations = [15, 30, 45, 60, 90, 120]
    /// 最后多久提示、调小音量
    static let warningSeconds: TimeInterval = 60
    /// 推迟多久（分钟）
    static let postponeMinutes = 10
    /// 睡眠、关机的命令发出去以后，过这么久 Mac 还醒着（没睡成、关机被 App 拦下了）就把音量调回去
    static let restoreAfter: TimeInterval = 90

    /// 定好的一次
    struct Pending: Equatable {
        let deadline: Date
        let action: SleepTimerAction

        var dictionary: [String: Any] {
            ["deadline": deadline, "action": action.rawValue]
        }

        init(deadline: Date, action: SleepTimerAction) {
            self.deadline = deadline
            self.action = action
        }

        init?(dictionary: [String: Any]?) {
            guard let deadline = dictionary?["deadline"] as? Date,
                  let action = (dictionary?["action"] as? String).flatMap(SleepTimerAction.init(rawValue:)) else { return nil }
            self.init(deadline: deadline, action: action)
        }
    }

    /// 睡眠、锁屏、音量、通知、时钟：平时是真的，测试、演示时是造的
    struct Environment {
        /// 做这件事；没做成时返回原因
        var perform: @MainActor (SleepTimerAction) async -> String?
        /// 关机要能控制「System Events」：没允许时返回要说的话
        var checkPermission: @MainActor () async -> String?
        /// 现在的输出音量（0～1）；设备不能调音量时是 nil
        var volume: @MainActor () -> Float?
        var setVolume: @MainActor (Float) -> Void
        var notify: @MainActor (_ title: String, _ body: String) -> Void
        var now: () -> Date
        var calendar: Calendar

        static var live: Environment {
            Environment(perform: { action in
                            switch action {
                            case .sleep: return await SystemActions.run(.sleep)
                            case .displaySleep: return await SystemActions.run(.displaySleep)
                            case .lock: return await SystemActions.run(.lockScreen)
                            case .shutDown:
                                // 照平常的样子关机：没存的文稿 App 会问，可能被拦下
                                switch await SleepTimer.systemEvents("tell application \"System Events\" to shut down") {
                                case .done: return nil
                                case .denied(let message): return message
                                case .failed(let reason): return reason.map { String(localized: "没能关机：\($0)", bundle: .sleepTimer) } ?? String(localized: "没能关机", bundle: .sleepTimer)
                                }
                            }
                        },
                        checkPermission: {
                            // 随便问「System Events」一句：没问过的话 macOS 这时会问能不能控制它；别的原因没问成的先不拦着
                            if case .denied(let message) = await SleepTimer.systemEvents("tell application \"System Events\" to get name") {
                                return message
                            }
                            return nil
                        },
                        volume: {
                            guard let device = SleepTimer.outputDevice() else { return nil }
                            return SleepTimer.volume(of: device)
                        },
                        setVolume: { value in
                            guard let device = SleepTimer.outputDevice() else { return }
                            SleepTimer.setVolume(value, of: device)
                        },
                        notify: { title, body in Notifier.shared.showReminder(title: title, body: body) },
                        now: Date.init,
                        calendar: .autoupdatingCurrent)
        }
    }

    @Published private(set) var action: SleepTimerAction = .sleep
    /// 上次选的「多久以后」（分钟）
    @Published private(set) var minutes = 30
    /// 最后一分钟慢慢调小音量（睡眠、关机时）
    @Published private(set) var fades = true
    @Published private(set) var pending: Pending?
    /// 卡片上的时刻
    @Published private(set) var now: Date
    /// 卡片上要说的话：没允许控制「System Events」、没做成
    @Published private(set) var message: String?
    /// 正在显示最后一分钟的提示
    @Published private(set) var isWarning = false
    /// 调小以前的音量：取消、推迟、醒来以后调回去
    private(set) var fadedFrom: Float?

    let environment: Environment
    private let defaults: UserDefaults
    /// 测试、演示时不开定时器、不弹提示、不听系统通知
    private let isLive: Bool
    private var timer: Timer?
    private var restoreTimer: Timer?
    /// 定着的时候不让系统把 Pop 的定时器一推再推（App Nap）
    private var activity: NSObjectProtocol?
    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    /// 命令发出去以后 Mac 真的睡着了
    private var didSleep = false
    /// 正在做（测试里等它做完）
    private(set) var firing: Task<Void, Never>?
    private var banner: SleepTimerBannerPanel?

    init(defaults: UserDefaults = .standard, environment: Environment = .live, isLive: Bool = true) {
        self.defaults = defaults
        self.environment = environment
        self.isLive = isLive
        now = environment.now()
        loadSettings()
    }

    private func loadSettings() {
        action = defaults.string(forKey: Self.actionKey).flatMap(SleepTimerAction.init(rawValue:)) ?? .sleep
        let saved = defaults.integer(forKey: Self.minutesKey)
        minutes = Self.durations.contains(saved) ? saved : 30
        fades = defaults.object(forKey: Self.fadeKey) as? Bool ?? true
        pending = Pending(dictionary: defaults.dictionary(forKey: Self.pendingKey))
        fadedFrom = (defaults.object(forKey: Self.volumeKey) as? NSNumber)?.floatValue
    }

    // MARK: - 开始、停下

    /// 插件包装载时（Pop 启动、装上插件）：上次调小了的音量调回去（关机以后再开机）；还没到点的接着等，过了点的不再做
    func startIfNeeded() {
        loadSettings()
        now = environment.now()
        restoreVolume()
        if let pending, pending.deadline <= now {
            clearPending()
        }
        observe()
        schedule()
    }

    /// 卸载插件时：取消，音量调回去
    func shutDown() {
        cancel()
        observers.forEach { $0.center.removeObserver($0.token) }
        observers.removeAll()
        restoreTimer?.invalidate()
        restoreTimer = nil
    }

    /// 过 minutes 分钟以后
    func start(minutes: Int) async {
        guard Self.durations.contains(minutes) else { return }
        self.minutes = minutes
        defaults.set(minutes, forKey: Self.minutesKey)
        await begin(at: environment.now().addingTimeInterval(TimeInterval(minutes * 60)))
    }

    /// 到几点（今天的已经过了，或者不到一分钟以后，就是明天的）
    func start(at time: Date) async {
        await begin(at: Self.nextOccurrence(of: time, after: environment.now(), calendar: environment.calendar))
    }

    /// time 的钟点在 now 以后（至少一分钟）第一次出现的时候
    static func nextOccurrence(of time: Date, after now: Date, calendar: Calendar) -> Date {
        let parts = calendar.dateComponents([.hour, .minute], from: time)
        let match = DateComponents(hour: parts.hour ?? 0, minute: parts.minute ?? 0, second: 0)
        let earliest = now.addingTimeInterval(warningSeconds)
        return calendar.nextDate(after: earliest.addingTimeInterval(-1), matching: match, matchingPolicy: .nextTime) ?? earliest
    }

    private func begin(at deadline: Date) async {
        message = nil
        // 关机先问能不能控制「System Events」：现在就问，不要等到半夜
        if action == .shutDown, let reason = await environment.checkPermission() {
            message = reason
            return
        }
        restoreVolume()
        hideBanner()
        isWarning = false
        let pending = Pending(deadline: deadline, action: action)
        self.pending = pending
        defaults.set(pending.dictionary, forKey: Self.pendingKey)
        now = environment.now()
        observe()
        schedule()
    }

    /// 推迟 10 分钟（最后一分钟里推迟的，从现在算）
    func postpone() {
        guard let pending else { return }
        now = environment.now()
        let base = pending.deadline.timeIntervalSince(now) <= Self.warningSeconds ? now : pending.deadline
        let later = Pending(deadline: base.addingTimeInterval(TimeInterval(Self.postponeMinutes * 60)), action: pending.action)
        self.pending = later
        defaults.set(later.dictionary, forKey: Self.pendingKey)
        isWarning = false
        hideBanner()
        restoreVolume()
        schedule()
    }

    func cancel() {
        clearPending()
        isWarning = false
        hideBanner()
        restoreVolume()
        schedule()
    }

    private func clearPending() {
        pending = nil
        defaults.removeObject(forKey: Self.pendingKey)
    }

    // MARK: - 到点

    /// 看一次：最后一分钟提示、调小音量；到点就做
    func tick() {
        now = environment.now()
        guard let pending else {
            schedule()
            return
        }
        let remaining = pending.deadline.timeIntervalSince(now)
        if remaining <= 0 {
            fire(pending)
            return
        }
        if remaining <= Self.warningSeconds {
            if !isWarning {
                isWarning = true
                showBanner()
            }
            if fades, pending.action.fadesVolume {
                if fadedFrom == nil, let volume = environment.volume(), volume > 0 {
                    fadedFrom = volume
                    defaults.set(volume, forKey: Self.volumeKey)
                }
                if let from = fadedFrom {
                    environment.setVolume(from * Float(remaining / Self.warningSeconds))
                }
            }
        }
        schedule()
    }

    private func fire(_ pending: Pending) {
        clearPending()
        isWarning = false
        hideBanner()
        schedule()
        if fadedFrom != nil {
            environment.setVolume(0)
        }
        didSleep = false
        firing = Task { @MainActor in
            if let reason = await environment.perform(pending.action) {
                restoreVolume()
                environment.notify(String(localized: "定时睡眠没做成", bundle: .sleepTimer), reason)
                return
            }
            // 睡眠：醒来时调回去；关机被 App 拦下了、没睡成：过一会儿还醒着就调回去
            guard fadedFrom != nil, isLive else { return }
            restoreTimer?.invalidate()
            let timer = Timer(timeInterval: Self.restoreAfter, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, !self.didSleep else { return }
                    self.restoreVolume()
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            restoreTimer = timer
        }
    }

    /// 调小了的音量调回去
    func restoreVolume() {
        guard let from = fadedFrom else { return }
        environment.setVolume(from)
        fadedFrom = nil
        defaults.removeObject(forKey: Self.volumeKey)
    }

    /// 下一次看：最后一分钟里每秒一次，之前在还剩一分钟的时候
    private func schedule() {
        guard isLive else { return }
        timer?.invalidate()
        timer = nil
        guard let pending else {
            if let activity {
                ProcessInfo.processInfo.endActivity(activity)
                self.activity = nil
            }
            return
        }
        if activity == nil {
            activity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep, reason: "Sleep timer")
        }
        let remaining = pending.deadline.timeIntervalSince(now)
        let fire = remaining <= Self.warningSeconds ? now.addingTimeInterval(min(1, max(0.05, remaining))) : pending.deadline.addingTimeInterval(-Self.warningSeconds)
        let timer = Timer(fire: fire, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// 睡着、醒来、改了时间
    private func observe() {
        guard isLive, observers.isEmpty else { return }
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append((workspace, workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.didSleep = true }
        }))
        observers.append((workspace, workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.woke() }
        }))
        observers.append((NotificationCenter.default, NotificationCenter.default.addObserver(forName: .NSSystemClockDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }))
    }

    /// 醒来：调小了的音量调回去；睡着的时候过了点的不再做（刚醒就又睡、又关机不对）；还没到点的按剩下的时间重新定
    func woke() {
        now = environment.now()
        restoreVolume()
        if let pending, pending.deadline <= now {
            clearPending()
            isWarning = false
            hideBanner()
        }
        tick()
    }

    /// 卡片打开时：清掉上次要说的话；过了点还没做的马上做
    func cardAppeared() {
        message = nil
        tick()
    }

    // MARK: - 设置

    func setAction(_ action: SleepTimerAction) {
        self.action = action
        defaults.set(action.rawValue, forKey: Self.actionKey)
        message = nil
    }

    func setFades(_ fades: Bool) {
        self.fades = fades
        defaults.set(fades, forKey: Self.fadeKey)
        if !fades {
            restoreVolume()
        }
    }

    // MARK: - 屏幕上方的提示

    private func showBanner() {
        guard isLive else { return }
        let panel = banner ?? SleepTimerBannerPanel(rootView: SleepTimerBanner(model: self))
        banner = panel
        panel.place()
        panel.orderFrontRegardless()
        DispatchQueue.main.async {
            MainActor.assumeIsolated { panel.place() }
        }
    }

    private func hideBanner() {
        banner?.orderOut(nil)
    }

    /// 演示用：屏幕上方的提示（不开定时器），返回它的位置
    func showBannerForDemo(on screen: NSScreen) -> CGRect {
        let panel = SleepTimerBannerPanel(rootView: SleepTimerBanner(model: self))
        banner = panel
        panel.place(on: screen)
        panel.sharingType = .readOnly
        panel.orderFrontRegardless()
        return panel.frame
    }

    func hideBannerForDemo() {
        banner?.orderOut(nil)
        banner = nil
    }

    /// 演示用：直接放好正在定时、最后一分钟
    func setDemoState(pending: Pending?, warning: Bool) {
        self.pending = pending
        isWarning = warning
    }

    // MARK: - 写法

    /// 「28:41」「1:05:00」
    static func clock(_ seconds: TimeInterval) -> String {
        CountdownTimer.clock(max(0, Int(seconds.rounded(.up))))
    }

    /// 「23:30」：按系统的时区
    static func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    /// 「30 分钟」「1 小时 30 分钟」
    static func durationTitle(_ minutes: Int) -> String {
        CountdownTimer.title(seconds: TimeInterval(minutes * 60))
    }

    // MARK: - 系统

    enum ScriptResult {
        case done
        /// 没允许 Pop 控制「System Events」：说去哪里允许
        case denied(String)
        /// 别的原因（超时、出错）；有原因时带着
        case failed(String?)
    }

    /// 让「System Events」做一件事。系统在问能不能控制它的时候脚本会等着，所以最多等两分钟
    static func systemEvents(_ script: String) async -> ScriptResult {
        let result = await ProcessRunner.run(URL(fileURLWithPath: "/usr/bin/osascript"), arguments: ["-e", script], stdin: nil,
                                             environment: [:], timeout: 120)
        switch result {
        case .success(let output) where output.status == 0 && !output.timedOut:
            return .done
        case .success(let output):
            let reason = output.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if reason.contains("-1743") {
                return .denied(String(localized: "要先在「系统设置 → 隐私与安全性 → 自动化」里允许 Pop 控制「System Events」", bundle: .sleepTimer))
            }
            return .failed(output.timedOut || reason.isEmpty ? nil : reason)
        case .failure(let error):
            return .failed(error.message)
        }
    }

    static func outputDevice() -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != kAudioObjectUnknown else { return nil }
        return device
    }

    private static func volumeAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume, mScope: kAudioDevicePropertyScopeOutput,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    /// 系统音量条用的那个音量（0～1）
    static func volume(of device: AudioObjectID) -> Float? {
        var address = volumeAddress()
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    static func setVolume(_ value: Float, of device: AudioObjectID) {
        var address = volumeAddress()
        guard AudioObjectHasProperty(device, &address) else { return }
        var settable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(device, &address, &settable) == noErr, settable.boolValue else { return }
        var volume = Float32(min(max(value, 0), 1))
        _ = AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &volume)
    }
}
