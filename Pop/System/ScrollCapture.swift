import AppKit
import CoreMedia
import ScreenCaptureKit
import SwiftUI
import VideoToolbox

/// 滚动截图：框好区域以后，一边往下滚动一边截，拼成一张长图。
/// 区域外面一圈蓝色虚线框，旁边一个小面板显示截了多长、「完成」和「取消」，这两个窗口不会截进去；按 Esc 也是取消。
/// 截的是画面有变化时 ScreenCaptureKit 送来的每一帧，交给 ScrollStitcher 拼。
@MainActor
final class ScrollCapture: NSObject {
    static let shared = ScrollCapture()

    struct Failure: Error, Equatable {
        let message: String
    }

    /// 拼好了（结果卡片）或者没截成
    var onFinish: (Result<ResultCard, Failure>) -> Void = { _ in }

    private var stream: SCStream?
    private let sink = ScrollFrameSink()
    private var frameWindow: NSWindow?
    private var panel: NSPanel?
    private let panelModel = ScrollCapturePanelModel()
    private var escapeMonitor: Any?
    private var starting = false

    var isCapturing: Bool { starting || stream != nil }

    /// 开始截 selection 选中的地方；画面开始送过来以后就返回，拼好的长图从 onFinish 交出去
    func start(_ selection: RegionPicker.Selection) async throws {
        guard !isCapturing else { return }
        starting = true
        defer { starting = false }
        let screen = selection.screen
        let frame = ScrollFrameWindow(region: selection.rect)
        frame.orderFrontRegardless()
        panelModel.progress = ScrollCaptureProgress()
        panelModel.ready = false
        panelModel.finishing = false
        let panel = ScrollCapturePanel(model: panelModel, region: selection.rect, screen: screen,
                                       onDone: { [weak self] in self?.finish() },
                                       onCancel: { [weak self] in self?.cancel() })
        panel.orderFrontRegardless()
        frameWindow = frame
        self.panel = panel
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first(where: { $0.displayID == screen.screenNumber }) else {
                throw Failure(message: String(localized: "找不到要截的屏幕"))
            }
            let ours = Set([frame.windowNumber, panel.windowNumber].map { CGWindowID($0) })
            let filter = SCContentFilter(display: display, excludingWindows: content.windows.filter { ours.contains($0.windowID) })
            let source = ScreenRecording.sourceRect(selection.rect, in: screen.frame)
            let scale = CGFloat(filter.pointPixelScale)

            let configuration = SCStreamConfiguration()
            configuration.sourceRect = source
            configuration.width = max(1, Int((source.width * scale).rounded()))
            configuration.height = max(1, Int((source.height * scale).rounded()))
            configuration.scalesToFit = false
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: 20)
            configuration.showsCursor = false
            configuration.pixelFormat = kCVPixelFormatType_32BGRA
            configuration.queueDepth = 3

