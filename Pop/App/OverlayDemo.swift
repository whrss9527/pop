import AppKit

/// 浮窗演示，给 CI 截图用。
///
/// 环境变量 POP_DEMO=1 启动时不弹设置窗口，而是按固定的时间表依次展示：圆盘展开、读到内容、
/// 指向一格、滑到另一格、选中后弹出结果卡片、提示、「全部功能」列表、再展开一次圆盘并取消；
/// 再按真实的手势流程走一遍：按住右键唤起、拖到上面一格、再拖到「剪贴板」、松开执行
/// （直接调用鼠标拦截的回调，拖动位置和真实使用时一样由拦截送来，不看系统的指针位置）；
/// 最后是单位换算的卡片、贴图、AI 卡片、窗口布局卡片、翻译卡片、常用短语、文本对比、图片配色、截图标注窗口
/// 和设置窗口里新加的几页。
/// 配合 POP_ANIMATION_SCALE 放慢动画，截图脚本就能拍到动画的中间帧；POP_APPEARANCE=dark 时用深色外观。
/// 每一步开始时往 POP_DEMO_LOG 指定的文件里写一行「步骤名 时间戳」；region 行是截图区域在屏幕上的位置
/// （点，AppKit 坐标：x y 宽 高）和屏幕大小，脚本按拍照时最新的那一行裁图。
@MainActor
enum OverlayDemo {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["POP_DEMO"] == "1"
    }

    static func run(overlay: OverlayController, coordinator: PopCoordinator, catalog: [PluginInfo], settings: AppSettings) {
        // POP_APPEARANCE=dark：用深色外观再走一遍，看看深色下的效果
        if ProcessInfo.processInfo.environment["POP_APPEARANCE"] == "dark" {
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        // 唤起点放在屏幕中间偏左上，右下方留出卡片和列表的位置
        let center = CGPoint(x: (visible.midX - 150).rounded(), y: (visible.midY + 150).rounded())
        logRegion(CGRect(x: center.x - 190, y: center.y - 480, width: 680, height: 680), screen: screen)

        let installed = Set(settings.installedPlugins)
        let text = ContentClassifier.classify(.text("Liquid glass"))
        let ring = RingViewModel(layout: settings.ring, catalog: catalog, installed: installed, content: nil)
        let chooserPlugins = catalog.filter { $0.id != BuiltinPluginID.allPlugins && installed.contains($0.id) && $0.canHandle(text) }
        let card = ResultCard(title: "字数统计", body: "", copyText: "12",
                              rows: [ResultCard.Row(label: "字符", value: "12"),
                                     ResultCard.Row(label: "单词", value: "2"),
                                     ResultCard.Row(label: "行", value: "1")])
        let unit = Motion.timeScale

        Task { @MainActor in
            await pause(1.5)
            step("ring")
            overlay.showRing(ring, center: center)

            await pause(0.5 * unit)
            step("loaded")
            ring.update(content: text)

            await pause(0.8 * unit)
            step("hover")
            ring.setHovered(0)

            await pause(0.7 * unit)
            step("slide")
            ring.setHovered(2)

            await pause(0.7 * unit)
            step("commit")
            ring.commit(2)
            overlay.showCard(ResultCardView(card: card, onAction: { _ in }, onMore: {}, onClose: {}), anchor: center)

            await pause(1.2 * unit)
            step("toast")
            overlay.showToast("已复制", anchor: center)

            await pause(1.6 * unit)
            step("chooser")
            overlay.showCard(PluginChooserView(model: PluginChooserModel(plugins: chooserPlugins), onClose: {}),
                             anchor: center)

            await pause(1.4 * unit)
            step("ring2")
            let again = RingViewModel(layout: settings.ring, catalog: catalog, installed: installed, content: text)
            overlay.showRing(again, center: center)

            await pause(1.0 * unit)
            step("cancel")
            overlay.hide()

            // 真实的手势：按住右键唤起（什么都没选中），拖到正上方的格子，再拖到左下方的「剪贴板」，松开
            await pause(1.0 * unit)
            step("press")
            if coordinator.mouseTriggerShouldBegin() {
                coordinator.mouseTriggerDidActivate(at: quartz(center))
            }

            await pause(1.2 * unit)
            step("drag-up")
            coordinator.mouseTriggerDidDrag(to: quartz(point(center, slot: 0, of: settings)))

            await pause(0.8 * unit)
            step("drag-clipboard")
            let clipboardSlot = settings.ring.slots.firstIndex(of: BuiltinPluginID.clipboardHistory) ?? 5
            let target = point(center, slot: clipboardSlot, of: settings)
            coordinator.mouseTriggerDidDrag(to: quartz(target))

            await pause(0.8 * unit)
            step("release")
            coordinator.mouseTriggerDidRelease(at: quartz(target))

            // 单位换算的结果卡片
            await pause(1.4 * unit)
            step("unit")
            coordinator.endSession()
            let measurement = ContentClassifier.classify(.text("5 km"))
            let converted = await UnitConvertPlugin().run(measurement, context: PluginContext(settings: settings, openSettings: {}))
            if case .card(let unitCard) = converted {
                overlay.showCard(ResultCardView(card: unitCard, onAction: { _ in }, onMore: {}, onClose: {}), anchor: center)
            }

            // 贴图：一段文字和一张图片贴在屏幕上，然后全部关掉
            await pause(1.4 * unit)
            step("pin")
            overlay.hide()
            PinBoard.shared.pin(text: "5 km ≈ 3.11 英里\n贴在屏幕上的文字，可以拖动、缩放", around: CGPoint(x: center.x + 40, y: center.y + 60))
            if let image = QRCode.generate("https://github.com/whrss9527/pop", scale: 6) {
                PinBoard.shared.pin(imageData: image, around: CGPoint(x: center.x + 260, y: center.y - 250))
            }

            await pause(1.4 * unit)
            step("unpin")
            PinBoard.shared.closeAll()

            // AI 卡片（演示时没有设置接口，显示的是引导去设置的样子）
            await pause(1.0 * unit)
            step("ai")
            let assistant = AIChatModel(source: "Liquid glass", settings: settings, keyProvider: { nil })
            overlay.showCard(AICardView(model: assistant, canReplace: false, onAction: { _ in }, onMore: {},
                                        onOpenSettings: {}, onClose: {}),
                             anchor: center)

            // 窗口布局卡片
            await pause(1.4 * unit)
            step("layout")
            overlay.showCard(WindowLayoutCardView(hasMultipleDisplays: false, onChoose: { _ in }, onClose: {}), anchor: center)

            // 翻译卡片（CI 上没有离线语言包，显示的是引导下载的样子），左上角可以换目标语言
            await pause(1.4 * unit)
            step("translate")
            let translation = TranslationModel(text: "Liquid glass", sourceLanguage: "en", targetLanguage: "zh-Hans")
            overlay.showCard(TranslationCardView(model: translation, canReplace: false, onAction: { _ in }, onMore: {},
                                                 onDownload: {}, onClose: {}),
                             anchor: center)

            // 常用短语列表
            await pause(1.4 * unit)
            step("snippets")
            let snippets = SnippetPickerModel(snippets: settings.snippets + [
                Snippet(title: "回复模板", text: "感谢反馈！我们会在 {date} 前回复你。"),
                Snippet(title: "会议链接", text: "https://meet.example.com/pop-weekly"),
            ])
            overlay.showCard(SnippetPickerView(model: snippets, onClose: {}), anchor: center)

            // 文本对比卡片
            await pause(1.4 * unit)
            step("diff")
            let diff = TextDiff.compare("长按右键唤起圆盘\n松开就执行\n支持 40 多个功能",
                                        "长按右键弹出圆盘\n松开就执行\n支持 50 多个功能\n还可以写自己的插件")
            overlay.showCard(ResultCardView(card: ResultCard(title: "文本对比",
                                                             detail: "剪贴板 → 选中的文字：删去 \(diff.removedCount) 行，"
                                                                 + "新增 \(diff.addedCount) 行",
                                                             copyText: diff.unifiedText, diff: diff),
                                            onAction: { _ in }, onMore: {}, onClose: {}),
                             anchor: center)

            // 图片配色卡片（用标注演示的那张示例图）
            await pause(1.4 * unit)
            step("palette")
            if let sample = sampleScreenshot() {
                let swatches = ColorPalette.extract(from: sample.image)
                let card = ResultCard(title: "图片配色", detail: "按面积从大到小；点色块复制色值",
                                      rows: swatches.map { ResultCard.Row(label: "占 \(Int((($0.share) * 100).rounded()))%", value: $0.hex) },
                                      palette: swatches.map(\.hex))
                overlay.showCard(ResultCardView(card: card, onAction: { _ in }, onMore: {}, onClose: {}), anchor: center)
            }

            // 截图标注窗口：拿一张画好的示例图，标上方框、箭头、文字、马赛克和序号；截图区域换成标注窗口
            await pause(1.4 * unit)
            overlay.hide()
            if let capture = sampleScreenshot() {
                let annotation = AnnotationWindowController.present(capture, near: center)
                annotateSample(annotation)
                await pause(0.3 * unit)
                if let window = NSApp.windows.first(where: { $0.isVisible && $0.title == "截图标注" }) {
                    logRegion(window.frame, screen: screen)
                }
            }
            step("annotate")
            await pause(1.4 * unit)
            NSApp.windows.first { $0.isVisible && $0.title == "截图标注" }?.close()

            // 设置窗口里新加的几页：截图区域换成设置窗口
            await pause(0.6 * unit)
            for tab in [SettingsTab.ai, .hotKeys] {
                coordinator.openSettings(tab)
                await pause(0.6 * unit)
                if let window = NSApp.windows.first(where: { $0.isVisible && $0.title == "Pop 设置" }) {
                    logRegion(window.frame, screen: screen)
                }
                step("settings-\(tab.rawValue)")
                await pause(0.8 * unit)
            }

            step("end")
        }
    }

    /// 标注演示用的「截图」：一张账户设置卡片，480×300 点、2 倍像素
    private static func sampleScreenshot() -> ScreenCapture.Capture? {
        let width = 960
        let height = 600
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // 换成「点、左上角为原点」的坐标
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 2, y: -2)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        context.setFillColor(NSColor(srgbRed: 0.93, green: 0.94, blue: 0.96, alpha: 1).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 480, height: 300))
        context.setFillColor(NSColor.white.cgColor)
        context.addPath(CGPath(roundedRect: CGRect(x: 40, y: 36, width: 400, height: 228), cornerWidth: 14, cornerHeight: 14,
                               transform: nil))
        context.fillPath()
        func text(_ string: String, at point: CGPoint, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor) {
            NSAttributedString(string: string, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight),
                                                            .foregroundColor: color]).draw(at: point)
        }
        text("账户设置", at: CGPoint(x: 64, y: 58), size: 20, weight: .semibold, color: .black)
        text("邮箱：pop@example.com", at: CGPoint(x: 64, y: 102), size: 13, color: .darkGray)
        text("手机：138 0000 0000", at: CGPoint(x: 64, y: 128), size: 13, color: .darkGray)
        text("登录设备：3 台", at: CGPoint(x: 64, y: 154), size: 13, color: .darkGray)
        context.setFillColor(NSColor(srgbRed: 0, green: 0.48, blue: 1, alpha: 1).cgColor)
        context.addPath(CGPath(roundedRect: CGRect(x: 300, y: 204, width: 116, height: 36), cornerWidth: 8, cornerHeight: 8,
                               transform: nil))
        context.fillPath()
        text("保存更改", at: CGPoint(x: 330, y: 213), size: 14, weight: .medium, color: .white)
        NSGraphicsContext.restoreGraphicsState()
        guard let image = context.makeImage(),
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return nil }
        return ScreenCapture.Capture(image: image, png: png)
    }

    /// 在示例图上标几笔：给手机号打码、序号、框出按钮、箭头指过去再写一句话
    private static func annotateSample(_ model: AnnotationModel) {
        func stroke(_ tool: AnnotationTool, from start: CGPoint, to end: CGPoint) {
            model.tool = tool
            model.begin(at: start)
            model.drag(to: end)
            model.end()
        }
        stroke(.mosaic, from: CGPoint(x: 100, y: 124), to: CGPoint(x: 200, y: 148))
        model.tool = .counter
        model.begin(at: CGPoint(x: 222, y: 136))
        stroke(.rectangle, from: CGPoint(x: 293, y: 197), to: CGPoint(x: 423, y: 247))
        stroke(.arrow, from: CGPoint(x: 176, y: 238), to: CGPoint(x: 286, y: 224))
        model.tool = .text
        model.begin(at: CGPoint(x: 72, y: 228))
        model.textDraft = "改完点这里"
        model.commitText()
        model.tool = .arrow
    }

    /// 截图区域（点，AppKit 坐标）和屏幕大小，截图脚本按它裁图
    private static func logRegion(_ region: CGRect, screen: NSScreen) {
        log("region \(Int(region.minX)) \(Int(region.minY)) \(Int(region.width)) \(Int(region.height)) "
            + "\(Int(screen.frame.width)) \(Int(screen.frame.height))")
    }

    /// 圆盘上第 slot 格方向、离圆心 95 点的位置（AppKit 坐标）
    private static func point(_ center: CGPoint, slot: Int, of settings: AppSettings) -> CGPoint {
        let offset = RingGeometry(slotCount: max(settings.ring.slotCount, 1)).slotCenterOffset(slot, radius: 95)
        return CGPoint(x: center.x + offset.dx, y: center.y + offset.dy)
    }

    /// AppKit 屏幕坐标换成鼠标拦截用的 Quartz 坐标（主屏左上角为原点）
    private static func quartz(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: OverlayController.primaryScreenHeight - point.y)
    }

    private static func pause(_ seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    private static func step(_ name: String) {
        log("\(name) \(Date().timeIntervalSince1970)")
    }

    private static func log(_ line: String) {
        guard let path = ProcessInfo.processInfo.environment["POP_DEMO_LOG"] else { return }
        let url = URL(fileURLWithPath: path)
        let data = Data((line + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }
}
