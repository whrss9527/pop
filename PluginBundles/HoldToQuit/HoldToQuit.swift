import AppKit
import Carbon.HIToolbox
import CoreGraphics
@testable import Pop

/// 长按 ⌘Q 退出：拦下 ⌘Q（QuitKeyTap），按住一会儿（或者连按两下）才把 ⌘Q 交给 App，误按一下不会关掉整个 App。
/// 屏幕中间显示要退出哪个 App 和进度；可以让有的 App 照旧一按就退出。设置都记住，Pop 启动时（插件包装载时）接着生效；
/// 要辅助功能权限（Pop 唤起圆盘本来就要）
@MainActor
final class HoldToQuit: ObservableObject {
    static let shared = HoldToQuit()

    static let enabledKey = "pop.holdToQuit.enabled"
    static let modeKey = "pop.holdToQuit.mode"
    static let durationKey = "pop.holdToQuit.duration"
    static let exceptionsKey = "pop.holdToQuit.exceptions"
    static let defaultsKeys = [enabledKey, modeKey, durationKey, exceptionsKey]
    /// 按住多久才退出；连按两下时是两下之间最多隔多久（秒）
    static let durations: [Double] = [0.5, 1, 1.5, 2]
    static let defaultDuration: Double = 1
    /// 访达的 ⌘Q 本来就不退出，照旧交给它
    static let finderID = "com.apple.finder"
    /// 自己就能设成按住 ⌘Q 才退出的 App（Chrome）：装了的话一开始就放在例外里，交给它自己管。
    /// 不然它收到补发的 ⌘Q 时只当是按了一下，永远退不掉
    static let selfGuardedIDs = ["com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.dev", "com.google.Chrome.canary", "org.chromium.Chromium"]
    /// 「正在退出」停多久
    static let quittingSeconds: TimeInterval = 0.8

    /// 前台的 App
    struct FrontApp: Equatable, Identifiable {
        var pid: pid_t
        var bundleID: String?
        var name: String
        var icon: NSImage?

        var id: String { bundleID ?? "\(pid)" }
    }

    /// 屏幕中间的提示
    struct Prompt: Equatable {
        var app: FrontApp
        var mode: QuitGuard.Mode
        /// 按住时按了多久，连按时第二下还剩多少时间（0…1）
        var progress: Double
        var isQuitting: Bool

        /// 还没显示过提示时用来算窗口大小
        static let placeholder = Prompt(app: FrontApp(pid: 0, bundleID: nil, name: ""), mode: .hold, progress: 0, isQuitting: false)
    }

    @Published private(set) var isEnabled: Bool
    @Published private(set) var mode: QuitGuard.Mode
    @Published private(set) var duration: Double
    /// 这些 App 里 ⌘Q 照旧一按就退出（bundle ID）
    @Published private(set) var exceptions: [String]
    /// 正在拦 ⌘Q
    @Published private(set) var isRunning = false
    /// 开着，但还没有辅助功能权限
    @Published private(set) var needsPermission = false
    /// 有权限，但系统暂时没让建 tap（刚给权限、刚醒来时可能这样）：过几秒再试
    @Published private(set) var tapFailed = false
    /// 屏幕中间的提示单独放：按住时一秒变六十次，卡片不用跟着重画
    let promptState = QuitPromptState()
    var prompt: Prompt? { promptState.prompt }

