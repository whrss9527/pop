import AppKit
import SwiftUI
@testable import Pop

/// 休息提醒：开着时每隔一会儿看看连续用了多久，到点在屏幕上方弹一个提醒；点「休息」开始倒计时，可以盖住屏幕
@MainActor
final class BreakReminder: ObservableObject {
    static let shared = BreakReminder()

    static let enabledKey = "pop.breakReminder.enabled"
    static let intervalKey = "pop.breakReminder.interval"
    static let lengthKey = "pop.breakReminder.length"
    static let fullScreenKey = "pop.breakReminder.fullScreen"
    static let defaultsKeys = [enabledKey, intervalKey, lengthKey, fullScreenKey]

    /// 每隔多久提醒（分钟）
    static let intervalChoices = [20, 30, 45, 60, 90]
    /// 一次休息多久（秒）
    static let lengthChoices = [20, 60, 180, 300, 600]
    static let defaultInterval = 45
    static let defaultLength = 300
    /// 「过一会儿再提醒」
    static let snoozeSeconds: TimeInterval = 300
    /// 平时多久看一次；休息倒计时的时候每秒一次
    static let tickSeconds: TimeInterval = 10
    /// 休息完了的那句话停多久
    static let finishedSeconds: TimeInterval = 4
    /// 两次看之间隔了这么久，就是睡过了（醒着的时候十秒看一次）
    static let sleepGap: TimeInterval = 60

    enum Phase: Equatable {
        case hidden
        /// 该休息了
        case reminder
        /// 正在休息（没盖住屏幕时，倒计时在上方的小条里）
        case onBreak
        /// 休息好了
        case finished
    }

    @Published private(set) var isEnabled: Bool
    @Published private(set) var schedule: BreakSchedule
    @Published var fullScreen: Bool {
        didSet { defaults.set(fullScreen, forKey: Self.fullScreenKey) }
    }
    @Published private(set) var phase: Phase = .hidden
    /// 有别的 App 不让屏幕变暗（在放视频、开会），先不提醒
    @Published private(set) var isQuiet = false
    /// 上一次看的时刻，卡片上的文字跟着它变
    @Published private(set) var now: Date
    /// 第几次休息：换着说休息时做什么
    private(set) var breakCount = 0

    private let defaults: UserDefaults
    private let clock: () -> Date
    private let idle: () -> TimeInterval
    private let quiet: () -> Bool
    /// 测试、演示时不开窗口、不开定时器
    private let isLive: Bool
    private var timer: Timer?
    private var finishedTimer: Timer?
    private var panel: BreakReminderPanel?
    private var overlays: [NSWindow] = []

    /// 屏幕上方的小条、休息时盖住屏幕的那几层：Pop 录屏时按这些编号把它们排除掉
    var windowNumbers: [Int] {
        ([panel].compactMap { $0 } + overlays).filter(\.isVisible).map(\.windowNumber)
    }
    /// 盖住屏幕之前在前台的 App，休息完还给它
    private var previousApp: NSRunningApplication?
    private var observers: [NSObjectProtocol] = []
    /// 什么时候睡的：睡醒时「多久没碰键盘鼠标」会清零，睡了多久要自己记
    private var sleptAt: Date?
    /// 睡之前已经离开了多久：走开几分钟再合上盖子，这几分钟也算在休息里
    private var awayBeforeSleep: TimeInterval = 0

    init(defaults: UserDefaults = .standard, clock: @escaping () -> Date = Date.init,
         idle: @escaping () -> TimeInterval = BreakSignals.idleSeconds,
         quiet: @escaping () -> Bool = BreakSignals.othersKeepDisplayAwake, isLive: Bool = true) {
        self.defaults = defaults
        self.clock = clock
        self.idle = idle
        self.quiet = quiet
        self.isLive = isLive
        let saved = Self.savedSettings(defaults)
        schedule = BreakSchedule(interval: saved.interval, breakLength: saved.length)
        isEnabled = saved.enabled
        fullScreen = saved.fullScreen
        now = clock()
    }

    /// 存着的设置；存的值不在几档里时用默认的
    private static func savedSettings(_ defaults: UserDefaults) -> (enabled: Bool, interval: TimeInterval, length: TimeInterval, fullScreen: Bool) {
        let minutes = defaults.object(forKey: intervalKey) as? Int ?? defaultInterval
        let seconds = defaults.object(forKey: lengthKey) as? Int ?? defaultLength
        return (defaults.bool(forKey: enabledKey),
                TimeInterval(intervalChoices.contains(minutes) ? minutes : defaultInterval) * 60,
                TimeInterval(lengthChoices.contains(seconds) ? seconds : defaultLength),
                defaults.bool(forKey: fullScreenKey))
    }

