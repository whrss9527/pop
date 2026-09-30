import AppKit
import SwiftUI

/// 暂存架：临时放几个文件，之后一起（或者一个个）拖到别的地方。
/// 可以从圆盘把选中的文件放上来，也可以直接把文件拖到架子上；拖着文件左右晃几下，架子会出现在指针旁边。
@MainActor
final class FileShelf: ObservableObject {
    static let shared = FileShelf()

    @Published private(set) var files: [URL] = []
    private var panel: ShelfPanel?

    var isVisible: Bool { panel?.isVisible ?? false }

    func add(_ urls: [URL]) {
        for url in urls where url.isFileURL {
            let file = url.standardizedFileURL
            if !files.contains(file) {
                files.append(file)
            }
        }
    }

    func remove(_ url: URL) {
        files.removeAll { $0 == url }
    }

    func clear() {
        files.removeAll()
    }

    /// 拖走后被移动、删掉的文件从架子上拿掉
    func pruneMissing() {
        files.removeAll { !FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) }
    }

    /// 在 point（AppKit 屏幕坐标）旁边显示；已经显示着就留在原地
    func show(near point: CGPoint) {
        pruneMissing()
        if let panel, panel.isVisible {
            panel.orderFrontRegardless()
            return
        }
        let panel = self.panel ?? ShelfPanel(shelf: self)
        self.panel = panel
        panel.present(near: point)
    }

    func hide() {
        panel?.dismiss()
    }
}

// MARK: - 窗口

final class ShelfPanel: NSPanel {
    init(shelf: FileShelf) {
        super.init(contentRect: CGRect(x: 0, y: 0, width: 280, height: 160), styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovableByWindowBackground = true
        animationBehavior = .none
        // 内容变多变少时窗口跟着变大变小
        contentView = NSHostingView(rootView: ShelfView(shelf: shelf, onClose: { [weak self] in self?.dismiss() }))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // 无边框窗口默认拿不到焦点，按钮就不好点；非激活面板拿到焦点也不会把 Pop 切到前台
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// 放在 point 右下方一点，超出屏幕时往里收
    func present(near point: CGPoint) {
        contentView?.layoutSubtreeIfNeeded()
        if let fitting = contentView?.fittingSize, fitting.width > 0, fitting.height > 0 {
            setContentSize(fitting)
        }
        let size = frame.size
        let bounds = OverlayController.visibleFrame(containing: point)
        let x = min(max(point.x + 16, bounds.minX + 8), bounds.maxX - size.width - 8)
        let y = min(max(point.y - size.height + 24, bounds.minY + 8), bounds.maxY - size.height - 8)
        setFrameOrigin(CGPoint(x: x, y: y))
        alphaValue = 0
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Motion.seconds(0.18)
            self.animator().alphaValue = 1
        }
    }

    func dismiss() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Motion.seconds(0.12)
            self.animator().alphaValue = 0
        } completionHandler: {
            MainActor.assumeIsolated {
                self.orderOut(nil)
            }
        }
    }
}

// MARK: - 界面

struct ShelfView: View {
    @ObservedObject var shelf: FileShelf
    let onClose: () -> Void
    @State private var targeted = false

    static let width: CGFloat = 250

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("暂存架")
                    .font(.headline)
                if !shelf.files.isEmpty {
                    Text("\(shelf.files.count) 个文件")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if !shelf.files.isEmpty {
                    Button {
                        shelf.clear()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("清空暂存架（不会删除文件）")
                }
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("收起（文件还留在架子上）")
            }
            if shelf.files.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "tray.and.arrow.down")
                        .font(.system(size: 26))
                    Text("把文件拖到这里")
                        .font(.callout)
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 96)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4])))
            } else {
                ShelfDragAll(files: shelf.files)
                let rows = VStack(spacing: 2) {
                    ForEach(shelf.files, id: \.self) { url in
                        ShelfRow(url: url) { shelf.remove(url) }
                    }
                }
                if shelf.files.count > 6 {
                    ScrollView {
                        rows
                    }
                    .frame(height: 6 * ShelfRow.height + 10)
                } else {
                    rows
                }
            }
        }
        .padding(12)
        .frame(width: Self.width)
        .glassSurface(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(Color.accentColor.opacity(targeted ? 0.9 : 0), lineWidth: 2))
        .animation(Motion.content, value: targeted)
        .animation(Motion.content, value: shelf.files)
        .padding(CardContainer<EmptyView>.shadowPadding)
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter(\.isFileURL)
            shelf.add(files)
            return !files.isEmpty
        } isTargeted: {
            targeted = $0
        }
    }
}

/// 最上面的一叠图标：按住拖走全部文件
private struct ShelfDragAll: View {
    let files: [URL]

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                ForEach(Array(files.prefix(3).enumerated().reversed()), id: \.offset) { index, url in
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false)))
                        .resizable()
                        .frame(width: 38, height: 38)
                        .rotationEffect(.degrees(Double(index) * 7 - 7))
                        .offset(x: CGFloat(index) * 5)
                }
            }
            .frame(width: 56, height: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text(files.count == 1 ? String(localized: "拖走这个文件") : String(localized: "拖走全部 \(files.count) 个文件"))
                    .font(.callout)
                Text("拖到访达、邮件或者聊天窗口里")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.06)))
        .overlay(FileDragSource(files: files))
        .help("按住拖到别的地方")
    }
}

