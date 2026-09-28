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

    func read(pid: pid_t?) async -> SelectionContent {
        guard let pid, pid != ProcessInfo.processInfo.processIdentifier else { return .none }
        return await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.readSync(pid: pid))
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

        let app = AXUIElementCreateApplication(pid)
        if let copyItem = findCopyMenuItem(in: app) {
            // 「拷贝」是灰的：确定没有选中任何东西，也就不用碰剪贴板了。
            guard axBool(copyItem, kAXEnabledAttribute) != false else { return .none }
            return copyThroughPasteboard(muteAlerts: false) {
                AXUIElementPerformAction(copyItem, kAXPressAction as CFString) == .success
            }
        }

        // 找不到菜单栏，但辅助功能明确说没有选中文字，就信它，避免无谓的 ⌘C。
        if case .empty = axResult {
            return .none
        }

        return copyThroughPasteboard(muteAlerts: true) {
            waitForModifierRelease(timeout: 0.5)
            postCommandC()
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

    private func copyThroughPasteboard(muteAlerts: Bool, trigger: () -> Bool) -> SelectionContent {
        let pasteboard = NSPasteboard.general
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

        guard trigger() else { return .none }

        let deadline = Date().addingTimeInterval(copyTimeout)
        while pasteboard.changeCount == before, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        guard pasteboard.changeCount != before else { return .none }
        // 有的 App 先清空剪贴板再分几次写入，稍等一下再读。
        Thread.sleep(forTimeInterval: 0.02)
        let content = Self.readContent(from: pasteboard)
        snapshot.restore(to: pasteboard)
        return content
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

    // MARK: - 模拟按键

    /// 用户可能还按着 ⌥ 之类的修饰键（比如用 ⌥+右键唤起），先等松开，避免变成 ⌘⌥C。
    private func waitForModifierRelease(timeout: TimeInterval) {
        let modifiers: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
        let deadline = Date().addingTimeInterval(timeout)
        while !CGEventSource.flagsState(.combinedSessionState).intersection(modifiers).isEmpty, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
    }

    private func postCommandC() {
        let source = CGEventSource(stateID: .combinedSessionState)
        source?.setLocalEventsFilterDuringSuppressionState([.permitLocalMouseEvents, .permitSystemDefinedEvents],
                                                           state: .eventSuppressionStateSuppressionInterval)
        let keyCode = CGKeyCode(kVK_ANSI_C)
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cgSessionEventTap)
        up?.post(tap: .cgSessionEventTap)
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

    private static func current() -> Int? {
        guard let result = run("alert volume of (get volume settings)") else { return nil }
        return Int(result.int32Value)
    }

    private static func set(_ volume: Int) {
        _ = run("set volume alert volume \(volume)")
    }

    private static func run(_ source: String) -> NSAppleEventDescriptor? {
        var error: NSDictionary?
        let result: NSAppleEventDescriptor? = NSAppleScript(source: source)?.executeAndReturnError(&error)
        return error == nil ? result : nil
    }
}
