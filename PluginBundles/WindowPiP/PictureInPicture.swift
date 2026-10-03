import AppKit
import ApplicationServices
import ScreenCaptureKit
@testable import Pop

/// 窗口画中画：把一个窗口的画面实时放进屏幕角落的小窗，一直在别的窗口上面，切到别的 App、全屏的 App 里也看得到。
/// 拖动换位置，滚动换大小，双击回到原来的窗口，右键换大小、透明度、关闭；最多同时开 4 个
@MainActor
final class PictureInPicture {
    static let shared = PictureInPicture()
    static let maxCount = 4
    /// 小窗的长边（点），下次开的时候还是这么大
    static let sizeKey = "pop.windowPiP.size"
    static let defaultsKeys = [sizeKey]
    /// 右键菜单里的透明度
    static let opacities: [CGFloat] = [1, 0.75, 0.5]

    private(set) var panels: [PiPPanel] = []
    /// 正在开的（抓画面还没开始）：不重复开，也算进最多 4 个里
    private var opening: Set<CGWindowID> = []
    /// 每次全部关掉加一：开到一半时全部关掉了，开好了也不显示
    private var generation = 0

    var count: Int { panels.count }

    func isShowing(_ id: CGWindowID) -> Bool {
        panels.contains { $0.item.id == id }
    }

