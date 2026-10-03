import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// 读取前台 App 里选中的内容，按以下顺序兜底：
/// 1. 辅助功能接口直接读选中文字：原生 App 又快又准，不碰剪贴板；
/// 2. 通过辅助功能找到菜单栏里 ⌘C 对应的「拷贝」菜单项并点它：菜单项是灰的就说明什么都没选中；
/// 3. 前两者都走不通时模拟按 ⌘C（临时静音系统提示音）。
/// 2、3 会先备份剪贴板，读完立刻还原。
///
/// 所有辅助功能调用都是跨进程同步调用，放在后台队列里执行，不阻塞主线程（也就不会拖慢事件拦截）。
final class SelectionReader: @unchecked Sendable {
    private let queue = DispatchQueue(label: "io.github.whrss9527.pop.selection", qos: .userInitiated)
    /// 触发拷贝后等待剪贴板变化的最长时间
    private let copyTimeout: TimeInterval

    init(copyTimeout: TimeInterval = 0.25) {
        self.copyTimeout = copyTimeout
        // 目标 App 卡住时，辅助功能调用最多等 0.25 秒（默认是 6 秒）。
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.25)
    }

    /// 演示模式（CI 截图）不去读别的 App：不碰剪贴板，也不会弹出授权提示
    private static let skipsReading = ProcessInfo.processInfo.environment["POP_DEMO"] == "1"

    func read(pid: pid_t?) async -> SelectionContent {
        guard !Self.skipsReading, let pid, pid != ProcessInfo.processInfo.processIdentifier else { return .none }
        return await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.readSync(pid: pid))
            }
        }
    }

    /// 只用辅助功能读选中的文字和它在屏幕上的位置（Quartz 坐标），不碰剪贴板；读不到时返回 nil。
    /// 选中文字后的工具条用它：每次选完都读，不能去动剪贴板
    func readAccessible(pid: pid_t?) async -> (text: String, bounds: CGRect?)? {
        guard !Self.skipsReading, let pid, pid != ProcessInfo.processInfo.processIdentifier else { return nil }
        return await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.accessibleSelectionWithBounds())
            }
        }
    }

    // MARK: - 读取流程

    private enum AXSelection {
        case text(String)
        case empty
        case unavailable
    }

    private func readSync(pid: pid_t) -> SelectionContent {
        let axResult = accessibilitySelection()
        if case .text(let text) = axResult {
            return .text(text)
        }
        let copyItem = findCopyMenuItem(in: AXUIElementCreateApplication(pid))
        // 找不到菜单栏，但辅助功能明确说没有选中文字，就信它，避免无谓的 ⌘C。
        if copyItem == nil, case .empty = axResult {
            return .none
        }
        return copySelection(copyItem: copyItem) { pasteboard -> SelectionContent? in Self.readContent(from: pasteboard) } ?? .none
    }

    /// 带格式地重新拷贝一次选中的内容（HTML、RTF），给「转成 Markdown」用。
    /// 辅助功能只能读到纯文字，所以这里直接点「拷贝」或者模拟 ⌘C。
    func readRich(pid: pid_t?) async -> RichSelection? {
        guard !Self.skipsReading, let pid, pid != ProcessInfo.processInfo.processIdentifier else { return nil }
        return await withCheckedContinuation { continuation in
            queue.async {
                let copyItem = self.findCopyMenuItem(in: AXUIElementCreateApplication(pid))
                continuation.resume(returning: self.copySelection(copyItem: copyItem, read: Self.richContent(from:)))
            }
        }
    }

    /// 点菜单栏里的「拷贝」，找不到菜单栏时模拟 ⌘C，读完剪贴板再还原
    private func copySelection<T>(copyItem: AXUIElement?, read: (NSPasteboard) -> T?) -> T? {
        if let copyItem {
            // 「拷贝」是灰的：确定没有选中任何东西，也就不用碰剪贴板了。
            guard axBool(copyItem, kAXEnabledAttribute) != false else { return nil }
            return copyThroughPasteboard(muteAlerts: false, read: read) {
                AXUIElementPerformAction(copyItem, kAXPressAction as CFString) == .success
            }
        }
        return copyThroughPasteboard(muteAlerts: true, read: read) {
            KeySimulator.waitForModifierRelease(timeout: 0.5)
            KeySimulator.pressCommand(kVK_ANSI_C)
            return true
        }
    }

    private func accessibilitySelection() -> AXSelection {
        let system = AXUIElementCreateSystemWide()
        guard let focused = axElement(system, kAXFocusedUIElementAttribute),
              let text = axValue(focused, kAXSelectedTextAttribute) as? String else {
            return .unavailable
        }
        return text.isEmpty ? .empty : .text(text)
    }

    private func accessibleSelectionWithBounds() -> (text: String, bounds: CGRect?)? {
        let system = AXUIElementCreateSystemWide()
        guard let focused = axElement(system, kAXFocusedUIElementAttribute),
              let text = axValue(focused, kAXSelectedTextAttribute) as? String,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        // 选区在屏幕上的位置：有的 App 给不出来，这时工具条对着鼠标
        guard let range = axValue(focused, kAXSelectedTextRangeAttribute) else { return (text, nil) }
        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(focused, kAXBoundsForRangeParameterizedAttribute as CFString, range,
                                                         &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return (text, nil) }
        var rect = CGRect.zero
        guard AXValueGetValue(value as! AXValue, .cgRect, &rect), rect.width > 0 || rect.height > 0 else { return (text, nil) }
        return (text, rect)
    }

    /// 在菜单栏里找快捷键是 ⌘C 的菜单项（不依赖菜单标题，所以不受系统语言影响）。
    private func findCopyMenuItem(in app: AXUIElement) -> AXUIElement? {
        guard let menuBar = axElement(app, kAXMenuBarAttribute) else { return nil }
        // 第 0 个是苹果菜单，跳过
        for topItem in axElements(menuBar, kAXChildrenAttribute).dropFirst() {
            guard let menu = axElements(topItem, kAXChildrenAttribute).first else { continue }
            for item in axElements(menu, kAXChildrenAttribute) {
                guard let key = axString(item, kAXMenuItemCmdCharAttribute), key.uppercased() == "C" else { continue }
                // 0 表示只有 ⌘，没有其他修饰键
                if (axInt(item, kAXMenuItemCmdModifiersAttribute) ?? 0) == 0 {
                    return item
                }
            }
        }
        return nil
    }

    private func copyThroughPasteboard<T>(muteAlerts: Bool, read: (NSPasteboard) -> T?, trigger: () -> Bool) -> T? {
        let pasteboard = NSPasteboard.general
        // 读取期间剪贴板历史不要记录（包括读完还原的那一次变化）
        PasteboardGuard.shared.begin()
        defer { PasteboardGuard.shared.end(changeCount: pasteboard.changeCount) }
        let snapshot = PasteboardSnapshot(pasteboard)
        let before = pasteboard.changeCount

        let mutedVolume: Int? = muteAlerts ? DispatchQueue.main.sync { MainActor.assumeIsolated { AlertVolume.mute() } } : nil
        defer {
            if let mutedVolume {
                // 稍等一下再恢复，确保可能出现的提示音已经被静音吞掉。
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    MainActor.assumeIsolated { AlertVolume.restore(mutedVolume) }
                }
            }
        }

        guard trigger() else { return nil }

        let deadline = Date().addingTimeInterval(copyTimeout)
        while pasteboard.changeCount == before, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        guard pasteboard.changeCount != before else { return nil }
        // 有的 App 先清空剪贴板再分几次写入，稍等一下再读。
        Thread.sleep(forTimeInterval: 0.02)
        let content = read(pasteboard)
        snapshot.restore(to: pasteboard)
        return content
    }

    static func richContent(from pasteboard: NSPasteboard) -> RichSelection? {
        let selection = RichSelection(html: pasteboard.string(forType: .html),
                                      rtf: pasteboard.data(forType: .rtf),
                                      rtfd: pasteboard.data(forType: .rtfd),
                                      text: pasteboard.string(forType: .string))
        return selection.isEmpty ? nil : selection
    }

    static func readContent(from pasteboard: NSPasteboard) -> SelectionContent {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            return .files(urls)
        }
        if let string = pasteboard.string(forType: .string),
           !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .text(string)
        }
        if let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff) {
            return .image(data)
        }
        return .none
    }

    // MARK: - 辅助功能小工具

    private func axValue(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    private func axElement(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = axValue(element, attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private func axElements(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
        (axValue(element, attribute) as? [AXUIElement]) ?? []
    }

    private func axString(_ element: AXUIElement, _ attribute: String) -> String? {
        axValue(element, attribute) as? String
    }

    private func axInt(_ element: AXUIElement, _ attribute: String) -> Int? {
        (axValue(element, attribute) as? NSNumber)?.intValue
    }

    private func axBool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        (axValue(element, attribute) as? NSNumber)?.boolValue
    }
}

/// 剪贴板快照：保存所有条目的所有类型，读完选中内容后原样还原。
struct PasteboardSnapshot {
    private let items: [[(type: NSPasteboard.PasteboardType, data: Data)]]

    /// 剪贴板历史类工具约定忽略带这个类型的内容，避免还原时多出一条重复历史。
    static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    init(_ pasteboard: NSPasteboard) {
        items = (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in
                item.data(forType: type).map { (type: type, data: $0) }
            }
        }
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        let restored: [NSPasteboardItem] = items.enumerated().map { index, pairs in
            let item = NSPasteboardItem()
            for pair in pairs {
                item.setData(pair.data, forType: pair.type)
            }
            if index == 0 {
                item.setData(Data(), forType: Self.transientType)
            }
            return item
        }
        pasteboard.writeObjects(restored)
    }
}

