import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import Vision

// MARK: - 文字识别

enum TextRecognizer {
    static func cgImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    static func cgImage(contentsOf url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// 用 Vision 离线识别图片里的文字（中英日韩），按行返回。
    static func recognize(_ image: CGImage) async -> Result<String, PluginRunError> {
        await runInBackground {
            do {
                return .success(try recognizeLines(in: image))
            } catch {
                return .failure(PluginRunError("文字识别失败：\(error.localizedDescription)"))
            }
        }
    }

    /// 同步识别，在后台线程里调用
    static func recognizeLines(in image: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US", "ja-JP", "ko-KR"]
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        return lines.joined(separator: "\n")
    }

    /// 识别结果卡片：可以复制，也可以接着翻译。
    static func card(title: String, text: String) -> ResultCard {
        var buttons = [CardButton(title: "翻译", action: .translate(text))]
        // 识别出来的文字按图片里的样子断行，接成整段更好贴进文档
        if let joined = TextCleanup.joinLines(text), joined != text {
            buttons.append(CardButton(title: "合并换行后复制", action: .copy(joined)))
        }
        return ResultCard(title: title, body: text, copyText: text, buttons: buttons)
    }
}

struct OCRPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.ocr, name: "识别文字", symbol: "text.viewfinder",
                          summary: "识别选中图片里的文字（离线）", accepts: [.image, .imageFile])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        let image: CGImage?
        if case .image(let data) = content.selection {
            image = TextRecognizer.cgImage(from: data)
        } else if let url = content.files.first {
            image = TextRecognizer.cgImage(contentsOf: url)
        } else {
            image = nil
        }
        guard let image else { return .failure("无法读取图片") }
        switch await TextRecognizer.recognize(image) {
        case .success(let text):
            guard !text.isEmpty else { return .failure("图片里没有识别到文字") }
            return .card(TextRecognizer.card(title: "识别文字", text: text))
        case .failure(let error):
            return .failure(error.message)
        }
    }
}

// MARK: - 截图

/// 系统截图：框选屏幕上的一块区域（按空格键可以改成选窗口），按 Esc 取消。
@MainActor
enum ScreenCapture {
    struct Capture {
        let image: CGImage
        /// 截图文件的 PNG 数据，复制、存储时直接用
        let png: Data
    }

    enum Outcome {
        case cancelled
        case captured(Capture)
        case failed(String)
    }

    enum TextOutcome {
        case cancelled
        case text(String)
        case failed(String)
    }

    static let noTextHint = "没有识别到文字。如果截到的只有桌面背景，请在「系统设置 → 隐私与安全性 → 录屏与系统录音」里允许 Pop。"

    static func selectRegion() async -> Outcome {
        if !CGPreflightScreenCaptureAccess() {
            // 第一次会弹出系统的授权提示；没授权时截图里可能只有桌面背景
            _ = CGRequestScreenCaptureAccess()
        }
        let url = FileManager.default.temporaryDirectory.appending(path: "pop-screenshot-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }
        let result = await ProcessRunner.run(URL(fileURLWithPath: "/usr/sbin/screencapture"),
                                             arguments: ["-i", "-x", url.path(percentEncoded: false)],
                                             stdin: nil, environment: [:], timeout: 300)
        if case .failure(let error) = result {
            return .failed(error.message)
        }
        // 按 Esc 取消了截图：没有生成文件
        guard let png = try? Data(contentsOf: url) else { return .cancelled }
        guard let image = TextRecognizer.cgImage(from: png) else { return .failed("无法读取截图") }
        return .captured(Capture(image: image, png: png))
    }

    /// 框选一块屏幕，识别里面的文字
    static func recognizeRegion() async -> TextOutcome {
        switch await selectRegion() {
        case .cancelled:
            return .cancelled
        case .failed(let message):
            return .failed(message)
        case .captured(let capture):
            switch await TextRecognizer.recognize(capture.image) {
            case .success(let text):
                return text.isEmpty ? .failed(noTextHint) : .text(text)
            case .failure(let error):
                return .failed(error.message)
            }
        }
    }
}

struct ScreenshotOCRPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.screenshotOCR, name: "截图识字", symbol: "viewfinder",
                          summary: "框选屏幕上的一块区域，识别里面的文字", accepts: [], hidesOverlay: true)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        switch await ScreenCapture.recognizeRegion() {
        case .cancelled:
            return .done(toast: nil)
        case .failed(let message):
            return .failure(message)
        case .text(let text):
            return .card(TextRecognizer.card(title: "截图识字", text: text))
        }
    }
}