    /// 给 window 开一个小窗，放在 point 所在屏幕的右下角；开不了时返回原因
    func open(_ item: PiPWindows.Item, window: SCWindow, near point: CGPoint) async -> String? {
        if let existing = panels.first(where: { $0.item.id == item.id }) {
            existing.orderFrontRegardless()
            return nil
        }
        guard !opening.contains(item.id) else { return nil }
        guard panels.count + opening.count < Self.maxCount else {
            return String(localized: "最多同时开 \(Self.maxCount) 个小窗，先关掉一个")
        }
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }) ?? NSScreen.main else {
            return String(localized: "找不到显示器")
        }
        let longSide = PiPLayout.savedLongSide(UserDefaults.standard.double(forKey: Self.sizeKey))
        let size = PiPLayout.size(for: item.frame.size, longSide: longSide)
        let frame = PiPLayout.defaultFrame(size: size, in: screen.visibleFrame,
                                           occupied: panels.filter { $0.screen == screen }.map(\.frame))
        let panel = PiPPanel(item: item, frame: frame)
        let stream = PiPStream(layer: panel.pip.contentLayer)
        // 先接上：刚开始抓就停了也知道
        stream.onStop = { [weak self, weak panel] error in
            guard let self, let panel, self.panels.contains(where: { $0 === panel }) else { return }
            self.windowWentAway(panel, error: error)
        }
        let generation = self.generation
        opening.insert(item.id)
        defer { opening.remove(item.id) }
        do {
            try await stream.start(window: window, pixels: PiPLayout.captureSize(for: frame.size, scale: screen.backingScaleFactor))
        } catch {
            return String(localized: "抓不到这个窗口的画面：\(error.localizedDescription)")
        }
        // 开的时候全部关掉了（或者卸载了插件）：不要了
        guard generation == self.generation, !stream.hasStopped else {
            let stopped = stream.hasStopped
            await stream.stop()
            return stopped ? String(localized: "原来的窗口关掉了") : nil
        }
        panel.stream = stream
        attach(panel)
        panel.orderFrontRegardless()
        return nil
    }

    func close(_ panel: PiPPanel) {
        guard let index = panels.firstIndex(where: { $0 === panel }) else { return }
        panels.remove(at: index)
        panel.orderOut(nil)
        panel.resizeTask?.cancel()
        panel.resizeTask = nil
        if let stream = panel.stream {
            panel.stream = nil
            Task { await stream.stop() }
        }
    }

    func closeAll() {
        generation += 1
        for panel in panels {
            close(panel)
        }
    }

    /// 原来的窗口关掉了（或者 App 退出了、在菜单栏里停止了抓取画面）：小窗上说一声，两秒后收起
    private func windowWentAway(_ panel: PiPPanel, error: Error?) {
        let stoppedByUser = (error as? SCStreamError)?.code == .userStopped
        panel.pip.showEnded(stoppedByUser ? String(localized: "从菜单栏停止了抓取画面") : String(localized: "原来的窗口关掉了"))
        Task { @MainActor [weak self, weak panel] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, let panel else { return }
            self.close(panel)
        }
    }

    private func attach(_ panel: PiPPanel) {
        panel.pip.onDoubleClick = { [weak panel] in
            guard let panel else { return }
            PiPWindowRaiser.raise(panel.item)
        }
        panel.pip.onClose = { [weak self, weak panel] in
            guard let self, let panel else { return }
            self.close(panel)
        }
        panel.pip.onBack = { [weak panel] in
            guard let panel else { return }
            PiPWindowRaiser.raise(panel.item)
        }
        panel.pip.onScroll = { [weak self, weak panel] delta in
            guard let self, let panel else { return }
            self.resize(panel, to: PiPLayout.scrolled(max(panel.frame.width, panel.frame.height), by: delta), animated: false)
        }
        panel.pip.menuProvider = { [weak self, weak panel] in
            guard let self, let panel else { return NSMenu() }
            return self.menu(for: panel)
        }
        panels.append(panel)
    }

    private func resize(_ panel: PiPPanel, to longSide: CGFloat, animated: Bool) {
        let visible = (panel.screen ?? NSScreen.main)?.visibleFrame ?? panel.frame
        let frame = PiPLayout.resized(panel.frame, longSide: longSide, within: visible, aspect: panel.item.frame.size)
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Motion.seconds(0.2)
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
        UserDefaults.standard.set(Double(longSide), forKey: Self.sizeKey)
        // 抓的画面跟着变大变小（停下滚动以后再换，不用每一步都换）
        panel.resizeTask?.cancel()
        panel.resizeTask = Task { @MainActor [weak panel] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let panel, let stream = panel.stream else { return }
            await stream.resize(pixels: PiPLayout.captureSize(for: frame.size, scale: panel.backingScaleFactor))
        }
    }

    /// 右键菜单：大小、透明度、回到窗口、关闭
    private func menu(for panel: PiPPanel) -> NSMenu {
        let menu = NSMenu()
        let current = max(panel.frame.width, panel.frame.height)
        for (size, title) in zip(PiPLayout.presets, [String(localized: "小"), String(localized: "中"), String(localized: "大")]) {
            let item = PiPMenuAction.item(title) { [weak self, weak panel] in
                guard let self, let panel else { return }
                self.resize(panel, to: size, animated: true)
            }
            item.state = abs(current - size) < 1 ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let titles = [String(localized: "不透明"), String(localized: "透明一点"), String(localized: "半透明")]
        for (opacity, title) in zip(Self.opacities, titles) {
            let item = PiPMenuAction.item(title) { [weak panel] in
                panel?.alphaValue = opacity
            }
            item.state = abs(panel.alphaValue - opacity) < 0.01 ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(PiPMenuAction.item(String(localized: "回到窗口")) { [weak panel] in
            guard let panel else { return }
            PiPWindowRaiser.raise(panel.item)
        })
        menu.addItem(PiPMenuAction.item(String(localized: "关闭小窗")) { [weak self, weak panel] in
            guard let self, let panel else { return }
            self.close(panel)
        })
        if panels.count > 1 {
            menu.addItem(PiPMenuAction.item(String(localized: "关闭全部小窗")) { [weak self] in
                self?.closeAll()
            })
        }
        return menu
    }

    // MARK: - 演示

    /// 演示用：不抓真的窗口，拿一张图当作画面，放在屏幕右下角；返回小窗的位置
    func showForDemo(image: CGImage, title: String, on screen: NSScreen) -> CGRect {
        closeAll()
        let item = PiPWindows.Item(id: 0, pid: 0, appName: title, title: "", frame: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let size = PiPLayout.size(for: item.frame.size, longSide: PiPLayout.defaultLongSide)
        let panel = PiPPanel(item: item, frame: PiPLayout.defaultFrame(size: size, in: screen.visibleFrame, occupied: []))
        panel.pip.contentLayer.contents = image
        panel.pip.showsControls = true
        panel.sharingType = .readOnly
        attach(panel)
        panel.orderFrontRegardless()
        return panel.frame
    }
}

/// 回到原来的窗口：把那个 App 叫到前台，用辅助功能接口把这个窗口提到最前（最小化了就先还原）。
/// 辅助功能调用是跨进程的同步调用，那个 App 卡住或者窗口很多时要等一阵，放在后台做，Pop 不跟着卡
enum PiPWindowRaiser {
    @MainActor static func raise(_ item: PiPWindows.Item) {
        guard let app = NSRunningApplication(processIdentifier: item.pid) else { return }
        app.activate()
        DispatchQueue.global(qos: .userInitiated).async {
            raiseWindow(item)
        }
    }

    /// 后台线程上
    private static func raiseWindow(_ item: PiPWindows.Item) {
        let element = AXUIElementCreateApplication(item.pid)
        // Pop 不在前台时 activate 不一定能把那个 App 叫到前面：用辅助功能接口再说一次
        AXUIElementSetAttributeValue(element, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return }
        // 先按位置和大小找（同一个 App 可能有几个同名的窗口，比如几个终端），找不到再按标题
        let byFrame = windows.first { frame(of: $0).map { sameFrame($0, item.frame) } ?? false }
        let titled = item.title.isEmpty ? nil : windows.first { title(of: $0) == item.title }
        guard let window = byFrame ?? titled else { return }
        AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    }

    private static func title(of window: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    /// 辅助功能接口的坐标和 ScreenCaptureKit 一样：主屏幕左上角为原点
    private static func frame(of window: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(), CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: position, size: size)
    }

    private static func sameFrame(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 4 && abs(a.minY - b.minY) < 4 && abs(a.width - b.width) < 4 && abs(a.height - b.height) < 4
    }
}

/// NSMenuItem 的动作写成闭包
@MainActor
final class PiPMenuAction: NSObject {
    private let action: () -> Void

    private init(_ action: @escaping () -> Void) {
        self.action = action
    }

    @objc private func run() {
        action()
    }

    static func item(_ title: String, action: @escaping () -> Void) -> NSMenuItem {
        let target = PiPMenuAction(action)
        let item = NSMenuItem(title: title, action: #selector(run), keyEquivalent: "")
        item.target = target
        // 菜单项只弱引用 target，挂在 representedObject 上让它活着
        item.representedObject = target
        return item
    }
}
