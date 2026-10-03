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
        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        // 有些 App 只认 TIFF：别的 App 来要的时候才转。长截图转成不压缩的 TIFF 有几百 MB，复制时就转要卡好一会儿
        let provider = TIFFProvider(png: png)
        if item.setDataProvider(provider, forTypes: [.tiff]) {
            TIFFProvider.current = provider
        }
        pasteboard.writeObjects([item])
    }

    static func copy(files: [URL]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(files as [NSURL])
    }
}

/// 别的 App 来要 TIFF 时才从 PNG 转（PasteboardWriter.copy(png:)）
final class TIFFProvider: NSObject, NSPasteboardItemDataProvider {
    /// 剪贴板上现在这张图的：剪贴板不替我们留着，换了内容（pasteboardFinishedWithDataProvider）再放掉
    @MainActor static var current: TIFFProvider?

    private let png: Data

    init(png: Data) {
        self.png = png
    }

    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
        guard type == .tiff, let tiff = NSImage(data: png)?.tiffRepresentation else { return }
        item.setData(tiff, forType: .tiff)
    }

    func pasteboardFinishedWithDataProvider(_ pasteboard: NSPasteboard) {
        DispatchQueue.main.async { [self] in
            MainActor.assumeIsolated {
                if Self.current === self {
                    Self.current = nil
                }
            }
        }
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
    /// 替换原文的几步按顺序在这里做：连着替换两次时，第二次等第一次把剪贴板还原以后再存剪贴板
    private nonisolated static let queue = DispatchQueue(label: "Pop.Paster", qos: .userInitiated)

    /// 用一段文字替换原来 App 里选中的内容。粘贴完把剪贴板恢复原样，不影响用户自己复制的东西。
    static func replaceSelection(with text: String) {
        PasteboardGuard.shared.begin()
        queue.async {
            let pasteboard = NSPasteboard.general
            // 存下剪贴板原来的内容。别的 App 延后提供的内容（表格、大图）要等它给，所以不在主线程上存
            let snapshot = PasteboardSnapshot(pasteboard)
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            // 标记成临时内容，其他剪贴板工具也不会记录
            pasteboard.setData(Data(), forType: PasteboardSnapshot.transientType)
            Self.pressPaste()
            // 目标 App 收到 ⌘V 后才去读剪贴板，等一会儿再还原
            Thread.sleep(forTimeInterval: 0.5)
            snapshot.restore(to: pasteboard)
            PasteboardGuard.shared.end(changeCount: pasteboard.changeCount)
        }
    }

    /// 写入剪贴板并粘贴，粘贴的内容留在剪贴板里（剪贴板历史就是这样用的）。
    static func paste(write: (NSPasteboard) -> Void) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        write(pasteboard)
        DispatchQueue.global(qos: .userInitiated).async {
            Self.pressPaste()
        }
    }

    /// 稍等浮窗收起、键盘焦点回到原来的 App，再按 ⌘V
    private nonisolated static func pressPaste() {
        Thread.sleep(forTimeInterval: 0.05)
        KeySimulator.waitForModifierRelease(ignoring: .maskCommand, timeout: 0.5)
        KeySimulator.pressCommand(kVK_ANSI_V)
    }
}
