import AppKit
import CoreText
@testable import Pop

/// 插件包「窗口画中画」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopWindowPiPEntry)
final class WindowPiPEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [WindowPiPPlugin()]
    }

    @MainActor static func didLoad(_ host: PluginHost.Registrar) {
        // CI 截图：选窗口的卡片（示例的窗口和缩略图，不抓 CI 机器的屏幕）
        host.addDemoScene(PluginHost.DemoScene(name: "windowPiP", after: "pdfPages", order: 25, delay: 1.4, hold: 0, show: { demo in
            demo.overlay.showCard(PiPChooserView(model: WindowPiPPlugin.demoModel(), onClose: {}), anchor: demo.center)
            return demo.cardRegion
        }))
        // 屏幕右下角的小窗：示例的视频会议画面，指针移上去时的按钮也显示出来
        host.addDemoScene(PluginHost.DemoScene(name: "windowPiP-panel", after: "pdfPages", order: 26, delay: 1.4, show: { demo in
            guard let image = WindowPiPPlugin.demoMeeting() else { return nil }
            // 连同阴影和周围的桌面一起截
            return PictureInPicture.shared.showForDemo(image: image, title: "产品周会", on: demo.screen).insetBy(dx: -24, dy: -24)
        }, hide: {
            PictureInPicture.shared.closeAll()
        }))
    }

    @MainActor static func willUninstall() {
        PictureInPicture.shared.closeAll()
    }
}

