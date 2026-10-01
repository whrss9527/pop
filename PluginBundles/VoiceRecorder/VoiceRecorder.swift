import AppKit
import AVFoundation
import SwiftUI
@testable import Pop

/// 录音：用 AVAudioRecorder 录成 AAC 的 .m4a（单声道、44.1 kHz、96 kbps），先录在临时文件夹，停下以后挪进「下载」。
///
/// 录的时候屏幕上方有一个小条：红点、时长、音量条、暂停和停止，可以拖开，录屏和截图时看不到它；存好后小条写着文件名，
/// 可以在访达中显示、接着转成文字，十秒后自己收起（指针放在上面时不收）。正在录的时候再用一次「录音」就停止；退出 Pop 时也先停下存好。
@MainActor
final class VoiceRecorder {
    static let shared = VoiceRecorder()

    private var recorder: AVAudioRecorder?
    private var panel: VoiceRecorderPanel?
    private let model = VoiceRecorderModel()
    private var meterTimer: Timer?
    private var closeTimer: Timer?
    private var startedAt = Date()
    private var terminationObserver: NSObjectProtocol?

    var isRecording: Bool {
        recorder != nil
    }

    /// 小条的窗口编号（录屏时不录它）
    var windowNumber: Int? {
        panel?.isVisible == true ? panel?.windowNumber : nil
    }

    /// 录成什么样：AAC、单声道、44.1 kHz、96 kbps
    nonisolated static var settings: [String: Any] {
        [AVFormatIDKey: kAudioFormatMPEG4AAC,
         AVSampleRateKey: 44_100,
         AVNumberOfChannelsKey: 1,
         AVEncoderBitRateKey: 96_000,
         AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue]
    }

    nonisolated static var permissionHint: String {
        String(localized: "要先在「系统设置 → 隐私与安全性 → 麦克风」里允许 Pop，才能录音")
    }

    /// 文件名：「录音 2026-10-01 15.42」（冒号不能用在文件名里）
    nonisolated static func fileName(at date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm"
        let stamp = formatter.string(from: date)
        return String(localized: "录音 \(stamp)")
    }

    /// 音量：-50 dB 以下算没声音，0 dB 最响
    nonisolated static func level(decibels: Float) -> Double {
        guard decibels.isFinite else { return 0 }
        return (min(max(Double(decibels), -50), 0) + 50) / 50
    }

