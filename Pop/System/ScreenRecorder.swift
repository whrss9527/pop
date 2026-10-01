import AppKit
import AVFoundation
import ScreenCaptureKit
import SwiftUI

/// 录屏：用 ScreenCaptureKit 把选中的一块屏幕录成 MP4（H.264，每秒 30 帧），存到系统截屏存放的文件夹。
/// 录的时候区域外面有一圈红色虚线框，旁边一个小面板显示时长和「停止」按钮，这两个窗口不会录进去；菜单栏上也能停止。
@MainActor
final class ScreenRecorder: NSObject {
    static let shared = ScreenRecorder()

    /// 录好了或者没录成
    var onFinish: (Result<ScreenRecording.Clip, ScreenRecording.Failure>) -> Void = { _ in }
    /// 开始、停止和录的时候每秒一次，刷新菜单栏上的时长
    var onTick: () -> Void = {}

    private var stream: SCStream?
    private var output: SCRecordingOutput?
    private let sink = FrameSink()
    private var url: URL?
    private var pixels = (width: 0, height: 0)
    private var startedAt: Date?
    private var timer: Timer?
    private var frameWindow: NSWindow?
    private var panel: NSPanel?
    private let panelModel = RecordingPanelModel()
    private var stopping = false
    /// 文件已经写完
    private var fileDone = false
    private var fileWaiter: CheckedContinuation<Void, Never>?
    /// 第几次等文件写完：上一次等待的超时不能算到这一次头上
    private var waitCount = 0
    private var problem: String?
    /// 停下来、收拾好以后要做的事（比如退出 Pop）
    private var afterStop: [() -> Void] = []
    /// 这次录屏显示了按键：录完关掉；原来单独开着的，回到跟着指针所在的屏幕
    private var showsKeysForRecording = false
    private var keysWereShowing = false

    var isRecording: Bool { stream != nil }

    /// 菜单栏上显示的时长；没在录时为 nil
    func elapsedText() -> String? {
        guard isRecording, let startedAt else { return nil }
        return ScreenRecording.durationText(Date().timeIntervalSince(startedAt))
    }