    var intervalMinutes: Int {
        Int(schedule.interval / 60)
    }

    var breakSeconds: Int {
        Int(schedule.breakLength)
    }

    // MARK: - 设置

    /// 插件包装载时（Pop 启动、装上插件）：按存着的设置来（卸载时可能一起删掉了），开着的话接着计时
    func startIfEnabled() {
        let saved = Self.savedSettings(defaults)
        isEnabled = saved.enabled
        schedule.interval = saved.interval
        schedule.breakLength = saved.length
        // 卸载时删掉的设置不要马上又写回去
        if fullScreen != saved.fullScreen {
            fullScreen = saved.fullScreen
        }
        if isEnabled {
            startTicking()
        }
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        defaults.set(enabled, forKey: Self.enabledKey)
        // 没开的时候在卡片上点了「现在休息」：打开时让这次休息走完
        if enabled, schedule.isOnBreak {
            startTicking()
            return
        }
        schedule.reset()
        hideEverything()
        if enabled {
            tick()
            startTicking()
        } else {
            stopTicking()
        }
    }

    func setInterval(minutes: Int) {
        guard Self.intervalChoices.contains(minutes) else { return }
        schedule.interval = TimeInterval(minutes) * 60
        defaults.set(minutes, forKey: Self.intervalKey)
        now = clock()
    }

    func setBreakLength(seconds: Int) {
        guard Self.lengthChoices.contains(seconds) else { return }
        schedule.breakLength = TimeInterval(seconds)
        defaults.set(seconds, forKey: Self.lengthKey)
        now = clock()
    }

    // MARK: - 计时

    func tick() {
        let previous = now
        now = clock()
        if let sleptAt {
            if now.timeIntervalSince(previous) >= Self.sleepGap {
                // 睡醒时定时器、屏幕醒来的通知可能比「睡醒了」的通知先到：先把睡的这段算上，免得提醒闪一下
                wake(at: now)
            } else if now.timeIntervalSince(sleptAt) >= Self.sleepGap {
                // 说了要睡又没睡着（被别的 App 拦下了），一直醒着：不算
                self.sleptAt = nil
            }
        }
        guard isEnabled || schedule.isOnBreak else { return }
        let isQuiet = schedule.isOnBreak ? false : quiet()
        self.isQuiet = isQuiet
        switch schedule.update(now: now, idle: idle(), quiet: isQuiet) {
        case .remind:
            show(.reminder)
        case .none where schedule.isDue:
            // 提醒着的时候开始放视频、开会：先收起来，结束了再弹出来
            if isQuiet, phase == .reminder {
                hidePanel()
            } else if !isQuiet, phase == .hidden {
                show(.reminder)
            }
        case .rested:
            if phase == .reminder {
                hideEverything()
            }
        case .breakFinished:
            hideOverlays()
            show(.finished)
            if isLive {
                NSSound(named: "Glass")?.play()
            }
        case .none:
            break
        }
        retimeIfNeeded()
    }

    /// 现在休息：提醒里点「休息」，或者卡片上点「现在休息」
    func takeBreak() {
        now = clock()
        breakCount += 1
        schedule.startBreak(now: now)
        if fullScreen {
            hidePanel()
            phase = .onBreak
            showOverlays()
        } else {
            show(.onBreak)
        }
        retimeIfNeeded()
    }

    /// 提前结束休息
    func endBreak() {
        schedule.finishBreak()
        hideEverything()
        retimeIfNeeded()
    }

    func snooze() {
        schedule.snooze(now: clock(), for: Self.snoozeSeconds)
        hideEverything()
    }

    func skip() {
        schedule.skip(now: clock())
        hideEverything()
    }

    /// 要睡了：记下时刻，和这时已经离开了多久
    func willSleep() {
        let now = clock()
        sleptAt = now
        awayBeforeSleep = schedule.away(now: now, idle: idle())
    }

    /// 睡醒了：马上看一次
    func didWake() {
        wake(at: clock())
        tick()
    }

    /// 睡之前离开的加上睡的够长，就算休息过了，提醒着的话收起来
    private func wake(at now: Date) {
        guard let sleptAt else { return }
        self.sleptAt = nil
        guard !schedule.isOnBreak, now.timeIntervalSince(sleptAt) + awayBeforeSleep >= schedule.restThreshold else { return }
        schedule.rest()
        if phase == .reminder {
            hidePanel()
        }
    }

    /// 卸载插件包、关掉的时候
    func shutDown() {
        stopTicking()
        schedule.reset()
        hideEverything()
    }

