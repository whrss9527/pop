import AppKit

/// 浮窗演示，给 CI 截图用。
///
/// 环境变量 POP_DEMO=1 启动时不弹设置窗口，而是按固定的时间表依次展示：圆盘展开、读到内容、
/// 指向一格、滑到另一格、选中后弹出结果卡片、提示、「全部功能」列表，最后再展开一次圆盘并取消。
/// 配合 POP_ANIMATION_SCALE 放慢动画，截图脚本就能拍到动画的中间帧。
/// 每一步开始时往 POP_DEMO_LOG 指定的文件里写一行「步骤名 时间戳」；第一行是演示区域在屏幕上的位置
/// （点，AppKit 坐标：x y 宽 高）和屏幕大小，脚本按它裁图。
@MainActor
enum OverlayDemo {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["POP_DEMO"] == "1"
    }

    static func run(overlay: OverlayController, catalog: [PluginInfo], settings: AppSettings) {
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

            await pause(0.8 * unit)
            step("end")
        }
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