struct WindowPiPPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.windowPiP, name: String(localized: "窗口画中画"), symbol: "pip",
                          summary: String(localized: "把一个窗口的画面实时放进屏幕角落的小窗，一直浮在别的窗口上面：边干活边看着视频、会议、下载进度；拖动换位置，滚动换大小，双击回到原来的窗口"),
                          accepts: [])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard CGPreflightScreenCaptureAccess() else {
            // 第一次会弹出系统的授权提示
            _ = CGRequestScreenCaptureAccess()
            return .failure(ScreenRecording.permissionHint)
        }
        let listing: PiPCapture.Listing
        do {
            listing = try await PiPCapture.listWindows()
        } catch {
            return .failure(String(localized: "读不到屏幕上的窗口：\(error.localizedDescription)"))
        }
        guard !listing.items.isEmpty else {
            return .failure(String(localized: "屏幕上没有能放进小窗的窗口"))
        }
        let pointer = context.anchor ?? NSEvent.mouseLocation
        let under = PiPWindows.item(at: PiPWindows.cgPoint(fromAppKit: pointer, primaryScreenHeight: OverlayController.primaryScreenHeight),
                                    in: listing.items)
        let pip = PictureInPicture.shared
        let model = PiPChooserModel(items: listing.items, under: under?.id, openCount: pip.count,
                                    showing: Set(listing.items.map(\.id).filter { pip.isShowing($0) }))
        return .present(PluginPresentation { session in
            model.onChoose = { item in
                guard let window = listing.windows[item.id] else { return }
                session.end()
                Task { @MainActor in
                    if let problem = await pip.open(item, window: window, near: pointer) {
                        session.finish(toast: problem)
                    }
                }
            }
            model.onCloseAll = {
                pip.closeAll()
                session.end()
            }
            session.showCard(PiPChooserView(model: model, onClose: { session.end() }), keyHandler: { model.handleKey($0) })
            model.loadThumbnails(listing.windows)
        })
    }

    // MARK: - 演示（示例内容不翻译）

    /// 演示用的卡片：会议、终端、设置、Safari 四个窗口，会议那个在指针下面
    @MainActor static func demoModel() -> PiPChooserModel {
        let items = [
            PiPWindows.Item(id: 11, pid: 1, appName: "Safari", title: "发布会直播", frame: CGRect(x: 80, y: 60, width: 1280, height: 800)),
            PiPWindows.Item(id: 12, pid: 2, appName: "FaceTime", title: "产品周会", frame: CGRect(x: 200, y: 120, width: 960, height: 540)),
            PiPWindows.Item(id: 13, pid: 3, appName: "终端", title: "npm run build", frame: CGRect(x: 40, y: 400, width: 720, height: 450)),
            PiPWindows.Item(id: 14, pid: 4, appName: "系统设置", title: "账户设置", frame: CGRect(x: 600, y: 300, width: 480, height: 300)),
        ]
        var thumbnails: [CGWindowID: CGImage] = [:]
        thumbnails[11] = demoVideo()
        thumbnails[12] = demoMeeting()
        thumbnails[13] = demoTerminal()
        thumbnails[14] = OverlayDemo.sampleScreenshot()?.image
        let apps: [pid_t: String] = [1: "/Applications/Safari.app", 2: "/System/Applications/FaceTime.app",
                                     3: "/System/Applications/Utilities/Terminal.app", 4: "/System/Applications/System Settings.app"]
        return PiPChooserModel(items: items, under: 12, openCount: 0, thumbnails: thumbnails) { pid in
            apps[pid].map { NSWorkspace.shared.icon(forFile: $0) }
        }
    }

    /// 示例的视频会议画面：深色背景上的示例人像，左下角写着名字
    @MainActor static func demoMeeting() -> CGImage? {
        drawDemo(width: 960, height: 540) { context in
            context.setFillColor(CGColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 960, height: 540))
            if let camera = OverlayDemo.sampleCameraFrame() {
                let tile = CGRect(x: 210, y: 0, width: 540, height: 540)
                context.saveGState()
                context.addPath(CGPath(roundedRect: tile.insetBy(dx: 12, dy: 12), cornerWidth: 18, cornerHeight: 18, transform: nil))
                context.clip()
                context.draw(camera, in: tile.insetBy(dx: 12, dy: 12))
                context.restoreGState()
            }
            label("李华", in: context, at: CGPoint(x: 236, y: 34), size: 22)
        }
    }

    /// 示例的直播画面：渐变的舞台，中间一个播放的三角
    @MainActor static func demoVideo() -> CGImage? {
        drawDemo(width: 1280, height: 800) { context in
            let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
            let colors = [CGColor(srgbRed: 0.18, green: 0.2, blue: 0.45, alpha: 1), CGColor(srgbRed: 0.55, green: 0.24, blue: 0.5, alpha: 1)]
            if let gradient = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: [0, 1]) {
                context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 800), end: CGPoint(x: 1280, y: 0), options: [])
            }
            context.setFillColor(CGColor(gray: 1, alpha: 0.85))
            context.fillEllipse(in: CGRect(x: 560, y: 320, width: 160, height: 160))
            context.setFillColor(CGColor(srgbRed: 0.35, green: 0.22, blue: 0.48, alpha: 1))
            context.move(to: CGPoint(x: 618, y: 360))
            context.addLine(to: CGPoint(x: 618, y: 440))
            context.addLine(to: CGPoint(x: 684, y: 400))
            context.closePath()
            context.fillPath()
            label("发布会直播", in: context, at: CGPoint(x: 48, y: 48), size: 36)
        }
    }

    /// 示例的终端：深色背景上几行编译输出
    @MainActor static func demoTerminal() -> CGImage? {
        drawDemo(width: 720, height: 450) { context in
            context.setFillColor(CGColor(srgbRed: 0.09, green: 0.1, blue: 0.12, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 720, height: 450))
            let lines: [(String, CGColor)] = [
                ("$ npm run build", CGColor(gray: 0.92, alpha: 1)),
                ("> vite build", CGColor(gray: 0.6, alpha: 1)),
                ("✓ 1204 modules transformed.", CGColor(srgbRed: 0.42, green: 0.85, blue: 0.5, alpha: 1)),
                ("dist/index.html        0.46 kB", CGColor(gray: 0.75, alpha: 1)),
                ("dist/assets/index.js   143.2 kB", CGColor(gray: 0.75, alpha: 1)),
                ("✓ built in 3.81s", CGColor(srgbRed: 0.42, green: 0.85, blue: 0.5, alpha: 1)),
            ]
            for (index, line) in lines.enumerated() {
                label(line.0, in: context, at: CGPoint(x: 28, y: 400 - CGFloat(index) * 40), size: 22, color: line.1, monospaced: true)
            }
        }
    }

    private static func drawDemo(width: Int, height: Int, _ draw: (CGContext) -> Void) -> CGImage? {
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        draw(context)
        return context.makeImage()
    }

    /// 在左下角为原点的坐标里写一行字（基线在 point）
    private static func label(_ text: String, in context: CGContext, at point: CGPoint, size: CGFloat,
                              color: CGColor = CGColor(gray: 1, alpha: 1), monospaced: Bool = false) {
        let font = monospaced ? NSFont.monospacedSystemFont(ofSize: size, weight: .regular) : NSFont.systemFont(ofSize: size, weight: .semibold)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ]))
        context.textMatrix = .identity
        context.textPosition = point
        CTLineDraw(line, context)
    }
}
