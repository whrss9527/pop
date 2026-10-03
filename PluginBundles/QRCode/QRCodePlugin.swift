import AppKit
@testable import Pop

/// 插件包「二维码」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopQRCodeEntry)
final class QRCodeEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [QRCodePlugin()]
    }
}

struct QRCodePlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.qrCode, name: String(localized: "二维码"), symbol: "qrcode",
                          summary: String(localized: "把文字或链接生成二维码（英文字母和数字还能生成条形码）；选中图片时识别里面的二维码和条形码"),
                          accepts: [.text, .image, .imageFile])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        if content.kinds.contains(.image) || content.kinds.contains(.imageFile) {
            return await decode(content)
        }
        guard let text = content.text else { return .failure(String(localized: "没有内容")) }
        guard let png = await runInBackground({ QRCode.generate(text) }) else {
            return .failure(String(localized: "内容太长，放不进一个二维码"))
        }
        var buttons = [CardButton(title: String(localized: "复制图片"), action: .copyImage(png))]
        // 英文字母、数字这类内容还能生成条形码
        if QRCode.canMakeBarcode(text) {
            buttons.append(CardButton(title: String(localized: "条形码"), action: .barcode(text)))
        }
        return .card(ResultCard(title: String(localized: "二维码"), detail: String(localized: "\(text.count) 个字符"), image: png,
                                buttons: buttons))
    }

    /// 读图片、认码都在后台：几千万像素的照片要认好一会儿
    @MainActor private func decode(_ content: ClassifiedContent) async -> PluginOutcome {
        let selection = content.selection
        let file = content.files.first
        let messages: [String]? = await runInBackground {
            let image: CGImage?
            if case .image(let data) = selection {
                image = TextRecognizer.cgImage(from: data)
            } else {
                image = file.flatMap(TextRecognizer.cgImage(contentsOf:))
            }
            return image.map(QRCode.decode)
        }
        guard let messages else { return .failure(String(localized: "无法读取图片")) }
        guard !messages.isEmpty else { return .failure(String(localized: "图片里没有找到二维码或条形码")) }
        return .card(QRCode.card(for: messages))
    }
}