private struct ShelfRow: View {
    static let height: CGFloat = 28

    let url: URL
    let onRemove: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 8) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false)))
                    .resizable()
                    .frame(width: 20, height: 20)
                Text(url.lastPathComponent)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .overlay(FileDragSource(files: [url]))
            if hovering {
                Button(action: onRemove) {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("从架子上拿掉")
            }
        }
        .padding(.horizontal, 6)
        .frame(height: Self.height)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(hovering ? 0.08 : 0)))
        .onHover { hovering = $0 }
    }
}

// MARK: - 拖出去

/// 盖在图标上面的一层透明 AppKit 视图：按住拖动时把 files 作为文件拖出去，双击用默认 App 打开
struct FileDragSource: NSViewRepresentable {
    let files: [URL]

    func makeNSView(context: Context) -> FileDragSourceView {
        FileDragSourceView()
    }

    func updateNSView(_ view: FileDragSourceView, context: Context) {
        view.files = files
    }
}

final class FileDragSourceView: NSView, NSDraggingSource {
    var files: [URL] = []
    private var mouseDownEvent: NSEvent?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
        if event.clickCount == 2 {
            mouseDownEvent = nil
            files.forEach { NSWorkspace.shared.open($0) }
        }
    }

    override func mouseUp(with event: NSEvent) {
        mouseDownEvent = nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard let down = mouseDownEvent, !files.isEmpty else { return }
        let start = down.locationInWindow
        let now = event.locationInWindow
        // 拖出一小段距离才开始，免得点一下就触发
        guard hypot(now.x - start.x, now.y - start.y) > 3 else { return }
        mouseDownEvent = nil
        let origin = convert(start, from: nil)
        let items = files.enumerated().map { index, url -> NSDraggingItem in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let icon = NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false))
            let offset = CGFloat(min(index, 4)) * 4
            item.setDraggingFrame(CGRect(x: origin.x - 16 + offset, y: origin.y - 16 - offset, width: 32, height: 32),
                                  contents: icon)
            return item
        }
        let session = beginDraggingSession(with: items, event: down, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
        session.draggingFormation = .pile
    }

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        // 放到哪里、是拷贝还是移动，由目标决定（和从访达里直接拖一样）
        context == .outsideApplication ? [.copy, .move, .link, .generic] : []
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        // 被移走的文件从架子上拿掉
        FileShelf.shared.pruneMissing()
    }
}

// MARK: - 晃一晃

/// 判断指针是不是在左右晃：一小段时间里来回换了几次方向，每一段都走得够远
struct ShakeTracker {
    var minimumSwing: CGFloat = 40
    var window: TimeInterval = 0.8
    var requiredReversals = 3

    private var direction: CGFloat = 0
    private var turnX: CGFloat?
    private var lastX: CGFloat?
    private var reversals: [TimeInterval] = []

    init() {}

    /// 送进指针的位置，晃够了返回 true
    mutating func add(x: CGFloat, time: TimeInterval) -> Bool {
        guard let previous = lastX else {
            lastX = x
            turnX = x
            return false
        }
        lastX = x
        let dx = x - previous
        guard abs(dx) >= 0.5 else { return false }
        let newDirection: CGFloat = dx > 0 ? 1 : -1
        if direction != 0, newDirection != direction {
            // 换方向了：上一段走得够远才算晃了一下
            if let turnX, abs(previous - turnX) >= minimumSwing {
                reversals.append(time)
            }
            turnX = previous
        }
        direction = newDirection
        reversals.removeAll { time - $0 > window }
        return reversals.count >= requiredReversals
    }
}

/// 全局监听鼠标拖动：拖着文件左右晃几下时回调（不拦截事件，也不需要额外的权限）
@MainActor
final class DragShakeDetector {
    var onShake: (CGPoint) -> Void = { _ in }
    private var monitors: [Any] = []
    private var tracker = ShakeTracker()
    private var dragChangeCount = 0
    /// 这次拖的是不是文件；还没开始拖放时为 nil
    private var draggingFiles: Bool?
    private var fired = false

    var isRunning: Bool { !monitors.isEmpty }

    func start() {
        guard monitors.isEmpty else { return }
        if let down = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseDown() }
        }) {
            monitors.append(down)
        }
        if let drag = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged, handler: { [weak self] event in
            let time = event.timestamp
            MainActor.assumeIsolated { self?.mouseDragged(time: time) }
        }) {
            monitors.append(drag)
        }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
    }

    private func mouseDown() {
        dragChangeCount = NSPasteboard(name: .drag).changeCount
        draggingFiles = nil
        tracker = ShakeTracker()
        fired = false
    }

    private func mouseDragged(time: TimeInterval) {
        guard !fired else { return }
        if draggingFiles == nil {
            // 按下鼠标之后开始了新的拖放才算（拖窗口、框选不算），看一次拖的是不是文件
            let pasteboard = NSPasteboard(name: .drag)
            guard pasteboard.changeCount != dragChangeCount else { return }
            draggingFiles = pasteboard.types?.contains(.fileURL) == true
        }
        guard draggingFiles == true else { return }
        let location = NSEvent.mouseLocation
        if tracker.add(x: location.x, time: time) {
            fired = true
            onShake(location)
        }
    }
}
