import AppKit
import Carbon.HIToolbox

/// Pop 自己读写剪贴板的时候（读取选中内容、替换原文后还原），让剪贴板历史不要记录这些变化。
final class PasteboardGuard: @unchecked Sendable {
    static let shared = PasteboardGuard()

    enum Verdict: Equatable {
        /// Pop 正在读写，稍后再看
        case busy
        /// Pop 自己造成的变化
        case ignore
        case record
    }

    private let lock = NSLock()
    private var depth = 0
    private var ignoredThrough = -1

    func begin() {
        lock.lock()
        depth += 1
        lock.unlock()
    }

    /// 结束一次读写：changeCount 以及之前的变化都不记录。
    func end(changeCount: Int) {
        lock.lock()
        depth = max(depth - 1, 0)
        ignoredThrough = max(ignoredThrough, changeCount)
        lock.unlock()
    }

    func verdict(for changeCount: Int) -> Verdict {
        lock.lock()
        defer { lock.unlock() }
        if depth > 0 { return .busy }
        return changeCount <= ignoredThrough ? .ignore : .record
    }
}

/// 写剪贴板的小工具。
@MainActor
enum PasteboardWriter {
    static func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    static func copy(png: Data) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(png, forType: .png)
        // 有些 App 只认 TIFF
        if let tiff = NSImage(data: png)?.tiffRepresentation {
            pasteboard.setData(tiff, forType: .tiff)
        }
    }

    static func copy(files: [URL]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(files as [NSURL])
    }
}

/// 模拟按键。
enum KeySimulator {
    /// 用户可能还按着修饰键（比如用 ⌥+右键唤起），先等松开，避免 ⌘C 变成 ⌘⌥C。
    static func waitForModifierRelease(ignoring ignored: CGEventFlags = [], timeout: TimeInterval) {
        let watched = CGEventFlags([.maskCommand, .maskAlternate, .maskControl, .maskShift]).subtracting(ignored)
        let deadline = Date().addingTimeInterval(timeout)
        while !CGEventSource.flagsState(.combinedSessionState).intersection(watched).isEmpty, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
    }

    /// 按一下 ⌘ + 某个键（kVK_ANSI_C、kVK_ANSI_V 等）。
    static func pressCommand(_ keyCode: Int) {
        let source = CGEventSource(stateID: .combinedSessionState)
        source?.setLocalEventsFilterDuringSuppressionState([.permitLocalMouseEvents, .permitSystemDefinedEvents],
                                                           state: .eventSuppressionStateSuppressionInterval)
        let code = CGKeyCode(keyCode)
        let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cgSessionEventTap)
        up?.post(tap: .cgSessionEventTap)
    }
}

/// 把内容粘贴到当前的前台 App（写剪贴板 + 模拟 ⌘V）。调用前要先收起 Pop 的浮窗，让键盘焦点回到原来的 App。
@MainActor
enum Paster {
    /// 用一段文字替换原来 App 里选中的内容。粘贴完把剪贴板恢复原样，不影响用户自己复制的东西。
    static func replaceSelection(with text: String) {
        paste(restoringPrevious: true) { pasteboard in
            pasteboard.setString(text, forType: .string)
        }
    }

    /// 写入剪贴板并粘贴。restoringPrevious 为 false 时，粘贴的内容会留在剪贴板里（剪贴板历史就是这样用的）。
    static func paste(restoringPrevious: Bool, write: (NSPasteboard) -> Void) {
        let pasteboard = NSPasteboard.general
        let snapshot = restoringPrevious ? PasteboardSnapshot(pasteboard) : nil
        if restoringPrevious {
            PasteboardGuard.shared.begin()
        }
        pasteboard.clearContents()
        write(pasteboard)
        if restoringPrevious {
            // 标记成临时内容，其他剪贴板工具也不会记录
            pasteboard.setData(Data(), forType: PasteboardSnapshot.transientType)
        }
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.05) {
            KeySimulator.waitForModifierRelease(ignoring: .maskCommand, timeout: 0.5)
            KeySimulator.pressCommand(kVK_ANSI_V)
            guard let snapshot else { return }
            // 目标 App 收到 ⌘V 后才去读剪贴板，等一会儿再还原
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                MainActor.assumeIsolated {
                    let general = NSPasteboard.general
                    snapshot.restore(to: general)
                    PasteboardGuard.shared.end(changeCount: general.changeCount)
                }
            }
        }
    }
}