    /// 开始录 selection 选中的地方
    func start(_ selection: RegionPicker.Selection) async throws {
        guard stream == nil else { return }
        let audio = selection.options.audio
        // 要录麦克风：没问过先问一次，不让就不录
        if audio == .microphone, !(await Self.microphoneAllowed()) {
            throw ScreenRecording.Failure(message: ScreenRecording.microphoneHint)
        }
        let screen = selection.screen
        let whole = selection.rect.insetBy(dx: -1, dy: -1).contains(screen.frame)
        // 边框和控制面板先放上屏幕，才能在要录的内容里把它们排除掉
        let frame = whole ? nil : RecordingFrameWindow(region: selection.rect)
        frame?.orderFrontRegardless()
        panelModel.elapsed = ScreenRecording.durationText(0)
        panelModel.stopping = false
        let panel = RecordingPanel(model: panelModel, region: selection.rect, screen: screen) { [weak self] in
            self?.stop()
        }
        panel.orderFrontRegardless()
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first(where: { $0.displayID == screen.screenNumber }) else {
                throw ScreenRecording.Failure(message: String(localized: "找不到要录的屏幕"))
            }
            // 插件包的浮窗也不录（比如提词器：对着摄像头读稿时它在屏幕上方）
            let windows = [frame?.windowNumber, panel.windowNumber].compactMap { $0 } + PluginHost.shared.windowsExcludedFromRecording
            let ours = Set(windows.map { CGWindowID($0) })
            let filter = SCContentFilter(display: display, excludingWindows: content.windows.filter { ours.contains($0.windowID) })
            let source = ScreenRecording.sourceRect(selection.rect, in: screen.frame)
            let size = ScreenRecording.outputSize(points: source.size, scale: CGFloat(filter.pointPixelScale))

            let configuration = SCStreamConfiguration()
            configuration.sourceRect = source
            configuration.width = size.width
            configuration.height = size.height
            configuration.scalesToFit = true
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
            configuration.showsCursor = true
            configuration.showMouseClicks = selection.options.showClicks
            configuration.capturesAudio = audio == .system
            configuration.captureMicrophone = audio == .microphone
            configuration.excludesCurrentProcessAudio = true

            let folder = ScreenRecording.folder(screenshotLocation: ScreenRecording.screenshotLocation)
            let url = FileNames.available(in: folder, base: ScreenRecording.fileName(at: Date()), extension: "mp4")
            let recording = SCRecordingOutputConfiguration()
            recording.outputURL = url
            recording.outputFileType = .mp4
            recording.videoCodecType = .h264
            let output = SCRecordingOutput(configuration: recording, delegate: self)

            let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
            try stream.addStreamOutput(sink, type: .screen, sampleHandlerQueue: sink.queue)
            if audio == .system {
                try stream.addStreamOutput(sink, type: .audio, sampleHandlerQueue: sink.queue)
            }
            if audio == .microphone {
                try stream.addStreamOutput(sink, type: .microphone, sampleHandlerQueue: sink.queue)
            }
            try stream.addRecordingOutput(output)
            try await stream.startCapture()

            self.stream = stream
            self.output = output
            self.url = url
            pixels = size
            frameWindow = frame
            self.panel = panel
            fileDone = false
            problem = nil
            startedAt = Date()
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.tick()
                }
            }
            onTick()
            // 按键显示钉在录的区域下边，会一起录进去；单独开着的先挪过来
            if selection.options.showKeys {
                let keys = KeystrokeOverlay.shared
                keysWereShowing = keys.isActive
                if keysWereShowing || keys.start() == nil {
                    keys.pin(to: selection.rect)
                    showsKeysForRecording = true
                }
            }
        } catch {
            frame?.orderOut(nil)
            panel.orderOut(nil)
            if let failure = error as? ScreenRecording.Failure {
                throw failure
            }
            throw ScreenRecording.Failure(message: String(localized: "录屏没能开始：\(error.localizedDescription)"))
        }
    }

    /// 麦克风权限：没问过就问一次
    private static func microphoneAllowed() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        default:
            return false
        }
    }

    /// 停止录制，等文件写完再交给 onFinish；then 在收拾好以后调用
    func stop(then done: (() -> Void)? = nil) {
        guard let stream else {
            done?()
            return
        }
        if let done {
            afterStop.append(done)
        }
        guard !stopping else { return }
        stopping = true
        panelModel.stopping = true
        Task { @MainActor in
            try? await stream.stopCapture()
            await self.waitForFile(seconds: 10)
            self.complete()
        }
    }

    /// 演示用：不录，只把录的时候的边框和控制面板摆出来（让截图拍得到）；返回收起它们的方法
    func showIndicatorsForDemo(region: CGRect, screen: NSScreen, elapsed: String) -> () -> Void {
        let frame = RecordingFrameWindow(region: region)
        panelModel.elapsed = elapsed
        panelModel.stopping = false
        let panel = RecordingPanel(model: panelModel, region: region, screen: screen) {}
        for window in [frame, panel] as [NSWindow] {
            window.sharingType = .readOnly
            window.orderFrontRegardless()
        }
        return {
            frame.orderOut(nil)
            panel.orderOut(nil)
        }
    }

    private func tick() {
        guard let startedAt else { return }
        panelModel.elapsed = ScreenRecording.durationText(Date().timeIntervalSince(startedAt))
        onTick()
    }

    private func waitForFile(seconds: TimeInterval) async {
        guard !fileDone else { return }
        waitCount += 1
        let current = waitCount
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            fileWaiter = continuation
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.waitCount == current else { return }
                    self.resumeWaiter()
                }
            }
        }
    }

    /// 录的文件写完了（或者写失败了）
    private func fileFinished(_ recording: ObjectIdentifier, problem: String? = nil) {
        guard let output, ObjectIdentifier(output) == recording else { return }
        if let problem {
            self.problem = problem
        }
        fileDone = true
        resumeWaiter()
    }

    private func resumeWaiter() {
        guard let fileWaiter else { return }
        self.fileWaiter = nil
        fileWaiter.resume()
    }

    /// 录制停下来了（点了停止，或者系统那边停了），收拾窗口，把文件交出去
    private func complete() {
        defer {
            let waiting = afterStop
            afterStop = []
            waiting.forEach { $0() }
        }
        let duration = output.map { CMTimeGetSeconds($0.recordedDuration) } ?? 0
        let elapsed = startedAt.map { Date().timeIntervalSince($0) } ?? 0
        timer?.invalidate()
        timer = nil
        if showsKeysForRecording {
            let keys = KeystrokeOverlay.shared
            if keysWereShowing, keys.isActive {
                keys.unpin()
            } else {
                keys.stop()
            }
            showsKeysForRecording = false
        }
        frameWindow?.orderOut(nil)
        frameWindow = nil
        panel?.orderOut(nil)
        panel = nil
        stream = nil
        output = nil
        startedAt = nil
        stopping = false
        fileDone = false
        onTick()
        guard let url else { return }
        self.url = nil
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        if bytes > 0 {
            onFinish(.success(ScreenRecording.Clip(url: url, duration: duration.isFinite && duration > 0 ? duration : elapsed,
                                                   width: pixels.width, height: pixels.height)))
        } else {
            try? FileManager.default.removeItem(at: url)
            onFinish(.failure(ScreenRecording.Failure(message: problem.map { String(localized: "录屏失败：\($0)") } ?? String(localized: "没有录下来"))))
        }
        problem = nil
    }

    /// 系统那边停了（比如在菜单栏上点了停止共享、屏幕断开了）：当作停止，已经录下的照样存
    private func streamStopped(_ stopped: ObjectIdentifier, message: String) {
        guard let stream, ObjectIdentifier(stream) == stopped, !stopping else { return }
        problem = message
        stopping = true
        panelModel.stopping = true
        Task { @MainActor in
            await self.waitForFile(seconds: 10)
            self.complete()
        }
    }
}