    private func startTicking() {
        guard isLive else { return }
        // 休息倒计时的定时器可能已经在走了；睡醒、解锁的通知照样要接
        if timer == nil {
            scheduleTimer(every: schedule.isOnBreak ? 1 : Self.tickSeconds)
        }
        guard observers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.willSleep() }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.didWake() }
        })
        // 屏幕醒来、解锁回来马上看一次：离开够久的话已经算休息过了
        for name in [NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            })
        }
    }

    private func stopTicking() {
        timer?.invalidate()
        timer = nil
        let center = NSWorkspace.shared.notificationCenter
        observers.forEach { center.removeObserver($0) }
        observers.removeAll()
    }

    private func scheduleTimer(every seconds: TimeInterval) {
        timer?.invalidate()
        let timer = Timer(timeInterval: seconds, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = seconds >= Self.tickSeconds ? 2 : 0.1
        // 菜单开着的时候也照样走
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// 休息倒计时时每秒走一次，平时十秒一次
    private func retimeIfNeeded() {
        guard isLive, let timer else {
            if isLive, schedule.isOnBreak {
                scheduleTimer(every: 1)
            }
            return
        }
        let wanted = schedule.isOnBreak ? 1 : Self.tickSeconds
        if timer.timeInterval != wanted {
            if isEnabled || schedule.isOnBreak {
                scheduleTimer(every: wanted)
            } else {
                stopTicking()
            }
        }
    }

    // MARK: - 写在卡片和提醒上的

    /// 「32 分钟」「1 小时 5 分钟」
    nonisolated static func durationText(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded(.down))
        if minutes < 1 {
            // 总是接在「已经连续用了」后面，英文要小写
            return String(localized: "不到一分钟")
        }
        if minutes < 60 {
            return String(localized: "\(minutes) 分钟")
        }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? String(localized: "\(hours) 小时") : String(localized: "\(hours) 小时 \(rest) 分钟")
    }

    /// 休息时长的名字：「20 秒」「5 分钟」
    nonisolated static func lengthTitle(_ seconds: Int) -> String {
        seconds < 60 ? String(localized: "\(seconds) 秒") : String(localized: "\(seconds / 60) 分钟")
    }

    /// 倒计时：「4:59」
    nonisolated static func countdown(_ seconds: TimeInterval) -> String {
        let whole = max(0, Int(seconds.rounded(.up)))
        return "\(whole / 60):" + String(format: "%02d", whole % 60)
    }

    /// 卡片上的一句话
    var statusText: String {
        guard isEnabled || schedule.isOnBreak else {
            return String(localized: "没开。打开以后，连续用电脑 \(Self.durationText(schedule.interval))会提醒你休息 \(Self.lengthTitle(breakSeconds))。")
        }
        if let remaining = schedule.breakRemaining(now: now) {
            return String(localized: "正在休息，还剩 \(Self.countdown(remaining))")
        }
        if schedule.isDue {
            return String(localized: "该休息了：已经连续用了 \(Self.durationText(schedule.worked(now: now)))")
        }
        if schedule.workStart == nil {
            return String(localized: "刚休息过，碰键盘鼠标时开始算")
        }
        let worked = Self.durationText(schedule.worked(now: now))
        if isQuiet {
            return String(localized: "已经连续用了 \(worked)。有 App 在放视频或者开会，先不提醒")
        }
        // 还剩几分钟往上取整：还剩 12 分 50 秒说「13 分钟后」
        let until = Self.durationText(max(60, ((schedule.untilReminder(now: now) ?? 0) / 60).rounded(.up) * 60))
        return String(localized: "已经连续用了 \(worked)，\(until)后提醒休息")
    }

    /// 提醒里的第二行
    var reminderDetail: String {
        String(localized: "已经连续用了 \(Self.durationText(schedule.worked(now: now)))，起来活动活动、看看远处")
    }

    /// 休息时做什么，每次换一句
    var tip: String {
        let tips = [String(localized: "看看 6 米外的地方，眨眨眼"), String(localized: "站起来走走，伸个懒腰"),
                    String(localized: "转转脖子，活动一下肩膀"), String(localized: "喝口水，闭上眼睛歇一会儿")]
        return tips[(max(breakCount, 1) - 1) % tips.count]
    }

    var breakRemainingText: String {
        Self.countdown(schedule.breakRemaining(now: now) ?? 0)
    }

    /// 休息倒计时走了多少（0…1），画进度圈用
    var breakProgress: Double {
        guard let remaining = schedule.breakRemaining(now: now), schedule.breakLength > 0 else { return 0 }
        return 1 - remaining / schedule.breakLength
    }

    // MARK: - 窗口

    private func show(_ phase: Phase) {
        self.phase = phase
        finishedTimer?.invalidate()
        finishedTimer = nil
        guard isLive else { return }
        let panel = self.panel ?? BreakReminderPanel(rootView: BreakReminderBanner(model: self))
        self.panel = panel
        panel.place()
        // Pop 自己录屏时按编号排除；别的录屏、截图尽量不录进去（新系统上别的 App 不一定管这个）
        panel.sharingType = .none
        panel.orderFrontRegardless()
        // 内容变了：等 SwiftUI 排好版再按新的大小放一次
        DispatchQueue.main.async {
            MainActor.assumeIsolated { panel.place() }
        }
        if phase == .finished {
            finishedTimer = Timer.scheduledTimer(withTimeInterval: Self.finishedSeconds, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.phase == .finished else { return }
                    self.hidePanel()
                }
            }
        }
    }

    private func hidePanel() {
        phase = .hidden
        finishedTimer?.invalidate()
        finishedTimer = nil
        panel?.orderOut(nil)
    }

    private func hideEverything() {
        hidePanel()
        hideOverlays()
    }

    /// 休息时盖住每一块屏幕，指针所在的屏幕上写着倒计时；Pop 到前台，Esc 就能提前结束
    private func showOverlays() {
        guard isLive else { return }
        hideOverlays()
        previousApp = NSWorkspace.shared.frontmostApplication
        NSApp.activate()
        let pointer = NSEvent.mouseLocation
        let main = NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) } ?? NSScreen.main
        for screen in NSScreen.screens {
            let showsCountdown = screen == main || main == nil
            let window = BreakOverlayWindow(screen: screen, rootView: BreakOverlayView(model: self, showsCountdown: showsCountdown)) { [weak self] in
                self?.endBreak()
            }
            window.sharingType = .none
            if showsCountdown {
                window.makeKeyAndOrderFront(nil)
            } else {
                window.orderFrontRegardless()
            }
            overlays.append(window)
        }
    }

    private func hideOverlays() {
        guard !overlays.isEmpty else { return }
        overlays.forEach { $0.orderOut(nil) }
        overlays.removeAll()
        if let previousApp, previousApp.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApp.activate()
        }
        previousApp = nil
    }

    // MARK: - 演示

    /// 演示用：开着，每 45 分钟提醒、休息 5 分钟，已经连续用了 32 分钟
    static func demo(phase: Phase = .hidden) -> BreakReminder {
        let suite = "PopBreakReminderDemo"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        defaults.set(true, forKey: enabledKey)
        let start = Date(timeIntervalSince1970: 1_790_820_000)
        var current = start
        let reminder = BreakReminder(defaults: defaults, clock: { current }, idle: { 0 }, quiet: { false }, isLive: false)
        reminder.tick()
        current = start.addingTimeInterval(phase == .reminder ? 47 * 60 : 32 * 60)
        reminder.tick()
        return reminder
    }

    /// 演示用：屏幕上方的提醒（不开定时器），返回它的位置
    func showBannerForDemo(on screen: NSScreen) -> CGRect {
        let panel = BreakReminderPanel(rootView: BreakReminderBanner(model: self))
        self.panel = panel
        panel.place(on: screen)
        panel.sharingType = .readOnly
        panel.orderFrontRegardless()
        return panel.frame
    }

    func hideBannerForDemo() {
        panel?.orderOut(nil)
        panel = nil
    }
}