struct ScreenshotTranslatePlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.screenshotTranslate, name: "截图翻译", symbol: "translate",
                          summary: "框选屏幕上的一块区域，识别里面的文字并翻译（离线）", accepts: [], hidesOverlay: true)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        switch await ScreenCapture.recognizeRegion() {
        case .cancelled:
            return .done(toast: nil)
        case .failed(let message):
            return .failure(message)
        case .text(let text):
            // 识别结果按屏幕上的行断开，先接成段落再翻译，译文才通顺
            let paragraphs = TextCleanup.joinLines(text) ?? text
            return .translate(text: paragraphs, language: ContentClassifier.dominantLanguage(paragraphs))
        }
    }
}

// MARK: - 截图标注

struct AnnotatePlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.annotate, name: "截图标注", symbol: "pencil.and.outline",
                          summary: "框选屏幕上的一块区域（或者用选中的图片），画箭头、方框、文字、马赛克、序号，再复制、存储或贴到屏幕上",
                          accepts: [], hidesOverlay: true, optionalContent: true)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        let anchor = context.anchor ?? NSEvent.mouseLocation
        // 选中了图片：直接标注这张图
        var data: Data?
        if case .image(let image) = content.selection {
            data = image
        } else if content.kinds.contains(.imageFile), let url = content.files.first {
            data = try? Data(contentsOf: url)
        }
        if let data {
            guard let image = TextRecognizer.cgImage(from: data) else { return .failure("无法读取图片") }
            AnnotationWindowController.present(ScreenCapture.Capture(image: image, png: data), near: anchor)
            return .done(toast: nil)
        }
        switch await ScreenCapture.selectRegion() {
        case .cancelled:
            return .done(toast: nil)
        case .failed(let message):
            return .failure(message)
        case .captured(let capture):
            AnnotationWindowController.present(capture, near: NSEvent.mouseLocation)
            return .done(toast: nil)
        }
    }
}

// MARK: - 贴图

struct PinPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.pin, name: "贴图", symbol: "pin",
                          summary: "把选中的图片或文字贴在屏幕最前面；什么都没选中时先框选一块屏幕", accepts: [],
                          hidesOverlay: true, optionalContent: true)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        let board = PinBoard.shared
        let anchor = context.anchor ?? NSEvent.mouseLocation
        if case .image(let data) = content.selection {
            return board.pin(imageData: data, around: anchor) ? .done(toast: nil) : .failure("无法读取图片")
        }
        if content.kinds.contains(.imageFile) {
            // 选中了几张图片：错开一点依次贴出来
            var pinned = 0
            for (index, url) in content.files.prefix(5).enumerated() {
                let offset = CGFloat(index) * 28
                if let data = try? Data(contentsOf: url),
                   board.pin(imageData: data, around: CGPoint(x: anchor.x + offset, y: anchor.y - offset)) {
                    pinned += 1
                }
            }
            return pinned > 0 ? .done(toast: nil) : .failure("无法读取图片")
        }
        if let text = content.text {
            board.pin(text: text, around: anchor)
            return .done(toast: nil)
        }
        // 什么都没选中（或者选中的不是图片文件）：先框选一块屏幕
        switch await ScreenCapture.selectRegion() {
        case .cancelled:
            return .done(toast: nil)
        case .failed(let message):
            return .failure(message)
        case .captured(let capture):
            board.pin(capture: capture, releasedAt: NSEvent.mouseLocation)
            return .done(toast: nil)
        }
    }
}