extension ScreenRecorder: SCStreamDelegate, SCRecordingOutputDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        let stopped = ObjectIdentifier(stream)
        let message = error.localizedDescription
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.streamStopped(stopped, message: message)
            }
        }
    }

    nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        let recording = ObjectIdentifier(recordingOutput)
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.fileFinished(recording)
            }
        }
    }

    nonisolated func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        let recording = ObjectIdentifier(recordingOutput)
        let message = error.localizedDescription
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.fileFinished(recording, problem: message)
            }
        }
    }
}

/// 录屏只写文件，不处理画面：画面和声音接住直接丢掉（没有输出的话系统会一直在日志里报丢帧）
private final class FrameSink: NSObject, SCStreamOutput {
    let queue = DispatchQueue(label: "pop.screen-record.frames")

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {}
}

extension NSScreen {
    /// 这块屏幕的显示器编号
    var screenNumber: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}

// MARK: - 录的时候显示的边框和控制面板

/// 区域外面一圈红色虚线，不挡鼠标
private final class RecordingFrameWindow: NSWindow {
    static let margin: CGFloat = 4

    init(region: CGRect) {
        let frame = region.insetBy(dx: -RecordingFrameWindow.margin, dy: -RecordingFrameWindow.margin)
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
        contentView = FrameBorderView(frame: CGRect(origin: .zero, size: frame.size))
        setFrame(frame, display: false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class FrameBorderView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.systemRed.setStroke()
        let path = NSBezierPath(rect: bounds.insetBy(dx: 1.5, dy: 1.5))
        path.lineWidth = 2
        path.setLineDash([7, 4], count: 2, phase: 0)
        path.stroke()
    }
}

@MainActor
private final class RecordingPanelModel: ObservableObject {
    @Published var elapsed = "00:00"
    @Published var stopping = false
}

private struct RecordingPanelView: View {
    @ObservedObject var model: RecordingPanelModel
    let onStop: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
            Text(model.elapsed)
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
            Button(model.stopping ? String(localized: "正在保存…") : String(localized: "停止"), action: onStop)
                .controlSize(.small)
                .disabled(model.stopping)
        }
        .foregroundStyle(.white)
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.black.opacity(0.8)))
        .environment(\.colorScheme, .dark)
        .fixedSize()
    }
}

/// 显示时长和「停止」按钮的小面板：放在区域右下角的下面，放不下就放上面，再不行放进区域里；可以拖开
private final class RecordingPanel: NSPanel {
    init(model: RecordingPanelModel, region: CGRect, screen: NSScreen, onStop: @escaping () -> Void) {
        let content = NSHostingView(rootView: RecordingPanelView(model: model, onStop: onStop))
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
