import AppKit

/// 浮窗演示，给 CI 截图用。
///
/// 环境变量 POP_DEMO=1 启动时不弹设置窗口，而是按固定的时间表依次展示：圆盘展开、读到内容、
/// 指向一格、滑到另一格、选中后弹出结果卡片、提示、「全部功能」列表、再展开一次圆盘并取消；
/// 再按真实的手势流程走一遍：按住右键唤起、拖到上面一格、再拖到「剪贴板」、松开执行
/// （直接调用鼠标拦截的回调，拖动位置和真实使用时一样由拦截送来，不看系统的指针位置）；
/// 最后是单位换算的卡片、贴图、AI 卡片、窗口布局卡片、翻译卡片、常用短语、文本对比、图片配色、暂存架、打开方式、
/// Markdown 预览、截图标注窗口、设置窗口里新加的几页和插件库。
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
        // 宽一些，放得下文本对比那样的宽卡片
        let cardRegion = CGRect(x: center.x - 190, y: center.y - 480, width: 760, height: 680)
        logRegion(cardRegion, screen: screen)
        // 插件包的演示步骤用
        let demo = PluginHost.DemoContext(screen: screen, center: center, overlay: overlay, cardRegion: cardRegion)

        let installed = Set(settings.installedPlugins)
        let text = ContentClassifier.classify(.text("Liquid glass"))
        let ring = RingViewModel(layout: settings.ring, catalog: catalog, installed: installed, content: nil)
        let chooserPlugins = catalog.filter { $0.id != BuiltinPluginID.allPlugins && installed.contains($0.id) && $0.canHandle(text) }
        let card = ResultCard(title: String(localized: "字数统计"), body: "", copyText: "12",
                              rows: [ResultCard.Row(label: String(localized: "字符"), value: "12"),
                                     ResultCard.Row(label: String(localized: "单词"), value: "2"),
                                     ResultCard.Row(label: String(localized: "行"), value: "1")])
        let unit = Motion.timeScale
        // 一步停多久再换下一步：截图脚本在每一步开始后最多 3 秒（放慢 6 倍时，也就是 0.5 × unit）拍照，
        // 拍完留一点余量就换，不多等。截图更晚的两步（「全部功能」列表、松开以后）单独写
        let holdTime = 0.5 * unit + 1.0

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
            overlay.showToast(String(localized: "已复制"), anchor: center)

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
            await pause(holdTime)
            step("pin")
            overlay.hide()
            PinBoard.shared.pin(text: "5 km ≈ 3.11 英里\n贴在屏幕上的文字，可以拖动、缩放", around: CGPoint(x: center.x + 40, y: center.y + 60))
            if let image = QRCode.generate("https://github.com/whrss9527/pop", scale: 6) {
                PinBoard.shared.pin(imageData: image, around: CGPoint(x: center.x + 260, y: center.y - 250))
            }

            await pause(holdTime)
            step("unpin")
            PinBoard.shared.closeAll()

            // AI 卡片（演示时没有设置接口，显示的是引导去设置的样子）
            await pause(1.0 * unit)
            step("ai")
            let assistant = AIChatModel(source: "Liquid glass", settings: settings, keyProvider: { nil })
            overlay.showCard(AICardView(model: assistant, canReplace: false, onAction: { _ in }, onMore: {},
                                        onOpenSettings: {}, onClose: {}),
                             anchor: center)

            // 插件包的步骤：窗口布局卡片
            await playPluginScenes(after: "ai", in: demo, unit: unit, holdTime: holdTime)

            // 翻译卡片（CI 上没有离线语言包，显示的是引导下载的样子），左上角可以换目标语言
            await pause(holdTime)
            step("translate")
            let translation = TranslationModel(text: "Liquid glass", sourceLanguage: "en", targetLanguage: "zh-Hans")
            overlay.showCard(TranslationCardView(model: translation, canReplace: false, onAction: { _ in }, onMore: {},
                                                 onDownload: {}, onClose: {}),
                             anchor: center)

            // 翻译对比：AI 和 DeepL 用演示的译文，系统翻译照常检查语言包
            await pause(holdTime)
            step("translate-compare")
            let comparison = TranslationModel(text: "Liquid glass reflects and refracts what is behind it, so every control feels alive.",
                                              sourceLanguage: "en", targetLanguage: "zh-Hans", services: demoTranslation)
            comparison.switchMode(to: .compare)
            overlay.showCard(TranslationCardView(model: comparison, canReplace: true, onAction: { _ in }, onMore: {},
                                                 onDownload: {}, onOpenSettings: { _ in }, onClose: {}),
                             anchor: center)

            // 常用短语列表
            await pause(holdTime)
            step("snippets")
            let snippets = SnippetPickerModel(snippets: settings.snippets + [
                Snippet(title: "回复模板", text: "感谢反馈！我们会在 {date} 前回复你。"),
                Snippet(title: "会议链接", text: "https://meet.example.com/pop-weekly"),
            ])
            overlay.showCard(SnippetPickerView(model: snippets, onClose: {}), anchor: center)

            // 文本对比卡片
            await pause(holdTime)
            step("diff")
            let diff = TextDiff.compare("长按右键唤起圆盘\n松开就执行\n支持 50 多个功能",
                                        "长按右键弹出圆盘\n松开就执行\n支持 60 多个功能\n还可以写自己的插件")
            overlay.showCard(ResultCardView(card: ResultCard(title: String(localized: "文本对比"),
                                                             detail: String(localized: "剪贴板 → 选中的文字：删去 \(diff.removedCount) 行，新增 \(diff.addedCount) 行"),
                                                             copyText: diff.unifiedText, diff: diff),
                                            onAction: { _ in }, onMore: {}, onClose: {}),
                             anchor: center)

            // 插件包的步骤：图片配色
            await playPluginScenes(after: "diff", in: demo, unit: unit, holdTime: holdTime)

            // 暂存架：放上几个示例文件
            await pause(holdTime)
            overlay.hide()
            let files = sampleFiles()
            FileShelf.shared.add(files)
            FileShelf.shared.show(near: CGPoint(x: center.x + 20, y: center.y - 20))
            step("shelf")

            // 打开方式卡片（示例文字文件能用哪些 App 打开）
            await pause(holdTime)
            FileShelf.shared.hide()
            FileShelf.shared.clear()
            if let note = files.first(where: { $0.pathExtension == "txt" }) {
                let request = OpenWithRequest(targets: [note], apps: OpenWith.applications(for: note))
                overlay.showCard(OpenWithCardView(request: request, onChoose: { _ in }, onClose: {}), anchor: center)
            }
            step("openWith")

            // Markdown 预览卡片（深色外观下文字也要看得清）
            await pause(holdTime)
            let markdown = "## 发布清单\n\n- 更新 **CHANGELOG**\n- 改 `MARKETING_VERSION`\n\n> 合并到 main 后自动发版"
            overlay.showCard(ResultCardView(card: ResultCard(title: String(localized: "Markdown 预览"), markdown: markdown,
                                                             buttons: [CardButton(title: String(localized: "复制为富文本"), action: .copyRichText(markdown))]),
                                            onAction: { _ in }, onMore: {}, onClose: {}),
                             anchor: center)
            step("markdown")

            // 提取信息卡片
            await pause(holdTime)
            let notice = "联系 pop@example.com，电话 138-1234-5678；下载 https://github.com/whrss9527/pop/releases，文档在 www.example.com；测试机 192.168.1.20:8080，备用 support@example.com"
            overlay.showCard(ResultCardView(card: InfoExtractor.card(for: InfoExtractor.extract(notice)),
                                            onAction: { _ in }, onMore: {}, onClose: {}),
                             anchor: center)
            step("extract")

            // 插件包的步骤：JSON 转代码
            await playPluginScenes(after: "extract", in: demo, unit: unit, holdTime: holdTime)

            // 网页内容转成 Markdown
            await pause(holdTime)
            let html = "<h2>发布说明</h2><p>这一版加了<strong>提取信息</strong>和<a href=\"https://github.com/whrss9527/pop\">JSON 转代码</a>。</p><ul><li>支持 <code>HTML</code> 和 RTF</li><li>表格也能转</li></ul><table><tr><th>功能</th><th>分类</th></tr><tr><td>按行处理</td><td>文字</td></tr></table>"
            if let converted = HTMLToMarkdown.convert(html) {
                overlay.showCard(ResultCardView(card: ResultCard(title: String(localized: "转成 Markdown"), body: converted, monospaced: true,
                                                                 copyText: converted),
                                                onAction: { _ in }, onMore: {}, onClose: {}),
                                 anchor: center)
            }
            step("toMarkdown")

            // 插件包的步骤：正则测试
            await playPluginScenes(after: "toMarkdown", in: demo, unit: unit, holdTime: holdTime)

            // 剪贴板历史：几条示例记录，⌘ 点选两条准备合在一起粘贴
            await pause(holdTime)
            if let history = sampleClipboardHistory() {
                overlay.showCard(ClipboardHistoryView(model: history, onClose: {}), anchor: center)
            }
            step("history")

            // 剪贴板历史按图片里的文字搜索：示例截图在本机识别出文字，搜「账户」能找到它
            await pause(holdTime)
            if let history = sampleClipboardHistory(marking: false), let capture = sampleScreenshot() {
                let store = history.service.store
                if let id = store.add(ClipboardCapture(kind: .image, text: "", imagePNG: capture.png)) {
                    await runInBackground { ClipboardImageIndex.index(png: capture.png, id: id, store: store) }
                }
                history.query = "账户"
                overlay.showCard(ClipboardHistoryView(model: history, onClose: {}), anchor: center)
            }
            step("history-search")

            // 插件包的步骤：加到提醒事项、识别表格
            await playPluginScenes(after: "history-search", in: demo, unit: unit, holdTime: holdTime)

            // 文件信息：一张带拍摄信息和位置的示例照片，可以在地图里看、另存去掉位置的一份
            await pause(holdTime)
            if let photo = samplePhoto(),
               case .card(let photoCard) = await FileInfoPlugin().run(ContentClassifier.classify(.files([photo])),
                                                                      context: PluginContext(settings: AppSettings(), openSettings: {})) {
                overlay.showCard(ResultCardView(card: photoCard, onAction: { _ in }, onMore: {}, onClose: {}), anchor: center)
            }
            step("photo")

            // 插件包的步骤：批量重命名、SQL 格式化
            await playPluginScenes(after: "photo", in: demo, unit: unit, holdTime: holdTime)

            // 生词本：几个示例单词（放在临时文件里，不动真的生词本）
            await pause(holdTime)
            let words = VocabularyStore(url: FileManager.default.temporaryDirectory.appending(path: "pop-demo-vocabulary.json"))
            words.remove(Set(words.entries.map(\.id)))
            for (word, meaning) in [("resilient", "有韧性的；能迅速恢复的"), ("liquid glass", "液态玻璃"), ("ephemeral", "短暂的"),
                                    ("serendipity", "意外发现美好事物的运气")] {
                words.add(word: word, translation: meaning, sourceLanguage: "en", targetLanguage: "zh-Hans")
            }
            if let oldest = words.entries.last {
                words.setMastered(oldest.id, true)
            }
            overlay.showCard(VocabularyView(model: VocabularyModel(store: words), onCopy: { _ in }, onSpeak: { _ in },
                                            onExport: { _ in }, onClose: {}),
                             anchor: center)
            step("vocabulary")

            // 插件包的步骤：查找重复文件
            await playPluginScenes(after: "vocabulary", in: demo, unit: unit, holdTime: holdTime)

            // PDF 页面：一份 12 页的 PDF，写好了要取出的页码（卡片只用到文件名和页数）
            await pause(holdTime)
            let pdfPages = PDFPagesModel(pdf: FileManager.default.temporaryDirectory.appending(path: "产品手册.pdf"), pageCount: 12)
            pdfPages.input = "1-3, 5, 8-"
            overlay.showCard(PDFPagesView(model: pdfPages, onExtract: { _ in }, onSplit: {}, onClose: {}), anchor: center)
            step("pdfPages")

            // 插件包的步骤：占用空间
            await playPluginScenes(after: "pdfPages", in: demo, unit: unit, holdTime: holdTime)

            // 给 PDF 加密码：两次输入的密码一样
            await pause(holdTime)
            let password = PDFPasswordModel(pdf: FileManager.default.temporaryDirectory.appending(path: "合同.pdf"), mode: .add)
            password.password = "pop-2026"
            password.confirmation = "pop-2026"
            overlay.showCard(PDFPasswordView(model: password, onSubmit: { _ in }, onClose: {}), anchor: center)
            step("pdfPassword")

            // 选中文字后的工具条：假装在圆盘的位置选中了一段英文
            await pause(holdTime)
            overlay.hide()
            coordinator.showToolbarForDemo(text: "Liquid glass", selection: CGRect(x: center.x - 50, y: center.y - 20, width: 100, height: 18))
            step("toolbar")
            await pause(holdTime)
            coordinator.hideToolbar()

            // 插件包的步骤：加水印
            await playPluginScenes(after: "toolbar", in: demo, unit: unit, holdTime: holdTime)

            // 传到手机：二维码和能下载的文件（演示时不开网页服务，网址是示例）
            await pause(holdTime)
            if let address = URL(string: "http://192.168.1.23:52731/k7m2p9qx4t/") {
                overlay.showCard(ResultCardView(card: PhoneShare.card(address: address, files: sampleFiles()),
                                                onAction: { _ in }, onMore: {}, onClose: {}),
                                 anchor: center)
            }
            step("sendToPhone")

            // 证件号码：国家标准里的示例身份证号
            await pause(holdTime)
            if let info = IDNumber.parse("11010519491231002X") {
                overlay.showCard(ResultCardView(card: IDNumber.card(info), onAction: { _ in }, onMore: {}, onClose: {}), anchor: center)
            }
            step("idNumber")

            // 语音转文字的结果：示例录音的文字和字幕
            await pause(holdTime)
            let meeting = FileManager.default.temporaryDirectory.appending(path: "pop-demo/周会录音.m4a")
            let spoken: [(String, TimeInterval, TimeInterval)] = [("大家好", 0.4, 0.8), ("。", 1.2, 0.1), ("今天先确认", 1.6, 1.0),
                                                                   ("发布时间", 2.6, 0.8), ("，", 3.4, 0.1), ("再看一下截图", 3.6, 1.2),
                                                                   ("。", 4.8, 0.1)]
            let transcript = Transcriber.Transcript(text: "大家好。今天先确认发布时间，再看一下截图。",
                                                    segments: spoken.map { Transcriber.Segment(text: $0.0, start: $0.1, duration: $0.2) },
                                                    onDevice: true)
            overlay.showCard(ResultCardView(card: Transcriber.card(transcript, file: meeting, language: "zh-CN"),
                                            onAction: { _ in }, onMore: {}, onClose: {}),
                             anchor: center)
            step("transcribe")

            // 证件照：画一个简单的人像，换成蓝底一寸
            await pause(holdTime)
            if let portrait = samplePortrait() {
                let photo = FileManager.default.temporaryDirectory.appending(path: "pop-demo/证件照.jpg")
                overlay.showCard(IDPhotoView(model: IDPhotoModel(file: photo, cutout: portrait), onSave: {}, onClose: {}), anchor: center)
            }
            step("idPhoto")

            // 网页存档：选中一个网址
            await pause(holdTime)
            if let page = URL(string: "https://github.com/whrss9527/pop/releases") {
                overlay.showCard(ResultCardView(card: WebCapture.card(page), onAction: { _ in }, onMore: {}, onClose: {}),
                                 anchor: center)
            }
            step("webCapture")

            // 裁剪图片：五种比例
            await pause(holdTime)
            let beach = FileManager.default.temporaryDirectory.appending(path: "pop-demo/海边.jpg")
            overlay.showCard(ResultCardView(card: SmartCrop.card([beach]), onAction: { _ in }, onMore: {}, onClose: {}),
                             anchor: center)
            step("cropImage")

            // 插件包的步骤：截图美化
            await playPluginScenes(after: "cropImage", in: demo, unit: unit, holdTime: holdTime)

            // 录屏：先是选区域的界面（截屏幕上方的提示条），再是倒数，然后是录的时候的边框、控制面板和按键显示，最后是录好的卡片
            await pause(holdTime)
            overlay.hide()
            Task { @MainActor in
                _ = await RegionPicker.pick()
            }
            await pause(0.4 * unit)
            logRegion(CGRect(x: screen.frame.midX - 380, y: screen.frame.maxY - 300, width: 760, height: 300), screen: screen)
            step("screenRecord-picker")
            await pause(holdTime)
            RegionPicker.cancel()
            logRegion(cardRegion, screen: screen)
            let recordRegion = CGRect(x: center.x - 150, y: center.y - 380, width: 560, height: 320)
            // 选好区域以后的倒数
            let hideCountdown = RecordingCountdown.showForDemo(value: 3, in: recordRegion)
            step("screenRecord-countdown")
            await pause(1.0 * unit)
            hideCountdown()
            let hideIndicators = ScreenRecorder.shared.showIndicatorsForDemo(region: recordRegion, screen: screen, elapsed: "00:12")
            KeystrokeOverlay.shared.showForDemo("⌘Z ×3", in: recordRegion)
            step("screenRecord-recording")
            await pause(holdTime)
            hideIndicators()
            KeystrokeOverlay.shared.stop()
            let clip = ScreenRecording.Clip(url: FileManager.default.temporaryDirectory.appending(path: "pop-demo/录屏 2026-09-30 15.30.12.mp4"),
                                            duration: 12, width: 1280, height: 720)
            overlay.showCard(ResultCardView(card: ScreenRecording.card(clip), onAction: { _ in }, onMore: {}, onClose: {}), anchor: center)
            step("screenRecord")

            // 系统操作：插着一个移动硬盘时的样子
            await pause(holdTime)
            overlay.showCard(ResultCardView(card: SystemActions.card(desktopIconsVisible: true, darkMode: false, ejectable: 1),
                                            onAction: { _ in }, onMore: {}, onClose: {}),
                             anchor: center)
            step("systemActions")

            // 文字转图片：一段示例文字排成的长图
            await pause(holdTime)
            let passage = "周五的发布会改到下午三点，地点不变。\n\n会前请把演示用的 Mac 更新到最新系统，提前半小时到场调试投屏。"
            if case .card(let textCard) = TextImage.outcome(passage, style: .warm) {
                overlay.showCard(ResultCardView(card: textCard, onAction: { _ in }, onMore: {}, onClose: {}), anchor: center)
            }
            step("textImage")

            // 插件包的步骤：快捷键一览
            await playPluginScenes(after: "textImage", in: demo, unit: unit, holdTime: holdTime)

            // 滚动截图：截的时候的边框和面板，然后是拼好的长图卡片（示例长图用文字转图片画一篇长文）
            await pause(holdTime)
            overlay.hide()
            let hideScrollIndicators = ScrollCapture.shared.showIndicatorsForDemo(
                region: CGRect(x: center.x - 150, y: center.y - 380, width: 560, height: 320), screen: screen,
                progress: ScrollCaptureProgress(height: 4280, frameHeight: 640))
            step("scrollCapture-capturing")
            await pause(holdTime)
            hideScrollIndicators()
            let article = (1...6).map { "第 \($0) 段：长按右键弹出圆盘，往一个方向划一下再松开，就能翻译、搜索、识别文字、截图。选中文件时换成处理文件的功能。" }
                .joined(separator: "\n\n")
            if let png = TextImage.render(article), let image = TextRecognizer.cgImage(from: png),
               let scrollCard = ScrollStitcher.card(image, frameHeight: 640) {
                overlay.showCard(ResultCardView(card: scrollCard, onAction: { _ in }, onMore: {}, onClose: {}), anchor: center)
            }
            step("scrollCapture")

            // 装载的插件包加的步骤：屏幕画笔、摄像头小窗、突出显示指针、提词器……
            await pause(holdTime)
            overlay.hide()
            await playPluginScenes(after: "scrollCapture", in: demo, unit: unit, holdTime: holdTime)

            // 截图标注窗口：拿一张画好的示例图，标上方框、箭头、文字、马赛克和序号；截图区域换成标注窗口
            await pause(holdTime)
            overlay.hide()
            if let capture = sampleScreenshot() {
                let annotation = AnnotationWindowController.present(capture, near: center)
                annotateSample(annotation)
                await pause(0.3 * unit)
                if let window = NSApp.windows.first(where: { $0.isVisible && $0.title == String(localized: "截图标注") }) {
                    logRegion(window.frame, screen: screen)
                }
            }
            step("annotate")
            await pause(holdTime)
            NSApp.windows.first { $0.isVisible && $0.title == String(localized: "截图标注") }?.close()

            // 设置窗口里新加的几页：截图区域换成设置窗口
            await pause(0.6 * unit)
            for tab in [SettingsTab.plugins, .ai, .hotKeys] {
                coordinator.openSettings(tab)
                await pause(0.6 * unit)
                if let window = NSApp.windows.first(where: { $0.isVisible && $0.title == String(localized: "Pop 设置") }) {
                    logRegion(window.frame, screen: screen)
                }
                step("settings-\(tab.rawValue)")
                await pause(0.8 * unit)
            }

            // 插件库：截图脚本用 POP_PLUGIN_INDEX_URL 指向仓库里的 plugins/index.json，不联网
            coordinator.openPluginLibrary()
            await pause(1.0 * unit)
            if let window = NSApp.windows.first(where: { $0.isVisible && $0.title == String(localized: "Pop 设置") }) {
                logRegion(window.frame, screen: screen)
            }
            step("settings-pluginLibrary")
            await pause(0.8 * unit)

            step("end")
        }
    }

    /// 翻译对比演示用的引擎：AI 和 DeepL 直接给出写好的译文，不联网
    private static var demoTranslation: TranslationServices {
        TranslationServices(
            unavailableReason: { _ in nil },
            translate: { engine, _, _ in
                let translated = engine == .ai
                    ? "液态玻璃会映出并折射身后的内容，让每个控件都显得生动。"
                    : "液态玻璃反射和折射其背后的东西，因此每个控件都感觉栩栩如生。"
                return AsyncThrowingStream { continuation in
                    continuation.yield(translated)
                    continuation.finish()
                }
            },
            checkSystem: { text, source, target in
                await SystemTranslation.status(text: text, source: source, target: target)
            }
        )
    }

    /// 剪贴板历史演示：放在临时文件夹里的几条示例记录，不碰真的历史；⌘ 点选了其中两条
    private static func sampleClipboardHistory(marking: Bool = true) -> ClipboardHistoryModel? {
        let directory = FileManager.default.temporaryDirectory.appending(path: "pop-demo-history", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: directory)
        let store = ClipboardStore(directory: directory)
        guard store.isAvailable else { return nil }
        let now = Date()
        let samples = ["SELECT * FROM orders WHERE id IN (1001, 1002, 1003);", "https://github.com/whrss9527/pop/releases",
                       "会议改到周五下午三点", "pop@example.com", "长按右键唤起圆盘，松开就执行"]
        for (offset, text) in samples.enumerated() {
            _ = store.add(ClipboardCapture(kind: .text, text: text), at: now.addingTimeInterval(Double(offset - samples.count) * 90))
        }
        let model = ClipboardHistoryModel(service: ClipboardService(store: store))
        for item in model.items where marking && (item.text.hasPrefix("会议") || item.text.hasPrefix("pop@")) {
            model.toggleMark(item)
        }
        return model
    }

    /// 标注演示用的「截图」：一张账户设置卡片，480×300 点，像素按屏幕倍率（和真的截图一样）；插件包的演示步骤也用
    static func sampleScreenshot() -> ScreenCapture.Capture? {
        let scale = max(NSScreen.main?.backingScaleFactor ?? 2, 1)
        let width = Int(480 * scale)
        let height = Int(300 * scale)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // 换成「点、左上角为原点」的坐标
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
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

    /// 暂存架演示用的几个文件：一个 PDF、一张图、一个文字文件（放在临时文件夹里）
    /// 演示用的人像：透明背景上画肩膀、脖子、头发和脸（Core Graphics 的原点在左下角）
    private static func samplePortrait() -> IDPhoto.Cutout? {
        guard let context = CGContext(data: nil, width: 600, height: 800, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(CGColor(srgbRed: 0.16, green: 0.2, blue: 0.3, alpha: 1))
        context.fillEllipse(in: CGRect(x: 90, y: -220, width: 420, height: 420))
        context.setFillColor(CGColor(srgbRed: 0.93, green: 0.78, blue: 0.66, alpha: 1))
        context.fill(CGRect(x: 262, y: 170, width: 76, height: 90))
        context.setFillColor(CGColor(srgbRed: 0.12, green: 0.1, blue: 0.09, alpha: 1))
        context.fillEllipse(in: CGRect(x: 195, y: 300, width: 210, height: 260))
        context.setFillColor(CGColor(srgbRed: 0.95, green: 0.8, blue: 0.68, alpha: 1))
        context.fillEllipse(in: CGRect(x: 212, y: 250, width: 176, height: 230))
        guard let image = context.makeImage() else { return nil }
        // 脸的位置（左上角为原点）
        return IDPhoto.Cutout(image: image, face: CGRect(x: 215, y: 330, width: 170, height: 190))
    }

    /// 摄像头小窗演示用的画面：浅色渐变的背景上的示例人像；插件包的演示步骤也用
    static func sampleCameraFrame() -> CGImage? {
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let portrait = samplePortrait(),
              let context = CGContext(data: nil, width: 600, height: 600, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let colors = [CGColor(srgbRed: 0.78, green: 0.85, blue: 0.95, alpha: 1), CGColor(srgbRed: 0.94, green: 0.88, blue: 0.83, alpha: 1)]
        if let gradient = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: [0, 1]) {
            context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 600), end: CGPoint(x: 600, y: 0), options: [])
        }
        // 人像是 600×800，下移一点让脸在中间
        context.draw(portrait.image, in: CGRect(x: 0, y: -40, width: 600, height: 800))
        return context.makeImage()
    }

    static func sampleFiles() -> [URL] {
        let folder = FileManager.default.temporaryDirectory.appending(path: "pop-demo")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var files: [URL] = []
        if let capture = sampleScreenshot() {
            let image = folder.appending(path: "界面截图.png")
            if (try? capture.png.write(to: image)) != nil {
                let pdf = folder.appending(path: "季度报告.pdf")
                if (try? PDFTools.combine([image], into: pdf)) != nil {
                    files.append(pdf)
                }
                files.append(image)
            }
        }
        let note = folder.appending(path: "会议记录.txt")
        if (try? Data("周一例会：确认发布时间。\n".utf8).write(to: note)) != nil {
            files.append(note)
        }
        return files
    }

    /// 查找重复文件演示：临时文件夹里三份一样的照片、两份一样的报告，再加两个不重复的
    static func sampleDuplicates() -> URL? {
        let root = FileManager.default.temporaryDirectory.appending(path: "pop-demo-duplicates/资料", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: root)
        let photo = Data(repeating: 7, count: 2_400_000)
        let report = Data(repeating: 9, count: 860_000)
        let files: [(path: String, data: Data)] = [
            ("旅行照片/IMG_2041.jpg", photo), ("下载/IMG_2041 (1).jpg", photo), ("桌面/IMG_2041 副本.jpg", photo),
            ("文稿/季度报告.pdf", report), ("下载/季度报告 最终版.pdf", report),
            ("文稿/会议记录.txt", Data("周一例会：确认发布时间。\n".utf8)), ("下载/安装包.dmg", Data(repeating: 3, count: 1_200_000)),
        ]
        for (offset, file) in files.enumerated() {
            let url = root.appending(path: file.path)
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard (try? file.data.write(to: url)) != nil else { return nil }
            // 按列出的顺序一个比一个晚创建，每组留下的是排在前面的那个
            try? FileManager.default.setAttributes([.creationDate: Date(timeIntervalSinceNow: Double(offset - files.count) * 86_400)],
                                                   ofItemAtPath: url.path(percentEncoded: false))
        }
        return root
    }

    /// 在示例图上标几笔：给手机号打码、序号、框出按钮、箭头指过去再写一句话，再加上渐变背景
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
        model.background = .sky
    }

    /// 插件包注册的演示步骤：按顺序一个个显示、记下截图区域、停一会儿再收起。最多停到截图拍完（holdTime）
    private static func playPluginScenes(after step: String, in context: PluginHost.DemoContext, unit: Double, holdTime: Double) async {
        // 上一步（主流程那一步，或者 hold 为 0、留在屏幕上等下一步换掉的卡片）靠这段等待撑到拍照，要等满 holdTime；
        // 上一个插件步骤自己已经停够了的话，只等它收起的动画（Motion.exitDuration，0.17 × unit）走完
        var previousHeld = false
        for scene in PluginHost.shared.demoScenes(after: step) {
            await pause(min(scene.delay * unit, previousHeld ? 0.25 * unit : holdTime))
            if let region = await scene.show(context) {
                logRegion(region == context.cardRegion ? region : region.insetBy(dx: -24, dy: -24), screen: context.screen)
            }
            Self.step(scene.name)
            await pause(min(scene.hold * unit, holdTime))
            scene.hide()
            previousHeld = scene.hold * unit >= holdTime
        }
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