// MARK: - 抠图

enum SubjectLifter {
    /// 用 Vision 离线抠出图片里的主体（人、动物、物品），返回透明背景的 PNG。
    static func lift(_ image: CGImage) async -> Result<Data, PluginRunError> {
        await runInBackground {
            let request = VNGenerateForegroundInstanceMaskRequest()
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
                guard let observation = request.results?.first, !observation.allInstances.isEmpty else {
                    return .failure(PluginRunError("图片里没有找到可以抠出来的主体"))
                }
                let buffer = try observation.generateMaskedImage(ofInstances: observation.allInstances, from: handler,
                                                                 croppedToInstancesExtent: true)
                let output = CIImage(cvPixelBuffer: buffer)
                guard let cgImage = CIContext().createCGImage(output, from: output.extent),
                      let png = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) else {
                    return .failure(PluginRunError("无法生成抠好的图片"))
                }
                return .success(png)
            } catch {
                return .failure(PluginRunError("抠图失败：\(error.localizedDescription)"))
            }
        }
    }
}

struct RemoveBackgroundPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.removeBackground, name: "抠图", symbol: "wand.and.stars",
                          summary: "去掉选中图片的背景，只留下人、动物或物品（离线）", accepts: [.image, .imageFile])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        let image: CGImage?
        var name = ImageFiles.timestampedName("Pop 抠图")
        if case .image(let data) = content.selection {
            image = TextRecognizer.cgImage(from: data)
        } else if let url = content.files.first {
            image = TextRecognizer.cgImage(contentsOf: url)
            name = url.deletingPathExtension().lastPathComponent + " 抠图"
        } else {
            image = nil
        }
        guard let image else { return .failure("无法读取图片") }
        switch await SubjectLifter.lift(image) {
        case .success(let png):
            return .card(ResultCard(title: "抠图", detail: "背景已去掉，复制或存储的 PNG 保留透明", image: png,
                                    buttons: [CardButton(title: "复制图片", action: .copyImage(png)),
                                              CardButton(title: "存到「下载」", action: .saveImage(png, name: name)),
                                              CardButton(title: "贴到屏幕", action: .pinImage(png))]))
        case .failure(let error):
            return .failure(error.message)
        }
    }
}

/// 图片存到「下载」文件夹
enum ImageFiles {
    /// 同名文件已经存在时在后面加 2、3……
    static func saveToDownloads(_ png: Data, name: String) throws -> URL {
        let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: "Downloads")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let safeName = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: ".")
        var url = folder.appending(path: safeName + ".png")
        var counter = 2
        while FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            url = folder.appending(path: "\(safeName) \(counter).png")
            counter += 1
        }
        try png.write(to: url, options: .atomic)
        return url
    }

    /// 「前缀 2026-09-29 10.30.15」
    static func timestampedName(_ prefix: String, date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return "\(prefix) \(formatter.string(from: date))"
    }
}

// MARK: - 隔空投送

struct AirDropPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.airDrop, name: "隔空投送", symbol: "dot.radiowaves.left.and.right",
                          summary: "用隔空投送把选中的文件、图片、链接或文字发到附近的 iPhone、iPad 或 Mac",
                          accepts: [.text, .files, .image])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        let items: [Any]
        if !content.files.isEmpty {
            items = content.files
        } else if case .image(let data) = content.selection, let image = NSImage(data: data) {
            items = [image]
        } else if let url = content.url {
            items = [url]
        } else if let text = content.text {
            items = [text]
        } else {
            return .failure("没有可以发送的内容")
        }
        guard let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: items) else {
            return .failure("现在用不了隔空投送。请确认无线局域网和蓝牙都已打开，「隔空投送」没有被关闭。")
        }
        // 隔空投送的窗口要显示在最前面
        NSApp.activate()
        service.perform(withItems: items)
        return .done(toast: nil)
    }
}