            sink.reset { [weak self] progress in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        self?.update(progress)
                    }
                }
            }
            let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
            try stream.addStreamOutput(sink, type: .screen, sampleHandlerQueue: sink.queue)
            try await stream.startCapture()
            self.stream = stream
            panelModel.ready = true
            installEscapeMonitor()
        } catch {
            cleanUp()
            if let failure = error as? Failure {
                throw failure
            }
            throw Failure(message: String(localized: "滚动截图没能开始：\(error.localizedDescription)"))
        }
    }

    /// 截好了：停下来，拼成长图交出去
    func finish() {
        guard let stream, !panelModel.finishing else { return }
        panelModel.finishing = true
        Task { @MainActor in
            try? await stream.stopCapture()
            let card = await self.sink.finish()
            self.cleanUp()
            if let card {
                self.onFinish(.success(card))
            } else {
                self.onFinish(.failure(Failure(message: ScreenRecording.permissionHint)))
            }
        }
    }

    /// 不要了：停下来，什么都不留
    func cancel() {
        guard let stream, !panelModel.finishing else { return }
        panelModel.finishing = true
        Task { @MainActor in
            try? await stream.stopCapture()
            _ = await self.sink.finish(keeping: false)
            self.cleanUp()
        }
    }

    /// 演示用：不截，只把截的时候的边框和面板摆出来（让截图拍得到）；返回收起它们的方法
    func showIndicatorsForDemo(region: CGRect, screen: NSScreen, progress: ScrollCaptureProgress) -> () -> Void {
        let frame = ScrollFrameWindow(region: region)
        panelModel.progress = progress
        panelModel.ready = true
        panelModel.finishing = false
        let panel = ScrollCapturePanel(model: panelModel, region: region, screen: screen, onDone: {}, onCancel: {})
        for window in [frame, panel] as [NSWindow] {
            window.sharingType = .readOnly
            window.orderFrontRegardless()
        }
        return {
            frame.orderOut(nil)
            panel.orderOut(nil)
        }
    }

    private func update(_ progress: ScrollCaptureProgress) {
        // 第一帧可能在 startCapture 返回之前就到了
        guard isCapturing, !panelModel.finishing else { return }
        panelModel.progress = progress
        // 长图到上限了：自动完成
        if progress.full {
            finish()
        }
    }

    private func installEscapeMonitor() {
        guard escapeMonitor == nil else { return }
        escapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return } // Esc
            MainActor.assumeIsolated {
                self?.cancel()
            }
        }
    }

    private func cleanUp() {
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
        }
        escapeMonitor = nil
        frameWindow?.orderOut(nil)
        panel?.orderOut(nil)
        frameWindow = nil
        panel = nil
        stream = nil
    }

    fileprivate func streamStopped(_ message: String) {
        guard stream != nil, !panelModel.finishing else { return }
        cleanUp()
        onFinish(.failure(Failure(message: String(localized: "滚动截图中断了：\(message)"))))
    }
}

extension ScrollCapture: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        let message = error.localizedDescription
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                ScrollCapture.shared.streamStopped(message)
            }
        }
    }
}

/// 截了多长
struct ScrollCaptureProgress: Equatable {
    /// 长图多高（像素）
    var height = 0
    /// 截的区域有多高（像素），算有几屏用
    var frameHeight = 0
    /// 最近几屏都对不上
    var lost = false
    /// 长图到上限了
    var full = false
}

// MARK: - 收画面、拼长图

/// 在自己的队列里收 ScreenCaptureKit 送来的画面，交给 ScrollStitcher 拼
private final class ScrollFrameSink: NSObject, SCStreamOutput, @unchecked Sendable {
    let queue = DispatchQueue(label: "io.github.whrss9527.pop.scroll-capture")
    private var stitcher: ScrollStitcher?
    private var lostInARow = 0
    private var onProgress: (ScrollCaptureProgress) -> Void = { _ in }

    func reset(onProgress: @escaping (ScrollCaptureProgress) -> Void) {
        queue.sync {
            stitcher = nil
            lostInARow = 0
            self.onProgress = onProgress
        }
    }

    /// 停下来以后：拼好的长图做成结果卡片（keeping 为 false 时只是丢掉）
    func finish(keeping: Bool = true) async -> ResultCard? {
        await withCheckedContinuation { continuation in
            queue.async {
                var card: ResultCard?
                if keeping, let stitcher = self.stitcher, let image = stitcher.makeImage() {
                    card = ScrollStitcher.card(image, frameHeight: stitcher.frameHeight)
                }
                self.stitcher = nil
                self.onProgress = { _ in }
                continuation.resume(returning: card)
            }
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, let image = Self.image(from: sampleBuffer) else { return }
        if stitcher == nil {
            stitcher = ScrollStitcher(first: image)
            report(lost: false, full: false)
            return
        }
        guard let step = stitcher?.add(image) else { return }
        switch step {
        case .appended:
            lostInARow = 0
        case .lost:
            lostInARow += 1
        case .unchanged, .full:
            break
        }
        // 偶尔对不上一帧（正在滚的中间帧）不用提示，连着几帧才提示
        report(lost: lostInARow >= 3, full: step == .full)
    }

    private func report(lost: Bool, full: Bool) {
        guard let stitcher else { return }
        onProgress(ScrollCaptureProgress(height: stitcher.height, frameHeight: stitcher.frameHeight, lost: lost, full: full))
    }

    /// 画面有变化的一帧转成图片；没变化的帧（idle）不要
    private static func image(from sampleBuffer: CMSampleBuffer) -> CGImage? {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let rawStatus = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: rawStatus) == .complete,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
        var image: CGImage?
        VTCreateCGImageFromCVPixelBuffer(pixelBuffer, options: nil, imageOut: &image)
        return image
    }
}

