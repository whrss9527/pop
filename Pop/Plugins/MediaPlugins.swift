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
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US", "ja-JP", "ko-KR"]
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                return .failure(PluginRunError("文字识别失败：\(error.localizedDescription)"))
            }
            let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            return .success(lines.joined(separator: "\n"))
        }
    }

    /// 识别结果卡片：可以复制，也可以接着翻译。
    static func card(title: String, text: String) -> ResultCard {
        ResultCard(title: title, body: text, copyText: text,
                   buttons: [CardButton(title: "翻译", action: .translate(text))])
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

struct ScreenshotOCRPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.screenshotOCR, name: "截图识字", symbol: "viewfinder",
                          summary: "框选屏幕上的一块区域，识别里面的文字", accepts: [], hidesOverlay: true)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
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
            return .failure(error.message)
        }
        // 按 Esc 取消了截图
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return .done(toast: nil) }
        guard let image = TextRecognizer.cgImage(contentsOf: url) else { return .failure("无法读取截图") }
        switch await TextRecognizer.recognize(image) {
        case .success(let text):
            guard !text.isEmpty else {
                return .failure("没有识别到文字。如果截到的只有桌面背景，请在「系统设置 → 隐私与安全性 → 录屏与系统录音」里允许 Pop。")
            }
            return .card(TextRecognizer.card(title: "截图识字", text: text))
        case .failure(let error):
            return .failure(error.message)
        }
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
    /// 显示系统的取色放大镜，按 Esc 取消时返回 nil。
    static func pick() async -> NSColor? {
        await withCheckedContinuation { continuation in
            let sampler = NSColorSampler()
            sampler.show { color in
                // 在回调里引用 sampler，保证取色结束前它不会被释放
                _ = sampler
                continuation.resume(returning: color)
            }
        }
    }
}

struct ColorPickerPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.colorPicker, name: "屏幕取色", symbol: "eyedropper",
                          summary: "吸取屏幕上任意位置的颜色，自动复制 HEX 值", accepts: [], hidesOverlay: true)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let picked = await ScreenColorSampler.pick() else { return .done(toast: nil) }
        guard let color = ColorValue(picked) else { return .failure("无法读取这个颜色") }
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

    static func decode(_ image: CGImage) -> [String] {
        let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
        let features = detector?.features(in: CIImage(cgImage: image)) ?? []
        return features.compactMap { ($0 as? CIQRCodeFeature)?.messageString }
    }
}

struct QRCodePlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.qrCode, name: "二维码", symbol: "qrcode",
                          summary: "把文字或链接生成二维码；选中图片时识别里面的二维码", accepts: [.text, .image, .imageFile])

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
        guard !messages.isEmpty else { return .failure("图片里没有找到二维码") }
        let text = messages.joined(separator: "\n")
        var buttons: [CardButton] = []
        if messages.count == 1, let url = URL(string: text), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) {
            buttons.append(CardButton(title: "打开链接", action: .open(url)))
        }
        return .card(ResultCard(title: "二维码内容", body: text, copyText: text, buttons: buttons))
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
