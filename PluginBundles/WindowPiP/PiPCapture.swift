import AppKit
import CoreMedia
import ScreenCaptureKit
@testable import Pop

/// 用 ScreenCaptureKit 列出屏幕上的窗口、拍缩略图、实时抓一个窗口的画面（要「录屏与系统录音」权限）
enum PiPCapture {
    /// 屏幕上能放进小窗的窗口（从前到后），和开小窗时要用的 SCWindow
    struct Listing {
        var items: [PiPWindows.Item]
        var windows: [CGWindowID: SCWindow]
    }

    static func listWindows() async throws -> Listing {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        var windows: [CGWindowID: SCWindow] = [:]
        let all: [PiPWindows.Item] = content.windows.compactMap { window in
            guard let app = window.owningApplication else { return nil }
            windows[window.windowID] = window
            return PiPWindows.Item(id: window.windowID, pid: app.processID, appName: app.applicationName,
                                   title: window.title ?? "", frame: window.frame, layer: window.windowLayer, isOnScreen: window.isOnScreen)
        }
        let items = PiPWindows.candidates(all, ownPID: ProcessInfo.processInfo.processIdentifier, order: frontToBack())
        return Listing(items: items, windows: windows.filter { id, _ in items.contains { $0.id == id } })
    }

    /// 屏幕上的窗口从前到后的顺序（CGWindowList 按这个顺序给）
    static func frontToBack() -> [CGWindowID] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return list.compactMap { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value }
    }

    /// 窗口的缩略图：长边 longSide 点（按屏幕倍率出像素），拍不到时为 nil
    static func thumbnail(of window: SCWindow, longSide: CGFloat = 320) async -> CGImage? {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let size = PiPLayout.size(for: window.frame.size, longSide: longSide)
        let pixels = PiPLayout.captureSize(for: size, scale: CGFloat(filter.pointPixelScale))
        let configuration = SCStreamConfiguration()
        configuration.width = pixels.width
        configuration.height = pixels.height
        configuration.showsCursor = false
        return try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }
}

/// 实时抓一个窗口的画面，一帧帧放到 layer 上（窗口被挡住、拖到别的桌面也照样抓得到）
final class PiPStream: NSObject, SCStreamOutput, SCStreamDelegate {
    private var stream: SCStream?
    private let configuration = SCStreamConfiguration()
    private let queue = DispatchQueue(label: "pop.window-pip.frames")
    /// 画面放在这个 layer 上（只在主线程上碰它）
    private weak var layer: CALayer?
    /// 抓不下去了（原来的窗口关掉了、App 退出了）
    var onStop: @MainActor () -> Void = {}

    init(layer: CALayer) {
        self.layer = layer
        super.init()
        // 每秒最多 30 帧；窗口没变化时 ScreenCaptureKit 不发新帧，不费电
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        configuration.queueDepth = 4
        configuration.showsCursor = false
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.scalesToFit = true
    }

    func start(window: SCWindow, pixels: (width: Int, height: Int)) async throws {
        configuration.width = pixels.width
        configuration.height = pixels.height
        let stream = SCStream(filter: SCContentFilter(desktopIndependentWindow: window), configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try await stream.startCapture()
        self.stream = stream
    }

    /// 小窗换了大小：按新的大小抓，画面一直清楚
    func resize(pixels: (width: Int, height: Int)) async {
        guard let stream, configuration.width != pixels.width || configuration.height != pixels.height else { return }
        configuration.width = pixels.width
        configuration.height = pixels.height
        try? await stream.updateConfiguration(configuration)
    }

    func stop() async {
        guard let stream else { return }
        self.stream = nil
        try? await stream.stopCapture()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        // 只要画好了的完整一帧（窗口没变化时发来的是 idle）
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let rawStatus = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: rawStatus) == .complete,
              let pixelBuffer = sampleBuffer.imageBuffer,
              let surface = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue() else { return }
        DispatchQueue.main.async { [weak self] in
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self?.layer?.contents = surface
            CATransaction.commit()
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.onStop()
            }
        }
    }
}