// MARK: - 截的时候显示的边框和面板

/// 区域外面一圈蓝色虚线，不挡鼠标，也不会被截进去
private final class ScrollFrameWindow: NSWindow {
    static let margin: CGFloat = 4

    init(region: CGRect) {
        let frame = region.insetBy(dx: -ScrollFrameWindow.margin, dy: -ScrollFrameWindow.margin)
        super.init(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        level = .statusBar
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        sharingType = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        contentView = ScrollFrameBorderView(frame: CGRect(origin: .zero, size: frame.size))
        setFrame(frame, display: false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class ScrollFrameBorderView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlAccentColor.setStroke()
        let path = NSBezierPath(rect: bounds.insetBy(dx: 1.5, dy: 1.5))
        path.lineWidth = 2
        path.setLineDash([7, 4], count: 2, phase: 0)
        path.stroke()
    }
}

@MainActor
private final class ScrollCapturePanelModel: ObservableObject {
    @Published var progress = ScrollCaptureProgress()
    @Published var ready = false
    @Published var finishing = false
}

private struct ScrollCapturePanelView: View {
    @ObservedObject var model: ScrollCapturePanelModel
    let onDone: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Image(systemName: "scroll")
                    .font(.system(size: 12, weight: .semibold))
                Text(status)
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .lineLimit(1)
                Spacer(minLength: 8)
                Button("取消", action: onCancel)
                    .controlSize(.small)
                    .disabled(model.finishing)
                Button(model.finishing ? String(localized: "正在拼图…") : String(localized: "完成"), action: onDone)
                    .controlSize(.small)
                    .disabled(!model.ready || model.finishing)
            }
            Text(hint)
                .font(.system(size: 11))
                .foregroundStyle(model.progress.lost || model.progress.full ? Color.orange : Color.white.opacity(0.75))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(width: 400, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.black.opacity(0.8)))
        .environment(\.colorScheme, .dark)
        .fixedSize()
    }

    private var status: String {
        guard model.ready else { return String(localized: "正在准备…") }
        let height = String(model.progress.height)
        let screens = ScrollStitcher.screensText(height: model.progress.height, frameHeight: model.progress.frameHeight)
        return String(localized: "滚动截图 · 已截 \(height) 像素高，约 \(screens) 屏")
    }

    private var hint: String {
        if model.progress.full {
            return String(localized: "长图到上限了，正在拼好")
        }
        if model.progress.lost {
            return String(localized: "对不上了：往回滚一点，接上以后再慢慢往下滚")
        }
        return String(localized: "往下滚动要截的内容，滚到底点「完成」；Esc 取消")
    }
}

/// 面板放在区域右下角的下面，放不下就放上面，再不行放进区域里；可以拖开
private final class ScrollCapturePanel: NSPanel {
    init(model: ScrollCapturePanelModel, region: CGRect, screen: NSScreen, onDone: @escaping () -> Void, onCancel: @escaping () -> Void) {
        let content = NSHostingView(rootView: ScrollCapturePanelView(model: model, onDone: onDone, onCancel: onCancel))
        let size = content.fittingSize
        let bounds = screen.visibleFrame
        var origin = CGPoint(x: region.maxX - size.width, y: region.minY - size.height - 10)
        if origin.y < bounds.minY + 4 {
            origin.y = region.maxY + 10
        }
        if origin.y + size.height > bounds.maxY - 4 {
            origin = CGPoint(x: region.maxX - size.width - 12, y: region.minY + 12)
        }
        origin.x = min(max(origin.x, bounds.minX + 4), bounds.maxX - size.width - 4)
        origin.y = min(max(origin.y, bounds.minY + 4), bounds.maxY - size.height - 4)
        super.init(contentRect: CGRect(origin: origin, size: size), styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        level = .statusBar
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isFloatingPanel = true
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        sharingType = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        contentView = content
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var canBecomeKey: Bool { false }
}