/// 屏幕上方的提醒：在普通窗口上面，不抢焦点
final class BreakReminderPanel: NSPanel {
    private let hosting: NSHostingView<BreakReminderBanner>

    init(rootView: BreakReminderBanner) {
        hosting = NSHostingView(rootView: rootView)
        let size = hosting.fittingSize
        super.init(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .statusBar
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isFloatingPanel = true
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        contentView = hosting
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var canBecomeKey: Bool { false }

    /// 放在指针所在屏幕的上方正中，菜单栏下面
    func place(on screen: NSScreen? = nil) {
        let pointer = NSEvent.mouseLocation
        guard let screen = screen ?? NSScreen.screens.first(where: { NSMouseInRect(pointer, $0.frame, false) }) ?? NSScreen.main else { return }
        let size = hosting.fittingSize
        let visible = screen.visibleFrame
        setFrame(CGRect(x: visible.midX - size.width / 2, y: visible.maxY - size.height - 10, width: size.width, height: size.height), display: true)
    }
}

/// 休息时盖住一块屏幕的窗口；Esc 提前结束
private final class BreakOverlayWindow: NSWindow {
    private let onCancel: () -> Void

    init(screen: NSScreen, rootView: BreakOverlayView, onCancel: @escaping () -> Void) {
        self.onCancel = onCancel
        super.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        contentView = NSHostingView(rootView: rootView)
        setFrame(screen.frame, display: false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onCancel()
    }
}