    private(set) var quitGuard: QuitGuard
    private let defaults: UserDefaults
    /// 测试、演示时不拦真的事件、不开窗口、不开定时器
    private let isLive: Bool
    private let isTrusted: () -> Bool
    private let isInstalled: (String) -> Bool
    private let clock: () -> Date
    /// 测试时代替真的发 ⌘Q
    var sendQuit: (@MainActor (pid_t) -> Void)?
    /// 现在在前台的 App（测试时用假的）。Pop 的卡片、圆盘有键盘焦点时（它们不激活 Pop，菜单栏还是别的 App 的），
    /// ⌘Q 其实是交给 Pop 的：算 Pop 自己，按住才退出 Pop，不会等够了以后退出 Pop、要退的 App 却还在
    var frontmostApp: @MainActor () -> FrontApp? = {
        if NSApp.keyWindow != nil {
            return FrontApp(pid: ProcessInfo.processInfo.processIdentifier, bundleID: Bundle.main.bundleIdentifier, name: "Pop")
        }
        return NSWorkspace.shared.frontmostApplication.map {
            FrontApp(pid: $0.processIdentifier, bundleID: $0.bundleIdentifier, name: $0.localizedName ?? $0.bundleIdentifier ?? "", icon: $0.icon)
        }
    }
    private lazy var keyTap = QuitKeyTap(model: self)
    /// 没有权限时每隔几秒看一次，给了就开始
    private var permissionTimer: Timer?
    /// 拦着的时候隔一会儿看看 tap 还管不管用（睡眠醒来、权限收回以后可能失效）
    private var healthTimer: Timer?
    private var wakeObserver: NSObjectProtocol?
    /// 等着的时候一秒六十次，画进度
    private var progressTimer: Timer?
    /// 正在等的那个 App
    private var waitingApp: FrontApp?
    /// 「正在退出」的提示，停一会儿再收起
    private var quittingPrompt: Prompt?
    private var quittingTask: Task<Void, Never>?
    /// 吞着的那个键（按 ⌘Q 时的 Q 键）
    private(set) var trackedKeyCode: Int64? {
        didSet { keyTap.trackedKeyCode = trackedKeyCode }
    }
    private var panel: QuitPromptPanel?
    private var panelUpdateScheduled = false

    init(defaults: UserDefaults = .standard, isLive: Bool = true, clock: @escaping () -> Date = Date.init,
         isTrusted: @escaping () -> Bool = { Permissions.isAccessibilityTrusted },
         isInstalled: @escaping (String) -> Bool = { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil }) {
        self.defaults = defaults
        self.isLive = isLive
        self.clock = clock
        self.isTrusted = isTrusted
        self.isInstalled = isInstalled
        let saved = Self.savedSettings(defaults, isInstalled: isInstalled)
        isEnabled = saved.enabled
        mode = saved.mode
        duration = saved.duration
        exceptions = saved.exceptions
        quitGuard = QuitGuard(mode: saved.mode, duration: saved.duration)
    }

    /// 存着的设置；没设过时开着、按住 1 秒，例外里是装了的 Chrome；存的值不在几档里时用默认的
    private static func savedSettings(_ defaults: UserDefaults, isInstalled: (String) -> Bool)
        -> (enabled: Bool, mode: QuitGuard.Mode, duration: Double, exceptions: [String]) {
        let mode = defaults.string(forKey: modeKey).flatMap(QuitGuard.Mode.init(rawValue:)) ?? .hold
        let duration = defaults.object(forKey: durationKey) as? Double ?? defaultDuration
        return (defaults.object(forKey: enabledKey) as? Bool ?? true, mode,
                durations.contains(duration) ? duration : defaultDuration,
                defaults.stringArray(forKey: exceptionsKey) ?? selfGuardedIDs.filter(isInstalled))
    }

    // MARK: - 设置

    func setEnabled(_ on: Bool) {
        isEnabled = on
        defaults.set(on, forKey: Self.enabledKey)
        update()
    }

    func setMode(_ mode: QuitGuard.Mode) {
        guard mode != self.mode else { return }
        self.mode = mode
        defaults.set(mode.rawValue, forKey: Self.modeKey)
        resetGuard()
    }

    func setDuration(_ seconds: Double) {
        guard Self.durations.contains(seconds) else { return }
        duration = seconds
        defaults.set(seconds, forKey: Self.durationKey)
        resetGuard()
    }

    func addException(_ bundleID: String) {
        guard !exceptions.contains(bundleID), !Self.alwaysPasses(bundleID) else { return }
        exceptions.append(bundleID)
        defaults.set(exceptions, forKey: Self.exceptionsKey)
    }

    func removeException(_ bundleID: String) {
        exceptions.removeAll { $0 == bundleID }
        defaults.set(exceptions, forKey: Self.exceptionsKey)
    }