    nonisolated static var downloadsFolder: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: "Downloads", directoryHint: .isDirectory)
    }

    /// 开始录，小条出现在 point 所在屏幕的上方；没有权限、录不了时返回原因
    func start(near point: CGPoint, canTranscribe: Bool) async -> String? {
        guard !isRecording else { return nil }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            break
        case .notDetermined:
            // 第一次会弹出系统的授权提示
            guard await AVCaptureDevice.requestAccess(for: .audio) else { return Self.permissionHint }
        default:
            return Self.permissionHint
        }
        guard !isRecording else { return nil }
        let url = FileManager.default.temporaryDirectory.appending(path: "pop-recording-\(UUID().uuidString).m4a")
        let recorder: AVAudioRecorder
        do {
            recorder = try AVAudioRecorder(url: url, settings: Self.settings)
        } catch {
            return String(localized: "录音没能开始：\(error.localizedDescription)")
        }
        recorder.isMeteringEnabled = true
        guard recorder.prepareToRecord(), recorder.record() else {
            try? FileManager.default.removeItem(at: url)
            return String(localized: "录音没能开始：没有找到能用的麦克风")
        }
        self.recorder = recorder
        startedAt = Date()
        closeTimer?.invalidate()
        closeTimer = nil
        model.reset(canTranscribe: canTranscribe)
        show(near: point)
        meterTimer?.invalidate()
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
        if terminationObserver == nil {
            // 退出 Pop 时先停下存好，不然录到一半的文件打不开
            terminationObserver = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil,
                                                                         queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    _ = self?.stop()
                }
            }
        }
        return nil
    }

    /// 暂停或者接着录
    func togglePause() {
        guard let recorder else { return }
        if recorder.isRecording {
            recorder.pause()
            model.phase = .paused
        } else if recorder.record() {
            model.phase = .recording
        }
    }

    /// 停下，挪进「下载」，小条换成存好的样子；返回存好的文件。没在录时为 nil
    @discardableResult
    func stop() -> URL? {
        guard let recorder else { return nil }
        let duration = recorder.currentTime
        recorder.stop()
        self.recorder = nil
        meterTimer?.invalidate()
        meterTimer = nil
        let destination = FileNames.available(in: Self.downloadsFolder, base: Self.fileName(at: startedAt), extension: "m4a")
        do {
            try FileManager.default.moveItem(at: recorder.url, to: destination)
        } catch {
            model.phase = .failed(String(localized: "录音没能存进「下载」：\(error.localizedDescription)"))
            relayout()
            scheduleClose()
            return nil
        }
        model.phase = .saved(destination, duration: duration)
        relayout()
        scheduleClose()
        return destination
    }

    /// 收起小条（在录的话先停下存好）
    func close() {
        if isRecording {
            stop()
        }
        closeTimer?.invalidate()
        closeTimer = nil
        panel?.orderOut(nil)
    }

    /// 演示用：不开麦克风，小条显示录了 42 秒、有说话声的样子；返回小条的位置
    func showForDemo(on screen: NSScreen) -> CGRect {
        close()
        model.reset(canTranscribe: true)
        model.elapsed = 42
        for index in 0..<VoiceRecorderModel.barCount {
            // 一句话的起伏：几个高低不同的峰
            let x = Double(index) / Double(VoiceRecorderModel.barCount - 1)
            model.push(0.15 + 0.75 * abs(sin(x * 9.5)) * (0.55 + 0.45 * sin(x * 3.1 + 0.6)))
        }
        show(near: CGPoint(x: screen.frame.midX, y: screen.frame.midY))
        panel?.sharingType = .readOnly
        return panel?.frame ?? .zero
    }

    // MARK: - 小条

    private func tick() {
        guard let recorder else { return }
        model.elapsed = recorder.currentTime
        guard recorder.isRecording else { return }
        recorder.updateMeters()
        model.push(Self.level(decibels: recorder.averagePower(forChannel: 0)))
    }

    private func show(near point: CGPoint) {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }) ?? NSScreen.main else { return }
        let size = panel.fittingSize
        let visible = screen.visibleFrame
        // 放在屏幕上方正中，菜单栏下面
        panel.setFrame(CGRect(x: visible.midX - size.width / 2, y: visible.maxY - size.height - 10, width: size.width, height: size.height),
                       display: true)
        panel.sharingType = .none
        panel.orderFrontRegardless()
        // 小条从别的样子（存好了）换回来时，等 SwiftUI 排好版再按新的大小调整一次
        relayout()
    }

    private func makePanel() -> VoiceRecorderPanel {
        let actions = VoiceRecorderActions(
            togglePause: { [weak self] in self?.togglePause() },
            stop: { [weak self] in _ = self?.stop() },
            reveal: { [weak self] in
                guard let self, case .saved(let url, _) = self.model.phase else { return }
                NSWorkspace.shared.activateFileViewerSelecting([url])
                self.close()
            },
            transcribe: { [weak self] in
                guard let self, case .saved(let url, _) = self.model.phase else { return }
                self.close()
                PluginHost.shared.runFunction(BuiltinPluginID.transcribe, [url])
            },
            close: { [weak self] in self?.close() })
        return VoiceRecorderPanel(rootView: VoiceRecorderCapsule(model: model, actions: actions))
    }

    /// 小条里的内容变了：等 SwiftUI 排好版再按新的大小调整，上边和中线不动
    private func relayout() {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let panel = self.panel else { return }
                let size = panel.fittingSize
                let old = panel.frame
                var frame = CGRect(x: old.midX - size.width / 2, y: old.maxY - size.height, width: size.width, height: size.height)
                if let visible = (panel.screen ?? NSScreen.main)?.visibleFrame {
                    frame.origin.x = min(max(frame.minX, visible.minX + 4), visible.maxX - frame.width - 4)
                }
                panel.setFrame(frame, display: true)
            }
        }
    }

    /// 存好后十秒收起；指针放在小条上时再等等
    private func scheduleClose() {
        closeTimer?.invalidate()
        closeTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.isRecording else { return }
                if self.model.isHovering {
                    self.scheduleClose()
                } else {
                    self.panel?.orderOut(nil)
                }
            }
        }
    }
}

/// 放小条的面板：在普通窗口上面，不抢焦点，可以拖开
private final class VoiceRecorderPanel: NSPanel {
    private let hosting: NSHostingView<VoiceRecorderCapsule>

    init(rootView: VoiceRecorderCapsule) {
        hosting = NSHostingView(rootView: rootView)
        let size = hosting.fittingSize
        super.init(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .statusBar
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isFloatingPanel = true
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        contentView = hosting
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var canBecomeKey: Bool { false }

    /// SwiftUI 内容想要的大小
    var fittingSize: CGSize {
        hosting.fittingSize
    }
}