// MARK: - 取色

extension ColorValue {
    init?(_ color: NSColor) {
        guard let rgb = color.usingColorSpace(.sRGB) else { return nil }
        self.init(red: rgb.redComponent * 255, green: rgb.greenComponent * 255, blue: rgb.blueComponent * 255,
                  alpha: rgb.alphaComponent)
    }
}

@MainActor
enum ScreenColorSampler {
    enum Outcome {
        case cancelled
        /// 取到了颜色；nil 表示无法转换成 sRGB
        case picked(ColorValue?)
    }

    /// 显示系统的取色放大镜，按 Esc 取消。
    static func pick() async -> Outcome {
        let sampler = NSColorSampler()
        let result = await withCheckedContinuation { (continuation: CheckedContinuation<Outcome, Never>) in
            sampler.show { color in
                let outcome: Outcome
                if let color {
                    outcome = .picked(ColorValue(color))
                } else {
                    outcome = .cancelled
                }
                continuation.resume(returning: outcome)
            }
        }
        // 取色结束前 sampler 不能被释放
        withExtendedLifetime(sampler) {}
        return result
    }
}

struct ColorPickerPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.colorPicker, name: "屏幕取色", symbol: "eyedropper",
                          summary: "吸取屏幕上任意位置的颜色，自动复制 HEX 值", accepts: [], hidesOverlay: true)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard case .picked(let picked) = await ScreenColorSampler.pick() else { return .done(toast: nil) }
        guard let color = picked else { return .failure("无法读取这个颜色") }
        PasteboardWriter.copy(color.hexString)
        return .card(ResultCard(title: "屏幕取色", detail: "已复制 \(color.hexString)",
                                rows: color.rows, rowsReplaceable: true, swatchHex: color.hexString))
    }
}

// MARK: - 二维码

enum QRCode {
    /// 生成二维码 PNG；内容太长放不下时返回 nil。
    static func generate(_ text: String, scale: CGFloat = 8) -> Data? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cgImage = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
    }

    /// 识别图片里的二维码和条形码（Vision 认不出来时再用 Core Image 找一遍二维码），同样的内容只留一个
    static func decode(_ image: CGImage) -> [String] {
        let request = VNDetectBarcodesRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        var messages: [String] = []
        if (try? handler.perform([request])) != nil {
            messages = (request.results ?? []).compactMap(\.payloadStringValue)
        }
        if messages.isEmpty {
            let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
            let features = detector?.features(in: CIImage(cgImage: image)) ?? []
            messages = features.compactMap { ($0 as? CIQRCodeFeature)?.messageString }
        }
        var seen = Set<String>()
        return messages.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// 识别结果的卡片：Wi-Fi 二维码列出网络名和密码，链接可以直接打开
    static func card(for messages: [String]) -> ResultCard {
        let text = messages.joined(separator: "\n")
        if messages.count == 1, let network = WiFiCode.parse(text) {
            var rows = [ResultCard.Row(label: "网络名称", value: network.ssid)]
            if let password = network.password {
                rows.append(ResultCard.Row(label: "密码", value: password))
            }
            rows.append(ResultCard.Row(label: "加密方式", value: network.security ?? "无（开放网络）"))
            return ResultCard(title: "Wi-Fi 二维码", detail: network.hidden ? "这是一个隐藏的网络" : nil, rows: rows)
        }
        var buttons: [CardButton] = []
        if messages.count == 1, let url = URL(string: text), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) {
            buttons.append(CardButton(title: "打开链接", action: .open(url)))
        }
        return ResultCard(title: "扫码结果", body: text, detail: messages.count > 1 ? "找到 \(messages.count) 个码" : nil,
                          copyText: text, buttons: buttons)
    }
}