    /// 访达：它的 ⌘Q 本来就不退出，不管有没有加都照旧交给它
    static func alwaysPasses(_ bundleID: String) -> Bool {
        bundleID == finderID
    }

    /// 这个 App 里 ⌘Q 照旧一按就退出。Pop 自己也拦：卡片有键盘焦点时误按一下 ⌘Q 不会把 Pop 关掉
    func passes(_ app: FrontApp) -> Bool {
        guard let id = app.bundleID else { return false }
        return Self.alwaysPasses(id) || exceptions.contains(id)
    }

    /// 插件包装载时：按存着的设置来（卸载时可能一起删掉了），开着的话开始拦
    func startIfNeeded() {
        let saved = Self.savedSettings(defaults, isInstalled: isInstalled)
        isEnabled = saved.enabled
        mode = saved.mode
        duration = saved.duration
        exceptions = saved.exceptions
        resetGuard()
        update()
    }

    /// 卸载插件包的时候
    func shutDown() {
        stopTap()
        permissionTimer?.invalidate()
        permissionTimer = nil
        needsPermission = false
        tapFailed = false
        resetGuard()
    }

    /// tap 失效了（睡眠醒来、权限收回）：重新建一个，没有权限了就说一声
    func recoverIfNeeded() {
        guard isEnabled, isLive, isRunning, !keyTap.isHealthy else { return }
        stopTap()
        update()
    }

    /// 换了方式、时长：正在等的不算了
    private func resetGuard() {
        quitGuard = QuitGuard(mode: mode, duration: duration)
        waitingApp = nil
        trackedKeyCode = nil
        quittingTask?.cancel()
        quittingPrompt = nil
        refresh()
    }

    /// 按现在的设置开、关拦截
    private func update() {
        guard isEnabled else {
            shutDown()
            return
        }
        guard isTrusted() else {
            stopTap()
            needsPermission = true
            tapFailed = false
            watchPermission()
            return
        }
        needsPermission = false
        permissionTimer?.invalidate()
        permissionTimer = nil
        startTap()
    }

    private func watchPermission() {
        guard isLive, permissionTimer == nil else { return }
        let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isTrusted() else { return }
                self.update()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        permissionTimer = timer
    }

    // MARK: - 按键

    /// 主线程上（QuitKeyTap 交过来的）：⌘Q 或者吞着的那个键按下、松开；返回 true 是吞掉
    func decide(isDown: Bool, keyCode: Int64, isRepeat: Bool, isQuitShortcut: Bool) -> Bool {
        if isDown, keyCode == trackedKeyCode {
            if isRepeat {
                return repeatKey()
            }
            // 没收到松开（比如中间开了安全输入）：当作已经松开了
            _ = releaseKey()
        }
        guard isDown else {
            return keyCode == trackedKeyCode ? releaseKey() : false
        }
        guard !isRepeat, isQuitShortcut, let app = frontmostApp() else { return false }
        // 先记下按的是哪个键：连按两下时第二下马上就要按这个键补发 ⌘Q
        trackedKeyCode = keyCode
        guard pressQuit(in: app) else {
            trackedKeyCode = nil
            return false
        }
        return true
    }

    /// 按下了 ⌘Q（不是自动重复的）；返回 true 是吞掉
    func pressQuit(in app: FrontApp) -> Bool {
        guard isEnabled, !passes(app) else { return false }
        quittingTask?.cancel()
        quittingPrompt = nil
        waitingApp = app
        if case .quit(let pid) = quitGuard.pressQuit(app: app.pid, now: clock()) {
            quit(pid)
        }
        refresh()
        return true
    }

    /// 吞着的那个键自动重复；返回 true 是吞掉
    func repeatKey() -> Bool {
        quitGuard.repeatKey() == .swallow
    }

    /// 吞着的那个键松开了；返回 true 是吞掉
    func releaseKey() -> Bool {
        trackedKeyCode = nil
        let action = quitGuard.releaseKey()
        refresh()
        return action == .swallow
    }

    func releaseCommand() {
        quitGuard.releaseCommand()
        refresh()
    }

