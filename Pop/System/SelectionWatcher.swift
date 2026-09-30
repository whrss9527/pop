import AppKit

/// 全局监听左键（不拦截事件）：拖着选了一段文字、双击或三击选词之后回调，给「选中文字后显示工具条」用。
/// 只在鼠标抬起时判断一次，像是选了文字才去读选区；平时单击、拖文件都不会去读。
/// 按下鼠标、按键、滚动时通知工具条收起。
@MainActor
final class SelectionWatcher {
    /// 鼠标抬起的位置（AppKit 坐标）和点击次数
    var onSelection: (CGPoint, Int) -> Void = { _, _ in }
    /// 点了别处、按了键、滚动了
    var onInteraction: () -> Void = {}

    private var monitors: [Any] = []
    private var downLocation: CGPoint?
    private var dragChangeCount = 0

    var isRunning: Bool { !monitors.isEmpty }

    func start() {
        guard monitors.isEmpty else { return }
        add(.leftMouseDown) { [weak self] _ in
            self?.mouseDown()
        }
        add(.leftMouseUp) { [weak self] clickCount in
            self?.mouseUp(clickCount: clickCount)
        }
        add([.rightMouseDown, .otherMouseDown, .keyDown, .scrollWheel]) { [weak self] _ in
            self?.onInteraction()
        }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        downLocation = nil
    }

    private func add(_ mask: NSEvent.EventTypeMask, handler: @escaping @MainActor (Int) -> Void) {
        let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { event in
            // 只有鼠标事件有点击次数
            let clickCount = event.type == .leftMouseUp ? event.clickCount : 0
            MainActor.assumeIsolated {
                handler(clickCount)
            }
        }
        if let monitor {
            monitors.append(monitor)
        }
    }

    private func mouseDown() {
        downLocation = NSEvent.mouseLocation
        dragChangeCount = NSPasteboard(name: .drag).changeCount
        onInteraction()
    }

    private func mouseUp(clickCount: Int) {
        guard let down = downLocation else { return }
        downLocation = nil
        let up = NSEvent.mouseLocation
        // 拖放开始时拖放剪贴板会变：拖的是文件或者一段文字，不是在选
        let startedDragAndDrop = NSPasteboard(name: .drag).changeCount != dragChangeCount
        guard SelectionToolbarLogic.isSelectionGesture(from: down, to: up, clickCount: clickCount,
                                                       startedDragAndDrop: startedDragAndDrop) else { return }
        onSelection(up, clickCount)
    }
}
