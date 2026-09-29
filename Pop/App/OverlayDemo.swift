import AppKit

/// 浮窗演示，给 CI 截图用。
///
/// 环境变量 POP_DEMO=1 启动时不弹设置窗口，而是按固定的时间表依次展示：圆盘展开、读到内容、
/// 指向一格、滑到另一格、选中后弹出结果卡片、提示、「全部功能」列表、再展开一次圆盘并取消；
/// 再按真实的手势流程走一遍：按住右键唤起、拖到上面一格、再拖到「剪贴板」、松开执行
/// （直接调用鼠标拦截的回调，拖动位置和真实使用时一样由拦截送来，不看系统的指针位置）；
/// 最后是单位换算的卡片和贴图。
/// 配合 POP_ANIMATION_SCALE 放慢动画，截图脚本就能拍到动画的中间帧。
/// 每一步开始时往 POP_DEMO_LOG 指定的文件里写一行「步骤名 时间戳」；第一行是演示区域在屏幕上的位置
/// （点，AppKit 坐标：x y 宽 高）和屏幕大小，脚本按它裁图。
@MainActor
enum OverlayDemo {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["POP_DEMO"] == "1"
    }

    static func run(overlay: OverlayController, coordinator: PopCoordinator, catalog: [PluginInfo], settings: AppSettings) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        // 唤起点放在屏幕中间偏左上，右下方留出卡片和列表的位置
        let center = CGPoint(x: (visible.midX - 150).rounded(), y: (visible.midY + 150).rounded())
        let region = CGRect(x: center.x - 190, y: center.y - 480, width: 680, height: 680)
        log("region \(Int(region.minX)) \(Int(region.minY)) \(Int(region.width)) \(Int(region.height)) "
            + "\(Int(screen.frame.width)) \(Int(screen.frame.height))")

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

            await pause(1.0 * unit)
            step("end")
        }
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