/// 模拟 ⌘C 时，如果目标 App 里没有选中内容会「咚」一声，所以临时把提示音量调成 0。
/// 调整前先记下原值，万一中途退出，下次启动时也能恢复。
@MainActor
enum AlertVolume {
    private static let pendingRestoreKey = "pop.pendingAlertVolumeRestore"

    static func mute() -> Int? {
        guard let volume = current(), volume > 0 else { return nil }
        UserDefaults.standard.set(volume, forKey: pendingRestoreKey)
        set(0)
        return volume
    }

    static func restore(_ volume: Int) {
        set(volume)
        UserDefaults.standard.removeObject(forKey: pendingRestoreKey)
    }

    static func restorePendingIfNeeded() {
        if let volume = UserDefaults.standard.object(forKey: pendingRestoreKey) as? Int {
            restore(volume)
        }
    }

    /// 启动以后闲着的时候先把要用的脚本编好：第一次编要装载 AppleScript，主线程上要等好一会儿，
    /// 放到第一次在读不出选中内容的 App 里唤起时，圆盘出来的时候会顿一下
    static func prepare() {
        _ = script(currentSource)
        _ = script(setSource(0))
    }

    private static let currentSource = "alert volume of (get volume settings)"

    private static func setSource(_ volume: Int) -> String {
        "set volume alert volume \(volume)"
    }

    private static func current() -> Int? {
        guard let result = run(currentSource) else { return nil }
        return Int(result.int32Value)
    }

    private static func set(_ volume: Int) {
        _ = run(setSource(volume))
    }

    /// 编好的脚本，编一次留着
    private static var compiled: [String: NSAppleScript] = [:]

    private static func script(_ source: String) -> NSAppleScript? {
        if let script = compiled[source] {
            return script
        }
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source), script.compileAndReturnError(&error) else { return nil }
        compiled[source] = script
        return script
    }

    private static func run(_ source: String) -> NSAppleEventDescriptor? {
        var error: NSDictionary?
        let result = script(source)?.executeAndReturnError(&error)
        return error == nil ? result : nil
    }
}