    /// 定时看一次：按住够久了就退出
    func tick() {
        // ⌘ 其实已经松开了，只是没收到（tap 重建、被系统停过一下）：不退。远程桌面、自动化工具发来的 ⌘ 也算按着
        if isLive, mode == .hold, quitGuard.isWaiting, !CGEventSource.flagsState(.combinedSessionState).contains(.maskCommand) {
            releaseCommand()
            return
        }
        if let pid = quitGuard.check(now: clock()) {
            quit(pid)
        }
        refresh()
    }

    /// 把 ⌘Q 交给这个 App。等的时候前台换成了别的 App 就不退了，免得退错
    private func quit(_ pid: pid_t) {
        guard let app = waitingApp, app.pid == pid, frontmostApp()?.pid == pid else {
            quitGuard.cancel()
            return
        }
        quittingPrompt = Prompt(app: app, mode: mode, progress: 1, isQuitting: true)
        if let sendQuit {
            sendQuit(pid)
        } else if isLive {
            postQuitShortcut()
        }
        quittingTask?.cancel()
        quittingTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.quittingSeconds))
            guard !Task.isCancelled, let self else { return }
            self.quittingPrompt = nil
            self.refresh()
        }
    }

    /// 补发一次 ⌘Q（按下、松开），用按的那个键（换了键盘布局也对），带着记号，自己不再拦
    private func postQuitShortcut() {
        let keyCode = CGKeyCode(trackedKeyCode ?? Int64(kVK_ANSI_Q))
        let source = CGEventSource(stateID: .privateState)
        for isDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: isDown) else { continue }
            event.flags = .maskCommand
            event.setIntegerValueField(.eventSourceUserData, value: QuitKeyTap.marker)
            event.post(tap: .cgSessionEventTap)
        }
    }

    /// 按等着的情况更新提示、进度定时器
    private func refresh() {
        if let quittingPrompt {
            promptState.show(quittingPrompt)
        } else if let app = waitingApp, let progress = quitGuard.progress(now: clock()) {
            promptState.show(Prompt(app: app, mode: mode, progress: progress, isQuitting: false))
        } else {
            promptState.show(nil)
        }
        if !quitGuard.isWaiting && quittingPrompt == nil {
            waitingApp = nil
        }
        updateTimer()
        schedulePanelUpdate()
    }

    private func updateTimer() {
        guard isLive else { return }
        if quitGuard.isWaiting {
            guard progressTimer == nil else { return }
            let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            RunLoop.main.add(timer, forMode: .common)
            progressTimer = timer
        } else {
            progressTimer?.invalidate()
            progressTimer = nil
        }
    }

    /// 显示、收起提示窗口放到下一轮再做：decide 是拦截的线程等着主线程时调的，那时键盘输入都排在后面
    private func schedulePanelUpdate() {
        guard isLive, !panelUpdateScheduled else { return }
        panelUpdateScheduled = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.panelUpdateScheduled = false
                self.updatePanel()
            }
        }
    }

    private func updatePanel() {
        guard isLive else { return }
        guard prompt != nil else {
            panel?.orderOut(nil)
            return
        }
        let panel = self.panel ?? QuitPromptPanel(rootView: QuitPromptView(state: promptState))
        self.panel = panel
        if !panel.isVisible {
            panel.place()
            panel.orderFrontRegardless()
        }
    }

    // MARK: - 拦 ⌘Q

    private func startTap() {
        guard isLive else {
            isRunning = true
            return
        }
        guard keyTap.start() else {
            // 有权限，但系统暂时没让建：每隔几秒再试
            tapFailed = true
            watchPermission()
            return
        }
        tapFailed = false
        // 重新建的 tap（醒来以后）：正按着的那个键接着吞，松开时还能收到
        keyTap.trackedKeyCode = trackedKeyCode
        isRunning = true
        // 提示窗口先建好，第一次按 ⌘Q 时不用现建
        if panel == nil {
            panel = QuitPromptPanel(rootView: QuitPromptView(state: promptState))
        }
        if healthTimer == nil {
            let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.recoverIfNeeded() }
            }
            RunLoop.main.add(timer, forMode: .common)
            healthTimer = timer
        }
        if wakeObserver == nil {
            wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.recoverIfNeeded() }
            }
        }
    }

    private func stopTap() {
        keyTap.stop()
        healthTimer?.invalidate()
        healthTimer = nil
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        wakeObserver = nil
        isRunning = false
    }

    // MARK: - 卡片上的字

    /// 「1 秒」「0.5 秒」
    nonisolated static func durationTitle(_ seconds: Double) -> String {
        let text = seconds == seconds.rounded() ? String(Int(seconds)) : String(format: "%.1f", seconds)
        return String(localized: "\(text) 秒")
    }

    /// 「正在拦 ⌘Q：按住 1 秒才退出」「没开」
    var statusText: String {
        if needsPermission {
            return String(localized: "要先在「系统设置 → 隐私与安全性 → 辅助功能」里允许 Pop，才能拦下 ⌘Q")
        }
        guard isEnabled else {
            return String(localized: "没开：⌘Q 一按就退出")
        }
        if tapFailed {
            return String(localized: "系统暂时没让 Pop 拦下 ⌘Q，过几秒会再试一次")
        }
        let time = Self.durationTitle(duration)
        return mode == .hold
            ? String(localized: "正在拦 ⌘Q：按住 \(time)才退出")
            : String(localized: "正在拦 ⌘Q：\(time)内连按两下才退出")
    }

    /// 例外里的 App 叫什么、长什么样；没装了的只写 bundle ID
    func exceptionApp(_ bundleID: String) -> FrontApp {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return FrontApp(pid: 0, bundleID: bundleID, name: bundleID)
        }
        let name = FileManager.default.displayName(atPath: url.path)
        return FrontApp(pid: 0, bundleID: bundleID, name: name.hasSuffix(".app") ? String(name.dropLast(4)) : name,
                        icon: NSWorkspace.shared.icon(forFile: url.path))
    }

    /// 「添加 App」菜单里列的：正在运行的普通 App（访达、已经加上的除外），按名字排
    func runningApps() -> [FrontApp] {
        var seen: Set<String> = []
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> FrontApp? in
                guard let id = app.bundleIdentifier, !Self.alwaysPasses(id), !exceptions.contains(id), seen.insert(id).inserted else { return nil }
                return FrontApp(pid: app.processIdentifier, bundleID: id, name: app.localizedName ?? id, icon: app.icon)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    // MARK: - 演示

    /// 演示用：开着，按住 1 秒，「终端」照旧一按就退出；不拦真的事件
    static func demo() -> HoldToQuit {
        let suite = "PopHoldToQuitDemo"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        let model = HoldToQuit(defaults: defaults, isLive: false, isTrusted: { true }, isInstalled: { _ in false })
        model.addException("com.apple.Terminal")
        model.startIfNeeded()
        return model
    }

    /// 演示用：屏幕中间的提示，按到一多半；返回提示的位置
    func showPromptForDemo(app: FrontApp, progress: Double, on screen: NSScreen) -> CGRect {
        promptState.show(Prompt(app: app, mode: .hold, progress: progress, isQuitting: false))
        let panel = QuitPromptPanel(rootView: QuitPromptView(state: promptState))
        self.panel = panel
        panel.place(on: screen)
        panel.sharingType = .readOnly
        panel.orderFrontRegardless()
        return panel.frame
    }

    func hidePromptForDemo() {
        panel?.orderOut(nil)
        panel = nil
        promptState.show(nil)
    }
}

/// 屏幕中间的提示现在的样子
@MainActor
final class QuitPromptState: ObservableObject {
    @Published private(set) var prompt: HoldToQuit.Prompt?
    /// 上一次显示的：收起以后窗口里还画着它，窗口大小不变
    private(set) var lastShown: HoldToQuit.Prompt?

    func show(_ prompt: HoldToQuit.Prompt?) {
        guard prompt != self.prompt else { return }
        if let prompt {
            lastShown = prompt
        }
        self.prompt = prompt
    }
}