struct QRCodePlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.qrCode, name: "二维码", symbol: "qrcode",
                          summary: "把文字或链接生成二维码；选中图片时识别里面的二维码和条形码", accepts: [.text, .image, .imageFile])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        if content.kinds.contains(.image) || content.kinds.contains(.imageFile) {
            return decode(content)
        }
        guard let text = content.text else { return .failure("没有内容") }
        guard let png = await runInBackground({ QRCode.generate(text) }) else {
            return .failure("内容太长，放不进一个二维码")
        }
        return .card(ResultCard(title: "二维码", detail: "\(text.count) 个字符", image: png,
                                buttons: [CardButton(title: "复制图片", action: .copyImage(png))]))
    }

    @MainActor private func decode(_ content: ClassifiedContent) -> PluginOutcome {
        let image: CGImage?
        if case .image(let data) = content.selection {
            image = TextRecognizer.cgImage(from: data)
        } else {
            image = content.files.first.flatMap(TextRecognizer.cgImage(contentsOf:))
        }
        guard let image else { return .failure("无法读取图片") }
        let messages = QRCode.decode(image)
        guard !messages.isEmpty else { return .failure("图片里没有找到二维码或条形码") }
        return .card(QRCode.card(for: messages))
    }
}

struct ScanCodePlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.scanCode, name: "扫码", symbol: "qrcode.viewfinder",
                          summary: "框选屏幕上的二维码或条形码，识别里面的内容；链接可以直接打开，Wi-Fi 二维码列出密码",
                          accepts: [], hidesOverlay: true)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        switch await ScreenCapture.selectRegion() {
        case .cancelled:
            return .done(toast: nil)
        case .failed(let message):
            return .failure(message)
        case .captured(let capture):
            let image = capture.image
            let messages = await runInBackground { QRCode.decode(image) }
            guard !messages.isEmpty else {
                return .failure("没有识别到二维码或条形码。框选时把整个码都框进去；如果框到的只有桌面背景，"
                                + "请在「系统设置 → 隐私与安全性 → 录屏与系统录音」里允许 Pop。")
            }
            return .card(QRCode.card(for: messages))
        }
    }
}

// MARK: - 图片配色

struct PalettePlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.palette, name: "图片配色", symbol: "paintpalette",
                          summary: "找出图片里的主要颜色，按面积从大到小列出色值，点一下复制", accepts: [.image, .imageFile])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        let image: CGImage?
        if case .image(let data) = content.selection {
            image = TextRecognizer.cgImage(from: data)
        } else {
            image = content.files.first.flatMap(TextRecognizer.cgImage(contentsOf:))
        }
        guard let image else { return .failure("无法读取图片") }
        let swatches = await runInBackground { ColorPalette.extract(from: image) }
        guard !swatches.isEmpty else { return .failure("图片是全透明的，取不出颜色") }
        let rows = swatches.map { swatch in
            ResultCard.Row(label: "占 \(max(Int((swatch.share * 100).rounded()), 1))%", value: swatch.hex)
        }
        return .card(ResultCard(title: "图片配色", detail: "按面积从大到小；点色块复制色值", rows: rows,
                                palette: swatches.map(\.hex)))
    }
}

// MARK: - 终端

struct OpenInTerminalPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.openInTerminal, name: "在终端打开", symbol: "apple.terminal",
                          summary: "在「终端」里打开选中的文件夹（选中文件时打开它所在的文件夹）", accepts: [.files])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let first = content.files.first else { return .failure("没有选中文件") }
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: first.path(percentEncoded: false), isDirectory: &isDirectory)
        guard exists else { return .failure("文件不存在") }
        let folder = isDirectory.boolValue ? first : first.deletingLastPathComponent()
        guard let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else {
            return .failure("找不到「终端」App")
        }
        NSWorkspace.shared.open([folder], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
        return .done(toast: nil)
    }
}
